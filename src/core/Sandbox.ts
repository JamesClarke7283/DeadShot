// Phase 1-5 sandbox: loads the DesertTown map and wires the full player loop —
// collision-resolved walking on the terrain, the weapon system (hitscan + recoil
// + viewmodel + RPG), throwable tacticals/lethals, screen effects, and a couple
// of damageable demo bots. Replaced by the real Match in Phase 7.
//
// Debug (from the browser console via window.deadshot.sandbox):
//   sandbox.throwLethal("frag" | "c4" | "molotov" | ...)
//   sandbox.throwTactical("flashbang" | "smoke" | ...)
//   sandbox.detonateC4()

import * as THREE from "../three.ts";
import type { Scene } from "./Scene.ts";
import type { Camera } from "./Camera.ts";
import type { Input } from "./Input.ts";
import type { AssetLoader } from "./AssetLoader.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { VFX } from "../render/VFX.ts";
import { ScreenEffects } from "../render/ScreenEffects.ts";
import { createCharacter } from "../characters/CharacterFactory.ts";
import type { Character } from "../characters/Character.ts";
import { getWeapon, WEAPONS } from "../weapons/WeaponDefinition.ts";
import { Weapon } from "../weapons/Weapon.ts";
import { WeaponViewmodel } from "../weapons/WeaponViewmodel.ts";
import { ProjectilePool } from "../weapons/Projectile.ts";
import { Rocket } from "../weapons/Rocket.ts";
import type {
  Aim,
  DamageInfo,
  DamageTarget,
  RaycastHit,
  ShooterTag,
  WorldQuery,
} from "../weapons/combat.ts";
import type { TeamId } from "./types.ts";
import { getMap, MAPS } from "../maps/maps.ts";
import type { MapBuild } from "../maps/MapDefinition.ts";
import { EquipmentManager, type LethalId, type TacticalId } from "../tacticals/EquipmentManager.ts";
import type { EquipmentContext } from "../tacticals/Equipment.ts";

const EYE_HEIGHT = 1.7;
const PLAYER_RADIUS = 0.4;
const PLAYER_HEIGHT = 1.8;

export class Sandbox {
  private vfx: VFX;
  private screen: ScreenEffects;
  private world: SandboxWorld;
  private pool: ProjectilePool;
  private viewmodel: WeaponViewmodel;
  private weapon!: Weapon;
  private weaponIndex = 0;
  private chars: Character[] = [];
  private aim: Aim;
  private equipment!: EquipmentManager;
  private map: MapBuild | null = null;
  private mapId = "desert_town";
  private assets: AssetLoader | null = null;
  private elapsed = 0;
  private lastG = -1;

  private currentTactical: TacticalId = "flashbang";
  private currentLethal: LethalId = "frag";

  private readonly shooter: ShooterTag = { team: "blue", isPlayer: true, weaponId: "m4" };
  private readonly feet = new THREE.Vector3(0, 0, 8);
  private readonly origin = new THREE.Vector3();
  private readonly dir = new THREE.Vector3();
  private readonly tmp = new THREE.Vector3();

  constructor(
    private scene: Scene,
    private camera: Camera,
    private input: Input,
  ) {
    this.vfx = new VFX(scene.three);
    this.screen = new ScreenEffects();
    this.world = new SandboxWorld(scene, this.vfx);
    this.pool = new ProjectilePool(scene.dynamicRoot);
    this.world.setRocketSpawner((origin, dir, owner) => {
      const def = getWeapon(owner.weaponId);
      if (!def.rocket) return;
      const rocket = new Rocket(def.rocket, owner);
      rocket.init({
        position: origin.clone(),
        velocity: dir.clone().multiplyScalar(def.rocket.speed),
        gravity: 3,
        maxLifetime: 6,
        maxRange: 300,
      });
      this.pool.spawn(rocket);
    });
    this.viewmodel = new WeaponViewmodel(camera.perspective);
    this.aim = {
      origin: this.origin,
      direction: this.dir,
      applyRecoil: (p, y) => this.camera.applyRecoil(p, y),
    };
  }

  /** Switch to a different map by id and rebuild (debug / future menu). */
  loadMap(id: string): void {
    this.mapId = id;
    if (this.assets) this.build(this.assets);
  }

  /** Cycle to the next map in the registry (debug). */
  cycleMap(): string {
    const i = MAPS.findIndex((m) => m.id === this.mapId);
    this.mapId = MAPS[(i + 1) % MAPS.length].id;
    if (this.assets) this.build(this.assets);
    return this.mapId;
  }

