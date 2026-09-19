/** Extract original Three.js models losslessly for the background Blender build.
 * Run from the Godot project: deno run -A --config ../DeadShot/deno.json tools/export_models.ts
 * No changes to the original project, and no hand-recreated approximations.
 */
import * as THREE from "../../DeadShot/src/three.ts";
import { ProceduralHuman } from "../../DeadShot/src/characters/ProceduralHuman.ts";
import { WeaponViewmodel } from "../../DeadShot/src/weapons/WeaponViewmodel.ts";
import { WEAPONS } from "../../DeadShot/src/weapons/WeaponDefinition.ts";
import { ATTACHMENTS } from "../../DeadShot/src/weapons/AttachmentDefinitions.ts";
import { buildAttachmentMeshes } from "../../DeadShot/src/weapons/AttachmentVisuals.ts";
import type { TeamId } from "../../DeadShot/src/core/types.ts";
import type { Streak, StreakContext } from "../../DeadShot/src/streaks/Streak.ts";
import { AttackHelicopter } from "../../DeadShot/src/streaks/AttackHelicopter.ts";
import { ChopperGunner } from "../../DeadShot/src/streaks/ChopperGunner.ts";
import { Gunship } from "../../DeadShot/src/streaks/Gunship.ts";
import { SentryGun } from "../../DeadShot/src/streaks/SentryGun.ts";
import { RCXD } from "../../DeadShot/src/streaks/RCXD.ts";
import { PredatorMissile } from "../../DeadShot/src/streaks/PredatorMissile.ts";
import { StrafeRun } from "../../DeadShot/src/streaks/StrafeRun.ts";
import { CarePackage } from "../../DeadShot/src/streaks/CarePackage.ts";
import { UAV } from "../../DeadShot/src/streaks/UAV.ts";
import { Nuke } from "../../DeadShot/src/streaks/Nuke.ts";
import { Rocket } from "../../DeadShot/src/weapons/Rocket.ts";
import { createToonMaterial } from "../../DeadShot/src/render/ToonMaterial.ts";
import { addOutline } from "../../DeadShot/src/render/OutlinePass.ts";

type GeometryRecord = { positions: number[]; normals: number[]; uvs: number[]; indices: number[] };
type MaterialRecord = {
  name: string;
  color: number[];
  emissive: number[];
  opacity: number;
  transparent: boolean;
  doubleSide: boolean;
  unlit: boolean;
  outline: boolean;
  thickness: number;
  depthTest: boolean;
  role: string;
};
type NodeRecord = {
  name: string;
  parent: number;
  matrix: number[];
  visible: boolean;
  castShadow: boolean;
  geometry?: string;
  material?: string;
};
const geometries: Record<string, GeometryRecord> = {};
const materials: Record<string, MaterialRecord> = {};
const geometryIds = new Map<THREE.BufferGeometry, string>();
const materialIds = new Map<string, string>();
const models: Record<string, { nodes: NodeRecord[]; file: string }> = {};

function geometryId(g: THREE.BufferGeometry): string {
  const cached = geometryIds.get(g);
  if (cached) return cached;
  const id = `geometry_${Object.keys(geometries).length}`;
  geometries[id] = {
    positions: Array.from(g.getAttribute("position").array),
    normals: Array.from(g.getAttribute("normal")?.array ?? []),
    uvs: Array.from(g.getAttribute("uv")?.array ?? []),
    indices: g.index
      ? Array.from(g.index.array)
      : Array.from({ length: g.getAttribute("position").count }, (_, i) => i),
  };
  geometryIds.set(g, id);
  return id;
}

function materialId(m: THREE.Material): string {
  const mat = m as THREE.MeshToonMaterial & THREE.ShaderMaterial;
  const outline = Boolean(mat.uniforms?.uThickness);
  const color = outline
    ? mat.uniforms.uColor.value as THREE.Color
    : mat.color ?? new THREE.Color(0xffffff);
  const record = {
    color: color.toArray(),
    emissive: mat.emissive?.toArray() ?? [0, 0, 0],
    opacity: mat.opacity,
    transparent: mat.transparent,
    doubleSide: mat.side === THREE.DoubleSide,
    unlit: mat.type === "MeshBasicMaterial" || outline,
    outline,
    thickness: outline ? mat.uniforms.uThickness.value as number : 0,
    depthTest: mat.depthTest,
    role: mat.name === "camo" || mat.name === "team" ? mat.name : "",
  };
  const key = JSON.stringify(record);
  const cached = materialIds.get(key);
  if (cached) return cached;
  const id = `ds_material_${Object.keys(materials).length}`;
  materials[id] = { name: id, ...record };
  materialIds.set(key, id);
  return id;
}

