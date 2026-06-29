// The human player as a match Actor.
//
// Wraps the camera + input into a first-person combatant: collision-resolved
// walking, the equipped weapon + viewmodel (ADS, recoil, reload), 100 HP with
// regen-after-delay, and damage screen feedback. Implements Actor + DamageTarget
// so bots can target/hit the player and the scoreboard can track them.

import * as THREE from "../three.ts";
import type { Camera } from "../core/Camera.ts";
import type { Input } from "../core/Input.ts";
import type { ScreenEffectsApi } from "../render/ScreenEffects.ts";
import type { Actor } from "../characters/Bot.ts";
import { Weapon } from "../weapons/Weapon.ts";
import type { WeaponDef } from "../weapons/WeaponDefinition.ts";
import type { Attachment } from "../weapons/AttachmentDefinitions.ts";
import { WeaponViewmodel } from "../weapons/WeaponViewmodel.ts";
import type { Aim, DamageInfo, VFXSink, WorldQuery } from "../weapons/combat.ts";
import type { CollisionWorld } from "../maps/Collision.ts";
import type { TeamId } from "../core/types.ts";

const EYE_HEIGHT = 1.7;
const RADIUS = 0.4;
const HEIGHT = 1.8;
const REGEN_DELAY = 5;
const REGEN_RATE = 35; // hp/sec

export interface PlayerContext {
  world: WorldQuery;
  vfx: VFXSink;
  collision: CollisionWorld;
  groundAt(x: number, z: number): number;
}

export class Player implements Actor {
  readonly id: number;
  team: TeamId;
  readonly isPlayer = true;
  alive = true;
  health = 100;
  maxHealth = 100;
  kills = 0;
  deaths = 0;
  regenEnabled = true;

  readonly object3d = new THREE.Object3D();
  readonly feet = new THREE.Vector3();
  /** Carried weapons (slot 0 = primary, slot 1 = secondary). */
  weapons: Weapon[] = [];
  private slotAttachments: ReadonlyArray<Attachment | string>[] = [];
  private currentSlot = 0;
  /** The currently-equipped weapon (mutating its fields is fine). */
  get weapon(): Weapon {
    return this.weapons[this.currentSlot];
  }
  lastDamage?: DamageInfo;
  private deathTimer = 0;

  private viewmodel: WeaponViewmodel;
  private camoColor: number;
  private attachments: ReadonlyArray<Attachment | string>;
  events?: {
    onShot?(weaponId: string): void;
    onReload?(): void;
    onHit?(headshot: boolean, killed: boolean): void;
  };

  private readonly origin = new THREE.Vector3();
  private readonly dir = new THREE.Vector3();
  private readonly fwd = new THREE.Vector3();
  private readonly aim: Aim;

  constructor(
    private camera: Camera,
    private input: Input,
    private screen: ScreenEffectsApi,
    opts: {
      id: number;
      team: TeamId;
      weaponDef: WeaponDef;
      attachments?: ReadonlyArray<Attachment | string>;
      camoColor?: number;
    },
  ) {
    this.id = opts.id;
    this.team = opts.team;
    this.attachments = opts.attachments ?? [];
    this.camoColor = opts.camoColor ?? 0x2b2f36;
    this.viewmodel = new WeaponViewmodel(camera.perspective);
    this.aim = {
      origin: this.origin,
      direction: this.dir,
      applyRecoil: (p, y) => this.camera.applyRecoil(p, y),
    };
    this.setWeapon(opts.weaponDef);
  }

  /** Construct a Weapon wired to this player's viewmodel + audio/hitmarker hooks. */
  private buildWeapon(def: WeaponDef, attachments: ReadonlyArray<Attachment | string>): Weapon {
    return new Weapon(def, attachments, {
      team: this.team,
      isPlayer: true,
      weaponId: def.id,
      id: this.id,
    }, {
      onShot: () => {
        this.viewmodel.onShot();
        this.events?.onShot?.(def.id);
      },
      onReloadStart: (_empty, dur) => {
        this.viewmodel.startReload(dur);
        this.events?.onReload?.();
      },
      onHit: (headshot, killed) => this.events?.onHit?.(headshot, killed),
    });
  }

  /** Single-weapon loadout (kept for callers that only have a primary). */
  setWeapon(def: WeaponDef): void {
    this.weapons = [this.buildWeapon(def, this.attachments)];
    this.slotAttachments = [this.attachments];
    this.currentSlot = 0;
    this.viewmodel.setWeapon(def, this.camoColor, this.attachments);
  }

  /** Two-weapon loadout: primary in slot 0, secondary in slot 1. */
  setLoadout(
    primaryDef: WeaponDef,
    secondaryDef: WeaponDef,
    primaryAttachments: ReadonlyArray<Attachment | string> = this.attachments,
    secondaryAttachments: ReadonlyArray<Attachment | string> = [],
  ): void {
    this.weapons = [
      this.buildWeapon(primaryDef, primaryAttachments),
      this.buildWeapon(secondaryDef, secondaryAttachments),
    ];
    this.slotAttachments = [primaryAttachments, secondaryAttachments];
    this.currentSlot = 0;
    this.viewmodel.setWeapon(primaryDef, this.camoColor, primaryAttachments);
  }

