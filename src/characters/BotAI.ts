// BotAI: per-bot decision making + actuation.
//
// Each frame the brain selects a target (nearest visible enemy), aims with a
// difficulty-tuned error + reaction delay, fires its weapon (real hitscan via the
// world, so bots damage each other and the player), navigates the waypoint graph
// toward enemies or patrol goals, retreats when low on health, and melees at
// point-blank range. Bots fully simulate vs. each other.

import * as THREE from "../three.ts";
import type { Actor, Bot, BotContext } from "./Bot.ts";
import type { Aim } from "../weapons/combat.ts";

export type Difficulty = "recruit" | "regular" | "veteran";

interface DiffParams {
  aimErrorDeg: number;
  reaction: number;
  viewRange: number;
}

const DIFFICULTY: Record<Difficulty, DiffParams> = {
  recruit: { aimErrorDeg: 18, reaction: 0.55, viewRange: 45 },
  regular: { aimErrorDeg: 9, reaction: 0.32, viewRange: 65 },
  veteran: { aimErrorDeg: 3, reaction: 0.16, viewRange: 85 },
};

const RETREAT_HEALTH = 30;
const MELEE_RANGE = 2.2;
const MELEE_DAMAGE = 55;
const DEG2RAD = Math.PI / 180;

const _eye = new THREE.Vector3();
const _tgtEye = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _away = new THREE.Vector3();

export class BotAI {
  private params: DiffParams;
  private target: Actor | null = null;
  private reactionTimer = 0;
  private suppressTimer = 0;
  private errorTimer = 0;
  private meleeCooldown = 0;
  private repathTimer = 0;
  private readonly error = new THREE.Vector3();
  private readonly aimNoise: { x: number; y: number } = { x: 0, y: 0 };

  constructor(difficulty: Difficulty) {
    this.params = DIFFICULTY[difficulty];
  }

  update(bot: Bot, dt: number, ctx: BotContext): void {
    this.reactionTimer += dt;
    this.errorTimer -= dt;
    this.meleeCooldown -= dt;
    this.suppressTimer -= dt;
    this.repathTimer -= dt;

    bot.eyePosition(_eye);
    const target = this.selectTarget(bot, ctx);

    if (target) {
      this.engage(bot, target, dt, ctx);
    } else {
      this.patrol(bot, dt, ctx);
    }

    // Auto-reload when dry.
    if (bot.weapon.magazine <= 0 && bot.weapon.reserve > 0) bot.weapon.reload();
  }

