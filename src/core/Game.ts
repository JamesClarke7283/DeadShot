// Top-level game orchestrator.
//
// Owns the engine subsystems and the audio/UI stack, runs the fixed-step rAF
// loop, and drives the state machine: MainMenu -> (ClassEditor | PreMatch) ->
// Playing (a live Match with HUD) -> PostMatch. The dev console (backquote)
// pokes the running match.

import * as THREE from "../three.ts";
import { Renderer } from "./Renderer.ts";
import { Scene } from "./Scene.ts";
import { Camera } from "./Camera.ts";
import { Input } from "./Input.ts";
import { Clock } from "./Clock.ts";
import { AssetLoader } from "./AssetLoader.ts";
import { GamepadController } from "./Gamepad.ts";
import { isTouchDevice, TouchControls } from "../ui/TouchControls.ts";
import { Storage } from "../persistence/Storage.ts";
import { AudioManager } from "../audio/AudioManager.ts";
import { WeaponSFX } from "../audio/WeaponSFX.ts";
import { SpatialSFX } from "../audio/SpatialSFX.ts";
import { MusicPlayer } from "../audio/MusicPlayer.ts";
import { MainMenu } from "../ui/MainMenu.ts";
import { type PreMatchConfig, PreMatchMenu } from "../ui/PreMatchMenu.ts";
import { ClassEditor } from "../ui/ClassEditor.ts";
import { HUD } from "../ui/HUD.ts";
import { DevConsole } from "../ui/DevConsole.ts";
import { button, el } from "../ui/dom.ts";
import { Match, type MatchAudio } from "../game/Match.ts";
import { TDM } from "../game/TDM.ts";
import { FFA } from "../game/FFA.ts";
import { getWeapon } from "../weapons/WeaponDefinition.ts";
import { getCamo } from "../weapons/AttachmentDefinitions.ts";
import type { PlayerScore } from "../game/Mode.ts";

export enum GameState {
  Boot = "Boot",
  MainMenu = "MainMenu",
  ClassEditor = "ClassEditor",
  PreMatch = "PreMatch",
  Playing = "Playing",
  PostMatch = "PostMatch",
}

export interface GameStateHandler {
  enter?(prev: GameState | null): void;
  exit?(next: GameState): void;
  update?(dt: number): void;
}

const FIXED_STEP = 1 / 60;
const MAX_SUBSTEPS = 5;

export class Game {
  readonly renderer: Renderer;
  readonly scene: Scene;
  readonly camera: Camera;
  readonly input: Input;
  readonly clock: Clock;
  readonly assets: AssetLoader;
  readonly storage: Storage;
  readonly audio: AudioManager;

  state: GameState = GameState.Boot;
  match: Match | null = null;

  private handlers = new Map<GameState, GameStateHandler>();
  private accumulator = 0;
  private running = false;
  private rafId = 0;

  private weaponSFX: WeaponSFX;
  private spatialSFX: SpatialSFX;
  private music: MusicPlayer;
  private mainMenu: MainMenu;
  private preMatch: PreMatchMenu;
  private classEditor: ClassEditor;
  private hud: HUD;
  private devConsole: DevConsole;
  private gamepad: GamepadController;
  private touch: TouchControls;
  private uiRoot: HTMLElement;

  private pendingConfig: PreMatchConfig | null = null;
  private killfeedShown = 0;
  private prevPlayerHealth = 100;
  private postResult: {
    winner: string;
    rows: PlayerScore[];
    blue: number;
    red: number;
    mode: "tdm" | "ffa";
  } | null = null;
  private pausePanel: HTMLElement | null = null;
  private postPanel: HTMLElement | null = null;
  private audioStarted = false;
  private streakBound = false;
  private hardcore = false;

  // FPS counter
  private fpsEl: HTMLElement;
  private fpsAccum = 0;
  private fpsFrames = 0;

