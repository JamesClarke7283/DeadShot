// Lightweight visual-effects system: bullet impacts + persistent holes, tracers,
// muzzle flashes and explosions. Implements the VFXSink combat interface.
//
// Transient effects age out in update(dt); bullet-hole decals persist up to a
// cap (oldest recycled). All effects are unlit (MeshBasicMaterial) so they read
// as punchy cartoon pops regardless of scene lighting.

import * as THREE from "../three.ts";
import type { VFXSink } from "../weapons/combat.ts";

interface Transient {
  obj: THREE.Object3D;
  age: number;
  life: number;
  tick: (t: number, obj: THREE.Object3D) => void;
}

const MAX_DECALS = 96;

export class VFX implements VFXSink {
  private root = new THREE.Group();
  private transients: Transient[] = [];
  private decals: THREE.Mesh[] = [];

  private sparkGeo = new THREE.SphereGeometry(0.06, 6, 6);
  private holeGeo = new THREE.CircleGeometry(0.08, 10);
  private flashGeo = new THREE.PlaneGeometry(0.6, 0.6);
  private explosionGeo = new THREE.SphereGeometry(1, 16, 16);
  private tracerGeo = new THREE.CylinderGeometry(0.02, 0.02, 1, 5, 1, true);

  constructor(scene: THREE.Scene) {
    this.root.name = "vfx";
    scene.add(this.root);
  }

  private addTransient(t: Transient): void {
    this.root.add(t.obj);
    this.transients.push(t);
  }

  bulletImpact(point: THREE.Vector3, normal: THREE.Vector3, onActor: boolean): void {
    // Spark
    const spark = new THREE.Mesh(
      this.sparkGeo,
      new THREE.MeshBasicMaterial({
        color: onActor ? 0xff4d4d : 0xffd166,
        transparent: true,
      }),
    );
    spark.position.copy(point);
    this.addTransient({
      obj: spark,
      age: 0,
      life: 0.12,
      tick: (t, o) => {
        const m = o as THREE.Mesh;
        const k = 1 - t;
        o.scale.setScalar(0.5 + t * 1.5);
        (m.material as THREE.MeshBasicMaterial).opacity = k;
      },
    });

    // Persistent hole on solid surfaces only.
    if (!onActor) this.bulletHole(point, normal);
  }

  bulletHole(point: THREE.Vector3, normal: THREE.Vector3): void {
    const hole = new THREE.Mesh(
      this.holeGeo,
      new THREE.MeshBasicMaterial({
        color: 0x14110d,
        transparent: true,
        opacity: 0.9,
        depthWrite: false,
        polygonOffset: true,
        polygonOffsetFactor: -4,
      }),
    );
    hole.position.copy(point).addScaledVector(normal, 0.01);
    hole.lookAt(point.clone().add(normal));
    this.root.add(hole);
    this.decals.push(hole);
    if (this.decals.length > MAX_DECALS) {
      const old = this.decals.shift();
      if (old) {
        this.root.remove(old);
        (old.material as THREE.Material).dispose();
      }
    }
  }

  tracer(from: THREE.Vector3, to: THREE.Vector3): void {
    const dir = to.clone().sub(from);
    const len = dir.length();
    if (len < 0.01) return;
    const tracer = new THREE.Mesh(
      this.tracerGeo,
      new THREE.MeshBasicMaterial({ color: 0xfff1a8, transparent: true, opacity: 0.85 }),
    );
    tracer.scale.set(1, len, 1);
    tracer.position.copy(from).addScaledVector(dir, 0.5);
    tracer.quaternion.setFromUnitVectors(
      new THREE.Vector3(0, 1, 0),
      dir.clone().normalize(),
    );
    this.addTransient({
      obj: tracer,
      age: 0,
      life: 0.06,
      tick: (t, o) => {
        ((o as THREE.Mesh).material as THREE.MeshBasicMaterial).opacity = 0.85 * (1 - t);
      },
    });
  }

  muzzleFlash(position: THREE.Vector3, direction: THREE.Vector3): void {
    const flash = new THREE.Mesh(
      this.flashGeo,
      new THREE.MeshBasicMaterial({
        color: 0xffe08a,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    flash.position.copy(position).addScaledVector(direction, 0.2);
    flash.lookAt(position.clone().addScaledVector(direction, -1));
    flash.rotation.z = Math.random() * Math.PI;
    this.addTransient({
      obj: flash,
      age: 0,
      life: 0.05,
      tick: (t, o) => {
        o.scale.setScalar(0.6 + t * 0.8);
        ((o as THREE.Mesh).material as THREE.MeshBasicMaterial).opacity = 1 - t;
      },
    });
  }

  explosion(center: THREE.Vector3, radius: number): void {
    const ball = new THREE.Mesh(
      this.explosionGeo,
      new THREE.MeshBasicMaterial({ color: 0xff8a3c, transparent: true, depthWrite: false }),
    );
    ball.position.copy(center);
    this.addTransient({
      obj: ball,
      age: 0,
      life: 0.45,
      tick: (t, o) => {
        o.scale.setScalar(radius * (0.3 + t * 0.9));
        ((o as THREE.Mesh).material as THREE.MeshBasicMaterial).opacity = 1 - t;
      },
    });

    const light = new THREE.PointLight(0xffa040, 8, radius * 4, 2);
    light.position.copy(center);
    this.addTransient({
      obj: light,
      age: 0,
      life: 0.35,
      tick: (t, o) => {
        (o as THREE.PointLight).intensity = 8 * (1 - t);
      },
    });
  }

  update(dt: number): void {
    for (let i = this.transients.length - 1; i >= 0; i--) {
      const tr = this.transients[i];
      tr.age += dt;
      const t = Math.min(1, tr.age / tr.life);
      tr.tick(t, tr.obj);
      if (tr.age >= tr.life) {
        this.root.remove(tr.obj);
        const m = tr.obj as THREE.Mesh;
        if (m.isMesh) (m.material as THREE.Material).dispose();
        this.transients.splice(i, 1);
      }
    }
  }

  clear(): void {
    for (const d of this.decals) {
      this.root.remove(d);
      (d.material as THREE.Material).dispose();
    }
    this.decals = [];
    for (const t of this.transients) this.root.remove(t.obj);
    this.transients = [];
  }
}