  /** Cycle carried weapons (dir +1 / -1) with a quick swap-in delay. */
  switchWeapon(dir: number): void {
    const n = this.weapons.length;
    if (n < 2) return;
    this.currentSlot = (((this.currentSlot + dir) % n) + n) % n;
    this.weapon.swapIn();
    this.viewmodel.setWeapon(
      this.weapon.def,
      this.camoColor,
      this.slotAttachments[this.currentSlot] ?? [],
    );
  }

  /** Pick up a dropped weapon into the current slot, keeping its leftover ammo. */
  equipDropped(def: WeaponDef, magazine: number, reserve: number): void {
    const w = this.buildWeapon(def, []);
    w.magazine = magazine;
    w.reserve = reserve;
    this.weapons[this.currentSlot] = w;
    this.slotAttachments[this.currentSlot] = [];
    w.swapIn();
    this.viewmodel.setWeapon(def, this.camoColor, []);
  }

  // ---- Actor / DamageTarget ----
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + 1.0);
  }
  eyePosition(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + EYE_HEIGHT);
  }
  isHead(): boolean {
    return false; // MatchWorld reports headshots analytically
  }
  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    this.health -= info.amount;
    this.lastDamage = info;
    this.regenTimer = 0;
    this.screen.tint("rgb(180,0,0)", Math.min(0.6, info.amount / 60), 0.5);
    if (this.health <= 0) {
      this.health = 0;
      this.alive = false;
      this.deaths++;
      this.deathTimer = 0;
    }
  }

  get timeDead(): number {
    return this.deathTimer;
  }

  /** Hardcore: 30 HP, no regen. */
  setHardcore(): void {
    this.maxHealth = 30;
    this.health = 30;
    this.regenEnabled = false;
  }

  spawnAt(pos: THREE.Vector3, yaw = 0): void {
    this.feet.copy(pos);
    this.feet.y = pos.y;
    this.alive = true;
    this.health = this.maxHealth;
    this.deathTimer = 0;
    this.camera.perspective.position.set(this.feet.x, this.feet.y + EYE_HEIGHT, this.feet.z);
    void yaw;
  }

  update(dt: number, ctx: PlayerContext): void {
    if (!this.alive) {
      this.deathTimer += dt;
      return;
    }
    // Health regen after REGEN_DELAY seconds out of damage (off in hardcore).
    this.regenTimer += dt;
    if (this.regenEnabled && this.regenTimer >= REGEN_DELAY && this.health < this.maxHealth) {
      this.health = Math.min(this.maxHealth, this.health + REGEN_RATE * dt);
    }

    // Mouse wheel switches between carried weapons.
    const wheel = this.input.consumeWheel();
    if (wheel !== 0) this.switchWeapon(wheel > 0 ? 1 : -1);

    // Aim from camera.
    this.camera.perspective.getWorldPosition(this.origin);
    this.camera.getLookDirection(this.dir);

    // Mouse-look needs pointer lock (PointerLockControls); movement/fire work
    // regardless so gamepad/touch (which drive look separately) also play.
    const ads = this.input.isDown("ads");
    this.viewmodel.setADS(ads, this.weapon.stats.adsTime);
    this.weapon.adsFactor = this.viewmodel.adsFactor;
    this.weapon.setTrigger(this.input.isDown("fire"));
    if (this.input.wasPressed("reload")) this.weapon.reload();
    this.weapon.update(dt, this.aim, ctx.world, ctx.vfx);
    this.viewmodel.update(dt);

    // Movement.
    const speed = (this.input.isDown("sprint") ? 7.5 : 5) * (this.weapon.stats.mobility / 80);
    const fb = this.input.axis("back", "forward");
    const lr = this.input.axis("left", "right");
    if (fb !== 0 || lr !== 0) {
      this.camera.getForward(this.fwd);
      const fx = this.fwd.x, fz = this.fwd.z;
      const rx = -fz, rz = fx; // right = forward × up (D / → strafes right)
      this.feet.x += (fx * fb + rx * lr) * speed * dt;
      this.feet.z += (fz * fb + rz * lr) * speed * dt;
    }
    this.feet.y = ctx.groundAt(this.feet.x, this.feet.z);
    ctx.collision.resolve(this.feet, RADIUS, HEIGHT);
    this.camera.perspective.position.set(this.feet.x, this.feet.y + EYE_HEIGHT, this.feet.z);
    this.object3d.position.copy(this.feet);
  }

  private regenTimer = REGEN_DELAY;

  dispose(): void {
    this.viewmodel.dispose();
  }
}