  private readonly _camPos = new THREE.Vector3();
  private readonly _look = new THREE.Vector3();

  constructor(canvas: HTMLCanvasElement) {
    this.clock = new Clock();
    this.renderer = new Renderer(canvas);
    this.camera = new Camera(canvas);
    this.scene = new Scene();
    this.input = new Input(canvas);
    this.assets = new AssetLoader((frac, url) => this.onLoadProgress(frac, url));
    this.storage = new Storage();

    this.scene.three.add(this.camera.perspective);
    this.renderer.setResizeCallback((_w, _h) => this.camera.resize(this.renderer.aspect));

    // Audio (context starts suspended; resumed on first user gesture).
    const s = this.storage.getSettings();
    this.audio = new AudioManager(this.camera.perspective, {
      master: s.masterVolume,
      sfx: s.sfxVolume,
      music: s.musicVolume,
    });
    this.weaponSFX = new WeaponSFX(this.audio);
    this.spatialSFX = new SpatialSFX(this.audio);
    this.music = new MusicPlayer(this.audio);
    this.camera.setSensitivity(s.sensitivity);

    this.uiRoot = document.getElementById("ui-root") ?? document.body;
    this.mainMenu = new MainMenu(this.uiRoot, {
      onPlay: () => this.setState(GameState.PreMatch),
      onCreateClass: () => this.setState(GameState.ClassEditor),
      onOptions: () => {/* inline in MainMenu */},
      onQuit: () => this.devConsole.println("Quit: close the tab/window."),
    });
    this.preMatch = new PreMatchMenu(this.uiRoot, this.storage, {
      onStart: (cfg) => {
        this.pendingConfig = cfg;
        this.setState(GameState.Playing);
      },
      onBack: () => this.setState(GameState.MainMenu),
    });
    this.classEditor = new ClassEditor(this.uiRoot, this.storage, {
      onBack: () => this.setState(GameState.MainMenu),
    });
    this.hud = new HUD(this.uiRoot);
    this.hud.hide();
    this.devConsole = new DevConsole(this.uiRoot, (cmd) => this.runDevCommand(cmd));
    this.gamepad = new GamepadController(this.input, this.camera);
    this.touch = new TouchControls(this.uiRoot, this.input, this.camera);

    canvas.addEventListener("click", () => {
      this.startAudioOnce();
      if (this.state === GameState.Playing && !this.pausePanel) this.camera.lock();
    });
    // Resume audio on any first interaction (menu clicks count).
    globalThis.addEventListener("pointerdown", () => this.startAudioOnce(), { once: false });

    this.fpsEl = el("div", { class: "fps-counter", parent: this.uiRoot });

    this.installStates();
  }

  private startAudioOnce(): void {
    if (this.audioStarted) return;
    this.audioStarted = true;
    this.audio.resume();
    void this.music.start();
  }

  registerState(state: GameState, handler: GameStateHandler): void {
    this.handlers.set(state, handler);
  }

  setState(next: GameState): void {
    if (next === this.state && this.running) return;
    const prev = this.state;
    this.handlers.get(prev)?.exit?.(next);
    this.state = next;
    this.handlers.get(next)?.enter?.(prev);
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.clock.reset();
    this.setState(GameState.MainMenu);
    this.hideLoading();
    this.rafId = requestAnimationFrame(this.loop);
  }

  stop(): void {
    this.running = false;
    cancelAnimationFrame(this.rafId);
  }

  private loop = (): void => {
    if (!this.running) return;
    const dt = this.clock.getDelta();
    const handler = this.handlers.get(this.state);

    this.accumulator += dt;
    let substeps = 0;
    while (this.accumulator >= FIXED_STEP && substeps < MAX_SUBSTEPS) {
      this.accumulator -= FIXED_STEP;
      substeps++;
    }
    if (substeps === MAX_SUBSTEPS) this.accumulator = 0;

    handler?.update?.(dt);
    this.scene.update(this.camera.perspective.position);
    this.renderer.render(this.scene.three, this.camera.perspective);

    this.input.endFrame();
    this.updateFps(dt);
    this.rafId = requestAnimationFrame(this.loop);
  };