function saveModel(id: string, root: THREE.Object3D): void {
  const nodes: NodeRecord[] = [];
  root.position.set(0, 0, 0);
  root.rotation.set(0, 0, 0);
  root.scale.set(1, 1, 1);
  root.visible = true;
  root.name = id;
  function visit(object: THREE.Object3D, parent: number): void {
    object.updateMatrix();
    const node: NodeRecord = {
      name: object.name === "__outline"
        ? `outline_${nodes.length}`
        : object.name || `part_${nodes.length}`,
      parent,
      matrix: object.matrix.toArray(),
      visible: object.visible,
      castShadow: object.castShadow,
    };
    const mesh = object as THREE.Mesh;
    if (mesh.isMesh) {
      if (Array.isArray(mesh.material)) throw new Error(`Multi-material node: ${id}/${node.name}`);
      node.geometry = geometryId(mesh.geometry);
      node.material = materialId(mesh.material);
    }
    const index = nodes.length;
    nodes.push(node);
    object.children.forEach((child) => visit(child, index));
  }
  visit(root, -1);
  models[id] = { nodes, file: `res://assets/models/${id}.glb` };
}

for (const team of ["blue", "red", "ffa"] as TeamId[]) {
  const human = new ProceduralHuman({ team });
  const parts = human as unknown as Record<string, THREE.Object3D>;
  for (
    const [key, name] of Object.entries({
      hips: "hips",
      head: "head",
      leftArm: "left_arm",
      rightArm: "right_arm",
      leftLeg: "left_leg",
      rightLeg: "right_leg",
    })
  ) parts[key].name = name;
  (human as unknown as { headbandMat: THREE.Material }).headbandMat.name = "team";
  saveModel(`human_${team}`, human.root);
}

const categories = [...new Set(WEAPONS.filter((w) => w.id !== "knife").map((w) => w.category))];
for (const category of categories) {
  const vm = new WeaponViewmodel(new THREE.PerspectiveCamera());
  vm.setWeapon(WEAPONS.find((w) => w.category === category)!);
  const parts = vm as unknown as {
    gun: THREE.Group;
    muzzle: THREE.Object3D;
    camoMat: THREE.Material;
    knifeMesh: THREE.Group;
  };
  parts.camoMat.name = "camo";
  parts.gun.name = "gun";
  parts.muzzle.name = "muzzle";
  parts.knifeMesh.name = "knife";
  saveModel(`weapon_${category}`, vm.root);
  for (const attachment of ATTACHMENTS) {
    const root = buildAttachmentMeshes(category, [attachment]);
    if (root.children.length > 0) saveModel(`attachment_${category}_${attachment.id}`, root);
  }
}
const knife = new WeaponViewmodel(new THREE.PerspectiveCamera());
knife.setWeapon(WEAPONS.find((w) => w.id === "knife")!);
const knifeParts = knife as unknown as {
  gun: THREE.Group;
  muzzle: THREE.Object3D;
  knifeMesh: THREE.Group;
};
knifeParts.gun.name = "gun";
knifeParts.muzzle.name = "muzzle";
knifeParts.knifeMesh.name = "knife";
saveModel("weapon_knife", knife.root);

const root = new THREE.Group();
const context: StreakContext = {
  root,
  owner: { id: 1, team: "blue" },
  localPlayerId: 1,
  bounds: { minX: -40, maxX: 40, minZ: -40, maxZ: 40 },
  allActors: () => [],
  enemiesOf: () => [],
  groundAt: () => 0,
  world: { raycast: () => null, radiusTargets: () => [] },
  vfx: { tracer: () => {}, muzzleFlash: () => {}, explosion: () => {}, bulletImpact: () => {} },
  ping: () => {},
  setCounterUAV: () => {},
  spawnCarePackage: () => {},
  armCarePackage: () => {},
  grantRandomStreak: () => "uav",
  endMatch: () => {},
};
const streaks: Streak[] = [
  new AttackHelicopter(),
  new ChopperGunner(),
  new Gunship(),
  new SentryGun(),
  new RCXD(),
  new PredatorMissile(),
  new StrafeRun(),
  new CarePackage(),
  new UAV(),
  new Nuke(),
];
for (const streak of streaks) {
  root.clear();
  streak.update(0, context);
  const parts = streak as unknown as {
    rotor?: THREE.Object3D;
    gun?: THREE.Object3D;
    releaseCrate?: (ctx: StreakContext, x: number) => void;
  };
  if (parts.rotor) parts.rotor.name = "rotor";
  if (parts.gun) parts.gun.name = "gun";
  if (root.children.length) saveModel(`streak_${streak.id}`, root.children[0]);
  if (streak.id === "strafe_run") saveModel("strafe_jet", root.children[0].children[0]);
  if (parts.releaseCrate) {
    parts.releaseCrate(context, 0);
    saveModel("care_crate", root.children[root.children.length - 1]);
  }
}