  // ---- Target selection ----
  private selectTarget(bot: Bot, ctx: BotContext): Actor | null {
    // Keep the current target if still valid.
    if (this.target && this.target.alive && this.visible(bot, this.target, ctx)) {
      return this.target;
    }
    let best: Actor | null = null;
    let bestScore = -Infinity;
    for (const a of ctx.actors) {
      if (a === (bot as unknown as Actor) || !a.alive) continue;
      if (bot.team !== "ffa" && a.team === bot.team) continue;
      a.position(_tgtEye);
      const dist = _tgtEye.distanceTo(bot.feet);
      if (dist > this.params.viewRange) continue;
      if (!this.visible(bot, a, ctx)) continue;
      // Closer enemies score higher (threat weighting).
      const score = -dist;
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    if (best && best !== this.target) this.reactionTimer = 0; // reaction delay on new target
    this.target = best;
    return best;
  }

  /** Line-of-sight from the bot's eye to a target's eye. */
  private visible(bot: Bot, target: Actor, ctx: BotContext): boolean {
    bot.eyePosition(_eye);
    target.eyePosition(_tgtEye);
    _dir.copy(_tgtEye).sub(_eye);
    const dist = _dir.length();
    if (dist < 1e-3) return true;
    _dir.multiplyScalar(1 / dist);
    const hit = ctx.world.raycast(_eye, _dir, dist + 0.5, bot.object3d);
    if (!hit) return true;
    if (hit.target === (target as unknown)) return true;
    return hit.distance >= dist - 0.6; // first solid surface is past the target
  }

  // ---- Combat ----
  private engage(bot: Bot, target: Actor, dt: number, ctx: BotContext): void {
    bot.eyePosition(_eye);
    target.eyePosition(_tgtEye);
    _dir.copy(_tgtEye).sub(_eye);
    const dist = _dir.length();
    _dir.normalize();

    // Face the enemy.
    bot.yaw = Math.atan2(_dir.x, _dir.z);

    // Aim with difficulty error (re-jittered periodically).
    if (this.errorTimer <= 0) {
      this.errorTimer = 0.12;
      const r = this.params.aimErrorDeg * DEG2RAD;
      this.aimNoise.x = (Math.random() * 2 - 1) * r;
      this.aimNoise.y = (Math.random() * 2 - 1) * r;
    }
    applyAimError(_dir, this.aimNoise.x, this.aimNoise.y, this.error);
    bot.aimDir.copy(this.error);

    const effectiveRange = Math.min(this.params.viewRange, bot.weapon.stats.range.far + 8);
    const ready = this.reactionTimer >= this.params.reaction;

    // Melee at point-blank.
    if (dist <= MELEE_RANGE && this.meleeCooldown <= 0) {
      this.meleeCooldown = 0.8;
      target.applyDamage({
        amount: MELEE_DAMAGE,
        headshot: false,
        sourceTeam: bot.team,
        sourceId: bot.id,
        weaponId: "melee",
      });
    }

    const wantFire = ready && dist <= effectiveRange && bot.weapon.magazine > 0;
    bot.firing = wantFire;
    if (wantFire) this.suppressTimer = 0.3;

    // Movement: close the gap, retreat if hurt, otherwise hold + slight strafe.
    bot.moving = false;
    if (bot.health <= RETREAT_HEALTH) {
      _away.set(bot.feet.x - _tgtEye.x, 0, bot.feet.z - _tgtEye.z).normalize();
      const dest = new THREE.Vector3(bot.feet.x + _away.x * 4, 0, bot.feet.z + _away.z * 4);
      bot.moving = bot.stepToward(dest, bot.moveSpeed(), dt, ctx);
    } else if (dist > effectiveRange * 0.7) {
      const dest = new THREE.Vector3(_tgtEye.x, 0, _tgtEye.z);
      bot.moving = bot.stepToward(dest, bot.moveSpeed(), dt, ctx);
    }

    this.fire(bot, dt, ctx);
  }

  // ---- Patrol / navigation ----
  private patrol(bot: Bot, dt: number, ctx: BotContext): void {
    bot.firing = false;
    bot.weapon.setTrigger(false);

    if (bot.path.length === 0 || bot.pathIndex >= bot.path.length || this.repathTimer <= 0) {
      this.repathTimer = 2 + Math.random() * 2;
      const gx = ctx.bounds.minX + Math.random() * (ctx.bounds.maxX - ctx.bounds.minX);
      const gz = ctx.bounds.minZ + Math.random() * (ctx.bounds.maxZ - ctx.bounds.minZ);
      const goal = new THREE.Vector3(gx, ctx.groundAt(gx, gz), gz);
      bot.path = ctx.navigator.findPath(bot.feet, goal);
      bot.pathIndex = 0;
    }

    if (bot.path.length > 0 && bot.pathIndex < bot.path.length) {
      const node = bot.path[bot.pathIndex];
      _dir.set(node.x - bot.feet.x, 0, node.z - bot.feet.z);
      if (_dir.lengthSq() > 1e-4) {
        _dir.normalize();
        bot.yaw = Math.atan2(_dir.x, _dir.z);
        bot.aimDir.copy(_dir);
      }
      bot.moving = bot.stepToward(node, bot.moveSpeed() * 0.8, dt, ctx);
      if (!bot.moving) bot.pathIndex++;
    } else {
      bot.moving = false;
    }
    // Update weapon (no fire) so reloads/cooldowns still tick.
    this.fire(bot, dt, ctx);
  }

  private fire(bot: Bot, dt: number, ctx: BotContext): void {
    bot.weapon.setTrigger(bot.firing);
    const aim: Aim = {
      origin: _eye.clone(),
      direction: bot.aimDir.clone().normalize(),
      applyRecoil: () => {}, // bots don't fight recoil; aim error models their spread
    };
    bot.eyePosition(aim.origin);
    bot.weapon.update(dt, aim, ctx.world, ctx.vfx);
  }
}

/** Rotate a unit direction by yaw/pitch error (radians) into `out`. */
function applyAimError(
  dir: THREE.Vector3,
  yawErr: number,
  pitchErr: number,
  out: THREE.Vector3,
): void {
  // Build a basis: forward = dir, right = forward x up, up' = right x forward.
  const up = Math.abs(dir.y) > 0.99 ? new THREE.Vector3(1, 0, 0) : new THREE.Vector3(0, 1, 0);
  const right = new THREE.Vector3().crossVectors(dir, up).normalize();
  const upN = new THREE.Vector3().crossVectors(right, dir).normalize();
  out.copy(dir)
    .addScaledVector(right, Math.tan(yawErr))
    .addScaledVector(upN, Math.tan(pitchErr))
    .normalize();
}