  private installStates(): void {
    this.registerState(GameState.MainMenu, {
      enter: () => {
        this.camera.unlock();
        this.mainMenu.show();
      },
      exit: () => this.mainMenu.hide(),
    });

    this.registerState(GameState.ClassEditor, {
      enter: () => this.classEditor.show(),
      exit: () => this.classEditor.hide(),
    });

    this.registerState(GameState.PreMatch, {
      enter: () => this.preMatch.show(),
      exit: () => this.preMatch.hide(),
    });

    this.registerState(GameState.Playing, {
      enter: () => {
        this.startMatch();
        if (isTouchDevice()) this.touch.setVisible(true);
      },
      update: (dt) => this.updatePlaying(dt),
      exit: () => {
        this.hud.hide();
        this.touch.setVisible(false);
        this.match?.dispose();
        this.match = null;
        this.removePause();
        this.music.setIntensity(0.2);
        this.music.setDuck(0);
      },
    });

    this.registerState(GameState.PostMatch, {
      enter: () => this.showPostMatch(),
      exit: () => this.removePostMatch(),
    });
  }

  // ---- Match lifecycle ----
  private startMatch(): void {
    const cfg = this.pendingConfig;
    if (!cfg) {
      this.setState(GameState.MainMenu);
      return;
    }
    const loadout = this.storage.getClass(cfg.classSlot);
    const primary = getWeapon(loadout.primary.weaponId);
    const camo = getCamo(loadout.camo).color;
    const mode = cfg.mode === "tdm" ? TDM : FFA;

    const matchAudio: MatchAudio = {
      playerShot: (id) => this.weaponSFX.shot(id),
      playerReload: () => this.weaponSFX.reload(),
      hitMarker: (hs) => {
        this.weaponSFX.hitMarker(hs);
        this.hud.hitMarker(hs);
      },
      enemyShot: (id, pos) => {
        this.camera.perspective.getWorldPosition(this._camPos);
        if (pos.distanceTo(this._camPos) < 90) this.spatialSFX.shotAt(id, pos);
      },
      explosion: (pos, radius) => this.spatialSFX.explosionAt(pos, Math.min(2, radius / 4)),
    };

    this.match = new Match(this.scene, this.camera, this.input, {
      mapId: cfg.mapId,
      mode,
      botCount: cfg.botCount,
      difficulty: cfg.difficulty,
      hasPlayer: true,
      playerWeaponDef: primary,
      playerName: "You",
      playerAttachments: loadout.primary.attachments,
      playerCamo: camo,
      playerStreaks: loadout.streaks,
      playerTactical: loadout.tactical,
      playerLethal: loadout.lethal,
      respawnDelay: 4,
      warmup: 2,
      hardcore: cfg.hardcore,
      audio: matchAudio,
    });
    this.match.build();
    this.killfeedShown = 0;
    this.prevPlayerHealth = this.match.player?.maxHealth ?? 100;
    this.streakBound = false;
    this.hardcore = cfg.hardcore;
    if (this.hardcore) this.hud.hide();
    else this.hud.show();
    this.music.setIntensity(0.4);
    this.startAudioOnce();
  }