// The landed care-package pickup is constructed directly inside Match.ts;
// preserve that separate geometry and palette, not the falling crate model.
const pickup = new THREE.Group();
const crate = new THREE.Mesh(
  new THREE.BoxGeometry(1.2, 1.2, 1.2),
  createToonMaterial({ color: 0xcf9233, emissive: 0x3a2400 }),
);
addOutline(crate, { thickness: 0.045 });
const beam = new THREE.Mesh(
  new THREE.CylinderGeometry(0.18, 0.18, 9, 8, 1, true),
  new THREE.MeshBasicMaterial({ color: 0xcdeb6e, transparent: true, opacity: 0.22 }),
);
beam.position.y = 4.6;
pickup.add(crate, beam);
saveModel("care_pickup", pickup);
const rocket = new Rocket({ speed: 50, directDamage: 120, splashDamage: 100, splashRadius: 5 }, {
  id: 1,
  team: "blue",
  weaponId: "rpg7",
});
saveModel("rocket", (rocket as unknown as { mesh: THREE.Object3D }).mesh);
const weaponDrop = new THREE.Group();
const dropBody = new THREE.Mesh(
  new THREE.BoxGeometry(0.72, 0.13, 0.13),
  createToonMaterial({ color: 0x2b2f36 }),
);
addOutline(dropBody, { thickness: 0.02 });
const dropMagazine = new THREE.Mesh(
  new THREE.BoxGeometry(0.12, 0.22, 0.1),
  createToonMaterial({ color: 0x14171c }),
);
dropMagazine.position.set(-0.04, -0.16, 0);
weaponDrop.add(dropBody, dropMagazine);
saveModel("weapon_drop", weaponDrop);
const ammoPickup = new THREE.Mesh(
  new THREE.BoxGeometry(0.5, 0.35, 0.5),
  createToonMaterial({ color: 0xffcc33, emissive: 0x3a2c00 }),
);
addOutline(ammoPickup, { thickness: 0.03 });
saveModel("ammo_pickup", ammoPickup);

for (
  const name of [
    "Frag",
    "Semtex",
    "Molotov",
    "Thermite",
    "ThrowingKnife",
    "Claymore",
    "C4",
    "Flashbang",
    "Stun",
    "Smoke",
    "Snapshot",
  ]
) {
  const module = await import(`../../DeadShot/src/tacticals/${name}.ts`);
  const equipment = new module[name]() as { buildMesh: (team: TeamId) => THREE.Object3D };
  const mesh = equipment.buildMesh("blue");
  mesh.traverse((object) => {
    const material = (object as THREE.Mesh).material as THREE.MeshToonMaterial;
    if (material?.color?.getHex() === 0x3a86ff) material.name = "team";
  });
  saveModel(
    `equipment_${name.replace(/[A-Z]/g, (s, i) => `${i ? "_" : ""}${s.toLowerCase()}`)}`,
    mesh,
  );
}

const output = new URL("../assets/models/source/models.json", import.meta.url);
await Deno.mkdir(new URL(".", output), { recursive: true });
await Deno.writeTextFile(
  output,
  JSON.stringify({
    schema: 1,
    source: "DeadShot Three.js r180",
    geometries,
    materials,
    models,
    weaponModels: Object.fromEntries(
      WEAPONS.map((w) => [w.id, `weapon_${w.id === "knife" ? "knife" : w.category}`]),
    ),
    attachmentSlots: Object.fromEntries(ATTACHMENTS.map((a) => [a.id, a.slot])),
  }),
);
console.log(
  `Exported ${Object.keys(models).length} models, ${Object.keys(geometries).length} geometries, ${
    Object.keys(materials).length
  } materials.`,
);