  build(assets: AssetLoader): void {
    this.assets = assets;
    // Clear any previous dynamic state (so build is re-runnable for map swaps).
    for (const c of this.chars) {
      this.scene.dynamicRoot.remove(c.root);
      c.dispose();
    }
    this.chars = [];
    this.pool.clear();
    this.vfx.clear();
    this.equipment?.clear();
    this.world.reset();

    const map = getMap(this.mapId).build();
    this.map = map;
    this.scene.setEnvironment(map.environment);
    this.scene.clearMap();
    this.scene.addToMap(map.root);
    this.world.setMap(map);

    // Destructible cube cluster near a building for explosive demos.
    for (let i = 0; i < 9; i++) {
      const cube = new THREE.Mesh(
        new THREE.BoxGeometry(1, 1, 1),
        createToonMaterial({ color: 0xd98c5f }),
      );
      const col = i % 3;
      const row = Math.floor(i / 3);
      cube.position.set(-1 + col * 1.1, 0.5 + row * 1.05, -6);
      cube.castShadow = true;
      this.scene.addToMap(cube);
      this.world.addTarget(new DestructibleCube(cube, this.scene, this.vfx));
    }

    // Equipment manager + context.
    const ctx: EquipmentContext = {
      world: this.world,
      vfx: this.vfx,
      root: this.scene.dynamicRoot,
      screen: this.screen,
      getPlayerPosition: (out) => out.copy(this.feet).setY(this.feet.y + 1),
      getPlayerTeam: () => "blue",
      onSnapshot: (positions) => console.info(`[snapshot] revealed ${positions.length} enemies`),
    };
    this.equipment = new EquipmentManager(ctx);

    this.equipWeapon(this.weaponIndex);
    this.spawnCharacters(assets, map);

    // Start at a blue spawn.
    const spawn = map.spawns.find((s) => s.team === "blue") ?? map.spawns[0];
    this.feet.copy(spawn.position);
    this.feet.y = map.groundAt(this.feet.x, this.feet.z);
    this.syncCamera();
  }

  private syncCamera(): void {
    this.camera.perspective.position.set(this.feet.x, this.feet.y + EYE_HEIGHT, this.feet.z);
  }

  private equipWeapon(index: number): void {
    const def = WEAPONS[((index % WEAPONS.length) + WEAPONS.length) % WEAPONS.length];
    this.shooter.weaponId = def.id;
    this.weapon = new Weapon(def, [], this.shooter, {
      onShot: () => this.viewmodel.onShot(),
      onReloadStart: (_empty, dur) => this.viewmodel.startReload(dur),
    });
    this.viewmodel.setWeapon(def);
  }

  private async spawnCharacters(assets: AssetLoader, map: MapBuild): Promise<void> {
    const redSpawns = map.spawns.filter((s) => s.team === "red");
    for (let i = 0; i < 2; i++) {
      const c = await createCharacter(assets, { team: "red" });
      const sp = redSpawns[i] ?? { position: new THREE.Vector3(i * 4 - 2, 0, -20) };
      c.root.position.copy(sp.position);
      c.root.position.z = -20 + i * 5;
      c.root.position.x = -4 + i * 8;
      c.play("idle");
      this.scene.add(c.root);
      this.chars.push(c);
      this.world.addTarget(new CharacterTarget(c, "red"));
    }
  }

  // ---- Public debug hooks (called from the console for verification) ----
  throwTactical(id: TacticalId = this.currentTactical): void {
    this.updateAim();
    this.equipment.throwTactical(id, {
      origin: this.origin.clone(),
      direction: this.dir.clone(),
      team: "blue",
    });
  }
  throwLethal(id: LethalId = this.currentLethal): void {
    this.updateAim();
    this.equipment.throwLethal(id, {
      origin: this.origin.clone(),
      direction: this.dir.clone(),
      team: "blue",
    });
  }
  detonateC4(): boolean {
    return this.equipment.detonateC4();
  }

  private updateAim(): void {
    this.camera.perspective.getWorldPosition(this.origin);
    this.camera.getLookDirection(this.dir);
  }

  update(dt: number): void {
    this.elapsed += dt;
    this.map?.update?.(dt, this.elapsed);
    for (const c of this.chars) c.update(dt);
    this.vfx.update(dt);
    this.screen.update(dt);
    this.pool.update(dt, this.world, this.vfx);
    this.equipment.update(dt);

    // Weapon cycling via wheel.
    const wheel = this.input.consumeWheel();
    if (wheel !== 0) {
      this.weaponIndex += wheel;
      this.equipWeapon(this.weaponIndex);
    }

    this.updateAim();

    const ads = this.input.isDown("ads") && this.camera.isLocked;
    this.viewmodel.setADS(ads, this.weapon.stats.adsTime);
    this.weapon.adsFactor = this.viewmodel.adsFactor;
    this.weapon.setTrigger(this.input.isDown("fire") && this.camera.isLocked);
    if (this.input.wasPressed("reload")) this.weapon.reload();
    this.weapon.update(dt, this.aim, this.world, this.vfx);
    this.viewmodel.update(dt);

    // Throwables.
    if (this.input.wasPressed("tactical")) this.throwTactical();
    if (this.input.wasPressed("lethal")) {
      const now = this.elapsed;
      if (this.currentLethal === "c4" && now - this.lastG < 0.35) {
        this.detonateC4();
      } else {
        this.throwLethal();
      }
      this.lastG = now;
    }

    this.movePlayer(dt);
  }