  private updatePlaying(dt: number): void {
    const m = this.match;
    if (!m) return;
    if (this.pausePanel) return; // frozen while paused
    this.gamepad.update(dt);
    this.touch.update();
    m.update(dt);

    const p = m.player;
    if (!p) return;

    // Bind streak-menu selection once.
    if (!this.streakBound) {
      this.streakBound = true;
      this.hud.streakMenu.onSelect((id) => m.activatePlayerStreak(id));
    }

    const blue = m.scoreboard.teamKills("blue");
    const red = m.scoreboard.teamKills("red");

    // HUD readouts (hidden entirely in hardcore).
    if (!this.hardcore) {
      this.hud.setHealth(p.health, p.maxHealth);
      this.hud.setAmmo(p.weapon.magazine, p.weapon.reserve);
      this.hud.setWeaponName(p.weapon.def.name);
      this.hud.setScoreline(blue, red, m.modeId);
      this.hud.setTimer(m.timeLeft);

      // Streak progress.
      const score = m.streaks.scoreOf(p.id);
      const lo = m.streaks.loadout(p.id)
        .map((id) => m.streaks.def(id))
        .filter((d): d is NonNullable<typeof d> => !!d)
        .sort((a, b) => a.cost - b.cost);
      const next = lo.find((d) => d.cost > score) ?? null;
      this.hud.setStreakProgress(score, next?.name ?? null, next?.cost ?? null);

      // Crosshair spread.
      const spread = (1 - p.weapon.adsFactor) * 18 + (this.input.isDown("fire") ? 10 : 0);
      this.hud.setSpread(spread);

      // Minimap.
      this.camera.getLookDirection(this._look);
      const yaw = Math.atan2(this._look.x, this._look.z);
      const blips = m.activePings(p.team).map((v) => ({ x: v.x, z: v.z, enemy: true }));
      this.hud.setMinimap(
        { x: p.feet.x, z: p.feet.z, yaw },
        blips,
        m.bounds,
        m.isCounterUAV(p.team),
      );

      // Killfeed.
      while (this.killfeedShown < m.killfeed.length) {
        this.hud.addKill(m.killfeed[this.killfeedShown++]);
      }

      // Damage indicator.
      if (p.health < this.prevPlayerHealth && p.lastDamage?.sourceId !== undefined) {
        const attacker = m.scoreboard.get(p.lastDamage.sourceId);
        void attacker;
        const src = this.findActorPos(p.lastDamage.sourceId);
        if (src) {
          const ang = Math.atan2(src.x - p.feet.x, src.z - p.feet.z) - yaw;
          this.hud.damageFrom(ang);
        }
      }
      this.prevPlayerHealth = p.health;

      // Scoreboard (Tab).
      const showSB = this.input.isDown("scoreboard");
      this.hud.showScoreboard(showSB);
      if (showSB) this.hud.updateScoreboard(m.scoreboard.all(), blue, red, m.modeId);

      // Streak wheel (Z).
      const showStreaks = this.input.isDown("streaks");
      this.hud.streakMenu.setVisible(showStreaks);
      if (showStreaks) {
        this.hud.streakMenu.setOptions(
          m.streaks.loadout(p.id).map((id) => ({
            id,
            name: m.streaks.def(id)?.name ?? id,
            available: m.streaks.isAvailable(p.id, id),
          })),
        );
      }
    } // end !hardcore HUD block

    // Throwables.
    if (this.input.wasPressed("lethal")) m.playerThrowLethal();
    if (this.input.wasPressed("tactical")) m.playerThrowTactical();

    // Music duck on low health.
    this.music.setDuck(p.alive && p.health < 35 ? 0.7 : 0);

    // Pause.
    if (this.input.wasPressed("pause")) this.togglePause();

    if (m.state === "end") {
      this.postResult = {
        winner: m.formatWinner(),
        rows: m.scoreboard.all(),
        blue,
        red,
        mode: m.modeId,
      };
      this.setState(GameState.PostMatch);
    }
  }

  private findActorPos(id: number): THREE.Vector3 | null {
    const m = this.match;
    if (!m) return null;
    if (m.player && m.player.id === id) return m.player.feet;
    const bot = m.bots.find((b) => b.id === id);
    return bot ? bot.feet : null;
  }

