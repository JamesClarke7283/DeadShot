// Phase 1-3 combat sandbox: a walkable test arena with a wall (for bullet
// holes), destructible cubes (for the RPG), two demo characters, and a fully
// wired player weapon (hitscan + recoil + viewmodel + reload + ADS + rocket).
// Cycle weapons with the mouse wheel. Replaced by the real Match in Phase 7.

import * as THREE from "../three.ts";
import type { Scene } from "./Scene.ts";
import type { Camera } from "./Camera.ts";
import type { Input } from "./Input.ts";
import type { AssetLoader } from "./AssetLoader.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { outlineHierarchy } from "../render/OutlinePass.ts";
import { VFX } from "../render/VFX.ts";
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

export class Sandbox {
  private vfx: VFX;
  private world: SandboxWorld;
  private pool: ProjectilePool;
  private viewmodel: WeaponViewmodel;
  private weapon!: Weapon;
  private weaponIndex = 0;
  private chars: Character[] = [];
  private aim: Aim;

  private readonly shooter: ShooterTag = { team: "blue", isPlayer: true, weaponId: "m4" };
  private readonly origin = new THREE.Vector3();
  private readonly dir = new THREE.Vector3();

  constructor(
    private scene: Scene,
    private camera: Camera,
    private input: Input,
  ) {
    this.vfx = new VFX(scene.three);
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

  build(assets: AssetLoader): void {
    this.scene.setEnvironment({
      background: 0x9fd3ff,
      fogColor: 0xbfe3ff,
      fogNear: 80,
      fogFar: 500,
    });
    this.scene.clearMap();

    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(200, 200),
      createToonMaterial({ color: 0x6fae5a }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    this.scene.addToMap(ground);

    // Bullet-hole test wall
    const wall = new THREE.Mesh(
      new THREE.BoxGeometry(16, 6, 0.6),
      createToonMaterial({ color: 0xb9a07a }),
    );
    wall.position.set(0, 3, -14);
    wall.castShadow = true;
    wall.receiveShadow = true;
    this.scene.addToMap(wall);
    outlineHierarchy(wall, { thickness: 0.05 });

    // Destructible cubes for the RPG
    for (let i = 0; i < 9; i++) {
      const cube = new THREE.Mesh(
        new THREE.BoxGeometry(1, 1, 1),
        createToonMaterial({ color: 0xd98c5f }),
      );
      const col = i % 3;
      const row = Math.floor(i / 3);
      cube.position.set(-2 + col * 2, 0.5 + row * 1.05, -8);
      cube.castShadow = true;
      this.scene.addToMap(cube);
      this.world.addDestructible(new DestructibleCube(cube, this.scene, this.vfx));
    }

    this.equipWeapon(this.weaponIndex);
    this.spawnCharacters(assets);
    this.camera.setPosition(0, 1.6, 8);
  }

  private equipWeapon(index: number): void {
    const def = WEAPONS[((index % WEAPONS.length) + WEAPONS.length) % WEAPONS.length];
    this.shooter.weaponId = def.id;
    this.weapon = new Weapon(def, [], this.shooter, {
      onShot: () => this.viewmodel.onShot(),
      onReloadStart: (_empty, dur) => this.viewmodel.startReload(dur),
    });
    this.viewmodel.setWeapon(def);
    console.info(`[sandbox] equipped ${def.name} (${this.weapon.ammoString()})`);
  }

  private async spawnCharacters(assets: AssetLoader): Promise<void> {
    const blue = await createCharacter(assets, { team: "blue" });
    blue.root.position.set(-6, 0, -4);
    blue.play("idle");
    this.scene.add(blue.root);
    this.chars.push(blue);

    const red = await createCharacter(assets, { team: "red" });
    red.root.position.set(6, 0, -4);
    red.play("run");
    this.scene.add(red.root);
    this.chars.push(red);
  }

  update(dt: number): void {
    for (const c of this.chars) c.update(dt);
    this.vfx.update(dt);
    this.pool.update(dt, this.world, this.vfx);

    // Weapon cycling via wheel.
    const wheel = this.input.consumeWheel();
    if (wheel !== 0) {
      this.weaponIndex += wheel;
      this.equipWeapon(this.weaponIndex);
    }

    // Aim from the camera.
    this.camera.perspective.getWorldPosition(this.origin);
    this.camera.getLookDirection(this.dir);

    const ads = this.input.isDown("ads") && this.camera.isLocked;
    this.viewmodel.setADS(ads, this.weapon.stats.adsTime);
    this.weapon.adsFactor = this.viewmodel.adsFactor;
    this.weapon.setTrigger(this.input.isDown("fire") && this.camera.isLocked);
    if (this.input.wasPressed("reload")) this.weapon.reload();

    this.weapon.update(dt, this.aim, this.world, this.vfx);
    this.viewmodel.update(dt);

    // Movement
    if (this.camera.isLocked) {
      const speed = (this.input.isDown("sprint") ? 9 : 5.5) * dt;
      const fb = this.input.axis("back", "forward");
      const lr = this.input.axis("left", "right");
      if (fb !== 0 || lr !== 0) {
        const fwd = new THREE.Vector3();
        const right = new THREE.Vector3();
        this.camera.getForward(fwd);
        this.camera.getRight(right);
        const move = new THREE.Vector3()
          .addScaledVector(fwd, fb)
          .addScaledVector(right, lr)
          .normalize()
          .multiplyScalar(speed);
        this.camera.perspective.position.add(move);
        this.camera.perspective.position.y = 1.6;
      }
    }
  }

  dispose(): void {
    for (const c of this.chars) {
      this.scene.dynamicRoot.remove(c.root);
      c.dispose();
    }
    this.chars = [];
    this.pool.clear();
    this.vfx.clear();
    this.viewmodel.dispose();
  }
}

// ---- Sandbox world (WorldQuery implementation) ----

class SandboxWorld implements WorldQuery {
  private raycaster = new THREE.Raycaster();
  private destructibles: DestructibleCube[] = [];
  private targetByObject = new Map<THREE.Object3D, DamageTarget>();
  private rocketSpawner?: (o: THREE.Vector3, d: THREE.Vector3, owner: ShooterTag) => void;

  constructor(private scene: Scene, private _vfx: VFX) {}

  setRocketSpawner(fn: (o: THREE.Vector3, d: THREE.Vector3, owner: ShooterTag) => void): void {
    this.rocketSpawner = fn;
  }

  addDestructible(cube: DestructibleCube): void {
    this.destructibles.push(cube);
    this.targetByObject.set(cube.object3d, cube);
  }

  raycast(
    origin: THREE.Vector3,
    direction: THREE.Vector3,
    maxDistance: number,
  ): RaycastHit | null {
    this.raycaster.set(origin, direction);
    this.raycaster.far = maxDistance;
    const hits = this.raycaster.intersectObject(this.scene.mapRoot, true);
    for (const h of hits) {
      if (h.object.name === "__outline") continue;
      if (!h.face) continue;
      // Map to a damage target by walking ancestors.
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
      return {
        point: h.point.clone(),
        normal,
        distance: h.distance,
        object: h.object,
        target,
      };
    }
    return null;
  }

  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[] {
    const out: DamageTarget[] = [];
    const p = new THREE.Vector3();
    for (const d of this.destructibles) {
      if (!d.alive) continue;
      if (d.position(p).distanceTo(center) <= radius) out.push(d);
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
  // Fragile test props so the RPG splash visibly clears a cluster.
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
    const mat = this.object3d.material as THREE.MeshToonMaterial;
    mat.emissive.setHex(0x552200);
    setTimeout(() => mat.emissive.setHex(0x000000), 60);
    if (this.health <= 0) {
      this.alive = false;
      this.vfx.explosion(this.object3d.position.clone(), 1.5);
      this.scene.mapRoot.remove(this.object3d);
    }
  }
}