  private movePlayer(dt: number): void {
    if (!this.camera.isLocked || !this.map) return;
    const speed = this.input.isDown("sprint") ? 7.5 : 5;
    const fb = this.input.axis("back", "forward");
    const lr = this.input.axis("left", "right");
    if (fb !== 0 || lr !== 0) {
      const fwd = this.tmp.set(0, 0, 0);
      this.camera.getForward(fwd);
      const fx = fwd.x, fz = fwd.z;
      // right = forward x up
      const rx = fz, rz = -fx;
      this.feet.x += (fx * fb + rx * lr) * speed * dt;
      this.feet.z += (fz * fb + rz * lr) * speed * dt;
    }
    this.feet.y = this.map.groundAt(this.feet.x, this.feet.z);
    this.map.collision.resolve(this.feet, PLAYER_RADIUS, PLAYER_HEIGHT);
    this.syncCamera();
  }

  dispose(): void {
    for (const c of this.chars) {
      this.scene.dynamicRoot.remove(c.root);
      c.dispose();
    }
    this.chars = [];
    this.pool.clear();
    this.vfx.clear();
    this.equipment?.clear();
    this.screen.clear();
    this.viewmodel.dispose();
  }
}

// ---- Sandbox world (WorldQuery implementation) ----

class SandboxWorld implements WorldQuery {
  private raycaster = new THREE.Raycaster();
  private targets: DamageTarget[] = [];
  private targetByObject = new Map<THREE.Object3D, DamageTarget>();
  private rocketSpawner?: (o: THREE.Vector3, d: THREE.Vector3, owner: ShooterTag) => void;
  private map: MapBuild | null = null;

  constructor(private scene: Scene, private _vfx: VFX) {}

  setMap(map: MapBuild): void {
    this.map = map;
  }

  reset(): void {
    this.targets = [];
    this.targetByObject.clear();
  }

  setRocketSpawner(fn: (o: THREE.Vector3, d: THREE.Vector3, owner: ShooterTag) => void): void {
    this.rocketSpawner = fn;
  }

  addTarget(t: DamageTarget): void {
    this.targets.push(t);
    this.targetByObject.set(t.object3d, t);
  }

  raycast(origin: THREE.Vector3, direction: THREE.Vector3, maxDistance: number): RaycastHit | null {
    this.raycaster.set(origin, direction);
    this.raycaster.far = maxDistance;
    const hits = this.raycaster.intersectObject(this.scene.mapRoot, true);
    // Also test damage-target meshes (characters live in dynamicRoot).
    for (const t of this.targets) {
      if (!t.alive) continue;
      const more = this.raycaster.intersectObject(t.object3d, true);
      for (const h of more) hits.push(h);
    }
    hits.sort((a, b) => a.distance - b.distance);
    for (const h of hits) {
      if (h.object.name === "__outline") continue;
      if (!h.face) continue;
      let target: DamageTarget | undefined;
      let node: THREE.Object3D | null = h.object;
      while (node) {
        const t = this.targetByObject.get(node);
        if (t) {
          target = t;
          break;
        }
        node = node.parent;
      }
      if (target && !target.alive) continue;
      const normal = h.face.normal.clone().transformDirection(h.object.matrixWorld);
      return { point: h.point.clone(), normal, distance: h.distance, object: h.object, target };
    }
    return null;
  }

  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[] {
    const out: DamageTarget[] = [];
    const p = new THREE.Vector3();
    for (const t of this.targets) {
      if (!t.alive) continue;
      if (t.position(p).distanceTo(center) <= radius) out.push(t);
    }
    return out;
  }

  spawnRocket(origin: THREE.Vector3, direction: THREE.Vector3, owner: ShooterTag): void {
    this.rocketSpawner?.(origin, direction, owner);
  }
}

class DestructibleCube implements DamageTarget {
  readonly object3d: THREE.Mesh;
  readonly team: TeamId = "red";
  alive = true;
  private health = 45;

  constructor(mesh: THREE.Mesh, private scene: Scene, private vfx: VFX) {
    this.object3d = mesh;
  }
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.object3d.position);
  }
  isHead(): boolean {
    return false;
  }
  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    this.health -= info.amount;
    if (this.health <= 0) {
      this.alive = false;
      this.vfx.explosion(this.object3d.position.clone(), 1.5);
      this.scene.mapRoot.remove(this.object3d);
    }
  }
}

class CharacterTarget implements DamageTarget {
  readonly object3d: THREE.Object3D;
  alive = true;
  private health = 100;

  constructor(private character: Character, readonly team: TeamId) {
    this.object3d = character.root;
  }
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.character.root.position).setY(this.character.root.position.y + 1);
  }
  isHead(obj: THREE.Object3D): boolean {
    return obj.getWorldPosition(new THREE.Vector3()).y > this.character.root.position.y + 1.55;
  }
  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    this.health -= info.amount;
    if (this.health <= 0) {
      this.alive = false;
      this.character.play("die");
    }
  }
}