  // ---- Pause overlay ----
  private togglePause(): void {
    if (this.pausePanel) {
      this.removePause();
    } else {
      this.camera.unlock();
      this.pausePanel = el("div", {
        class: "screen",
        parent: this.uiRoot,
        style: {
          position: "fixed",
          inset: "0",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "16px",
          background: "rgba(5,7,10,0.7)",
          zIndex: "90",
        },
        children: [
          el("div", { text: "PAUSED", style: { font: "900 48px system-ui", color: "#b6ff5e" } }),
          button("Resume", () => this.removePause()),
          button("Quit to Menu", () => this.setState(GameState.MainMenu)),
        ],
      });
    }
  }
  private removePause(): void {
    this.pausePanel?.remove();
    this.pausePanel = null;
  }

  // ---- Post match ----
  private showPostMatch(): void {
    this.camera.unlock();
    const r = this.postResult;
    const rows = r?.rows ?? [];
    const table = rows.slice(0, 12).map((p) =>
      el("div", {
        text: `${p.name}   ${p.kills}/${p.deaths}/${p.assists}   ${p.score}`,
        style: { font: "14px monospace", color: p.isPlayer ? "#ffd166" : "#cfe" },
      })
    );
    this.postPanel = el("div", {
      class: "screen",
      parent: this.uiRoot,
      style: {
        position: "fixed",
        inset: "0",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "12px",
        background: "radial-gradient(circle at 50% 35%, #14202c, #05070a 70%)",
        zIndex: "95",
      },
      children: [
        el("div", {
          text: r?.winner ?? "Match Over",
          style: { font: "900 44px system-ui", color: "#b6ff5e", textShadow: "3px 3px 0 #000" },
        }),
        el("div", {
          style: { display: "flex", flexDirection: "column", gap: "4px" },
          children: table,
        }),
        button("Continue", () => this.setState(GameState.MainMenu)),
      ],
    });
  }
  private removePostMatch(): void {
    this.postPanel?.remove();
    this.postPanel = null;
  }

  // ---- Dev console ----
  private runDevCommand(cmd: string): string {
    const [verb, ...args] = cmd.split(/\s+/);
    const m = this.match;
    switch (verb) {
      case "help":
        return "commands: map <id>, give <streakId>, nuke, kill, heal, bots, state";
      case "state":
        return `state=${this.state} match=${m ? m.state : "none"}`;
      case "map":
        if (!m || !m.player) return "no active match";
        m.activateStreak({ id: m.player.id, team: m.player.team }, "uav");
        return "(map switching only in pre-match; gave UAV instead)";
      case "give":
        if (!m || !m.player) return "no active match";
        try {
          m.activateStreak({ id: m.player.id, team: m.player.team }, args[0]);
          return `gave ${args[0]}`;
        } catch (e) {
          return e instanceof Error ? e.message : "error";
        }
      case "nuke":
        if (!m || !m.player) return "no active match";
        m.activateStreak({ id: m.player.id, team: m.player.team }, "nuke");
        return "nuke incoming";
      case "heal":
        if (m?.player) m.player.health = m.player.maxHealth;
        return "healed";
      case "kill":
        if (m?.player) {
          m.player.applyDamage({ amount: 999, headshot: false, sourceTeam: m.player.team });
        }
        return "ouch";
      case "bots":
        return m ? `${m.bots.length} bots` : "no match";
      default:
        return `unknown: ${verb}`;
    }
  }

  private updateFps(dt: number): void {
    this.fpsAccum += dt;
    this.fpsFrames++;
    if (this.fpsAccum >= 0.5) {
      this.fpsEl.textContent = `${(this.fpsFrames / this.fpsAccum).toFixed(0)} FPS`;
      this.fpsAccum = 0;
      this.fpsFrames = 0;
    }
  }

  private onLoadProgress(frac: number, _url: string): void {
    const fill = document.getElementById("loading-fill");
    if (fill) fill.style.width = `${Math.round(frac * 100)}%`;
  }

  private hideLoading(): void {
    document.getElementById("loading")?.classList.add("hidden");
  }
}
