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

  readonly object3d = new THREE.Object3D();
  readonly feet = new THREE.Vector3();
  weapon!: Weapon;
  lastDamage?: DamageInfo;
  private deathTimer = 0;

  private viewmodel: WeaponViewmodel;
  private camoColor: number;
  private attachments: ReadonlyArray<Attachment | string>;

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

  setWeapon(def: WeaponDef): void {
    this.weapon = new Weapon(def, this.attachments, {
      team: this.team,
      isPlayer: true,
      weaponId: def.id,
      id: this.id,
    }, {
      onShot: () => this.viewmodel.onShot(),
      onReloadStart: (_empty, dur) => this.viewmodel.startReload(dur),
    });
    this.viewmodel.setWeapon(def, this.camoColor);
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
    // Health regen after REGEN_DELAY seconds out of damage.
    this.regenTimer += dt;
    if (this.regenTimer >= REGEN_DELAY && this.health < this.maxHealth) {
      this.health = Math.min(this.maxHealth, this.health + REGEN_RATE * dt);
    }

    // Aim from camera.
    this.camera.perspective.getWorldPosition(this.origin);
    this.camera.getLookDirection(this.dir);

    const locked = this.camera.isLocked;
    const ads = this.input.isDown("ads") && locked;
    this.viewmodel.setADS(ads, this.weapon.stats.adsTime);
    this.weapon.adsFactor = this.viewmodel.adsFactor;
    this.weapon.setTrigger(this.input.isDown("fire") && locked);
    if (this.input.wasPressed("reload")) this.weapon.reload();
    this.weapon.update(dt, this.aim, ctx.world, ctx.vfx);
    this.viewmodel.update(dt);

    // Movement.
    if (locked) {
      const speed = (this.input.isDown("sprint") ? 7.5 : 5) * (this.weapon.stats.mobility / 80);
      const fb = this.input.axis("back", "forward");
      const lr = this.input.axis("left", "right");
      if (fb !== 0 || lr !== 0) {
        this.camera.getForward(this.fwd);
        const fx = this.fwd.x, fz = this.fwd.z;
        const rx = fz, rz = -fx; // right = forward x up
        this.feet.x += (fx * fb + rx * lr) * speed * dt;
        this.feet.z += (fz * fb + rz * lr) * speed * dt;
      }
      this.feet.y = ctx.groundAt(this.feet.x, this.feet.z);
      ctx.collision.resolve(this.feet, RADIUS, HEIGHT);
      this.camera.perspective.position.set(this.feet.x, this.feet.y + EYE_HEIGHT, this.feet.z);
    }
    this.object3d.position.copy(this.feet);
  }

  private regenTimer = REGEN_DELAY;

  dispose(): void {
    this.viewmodel.dispose();
  }
}
