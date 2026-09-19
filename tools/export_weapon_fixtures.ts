import * as THREE from "../../DeadShot/src/three.ts";
import { ProceduralHuman } from "../../DeadShot/src/characters/ProceduralHuman.ts";
import { Weapon } from "../../DeadShot/src/weapons/Weapon.ts";
import {
  getWeapon,
  WEAPON_IDS,
} from "../../DeadShot/src/weapons/WeaponDefinition.ts";
import { WeaponViewmodel } from "../../DeadShot/src/weapons/WeaponViewmodel.ts";

// Deterministic source observations: assertions in Godot consume these instead
// of reimplementing the source state machine as their expected value.
Math.random = () => 0.5;
const weapons = WEAPON_IDS.map((id) => {
  let shots = 0;
  let reloads = 0;
  let recoil = 0;
  let pellets = 0;
  let rockets = 0;
  const weapon = new Weapon(getWeapon(id), [], {
    id: 0,
    team: "blue",
    isPlayer: true,
    weaponId: id,
  }, {
    onShot: () => shots++,
    onReloadStart: () => reloads++,
  });
  weapon.magazine = Math.min(2, weapon.magazine);
  weapon.reserve = Math.min(7, weapon.reserve);
  const aim = {
    origin: new THREE.Vector3(1, 1.7, 2),
    direction: new THREE.Vector3(0, 0, -1),
    applyRecoil: (pitch: number) => recoil += pitch,
  };
  const world = {
    raycast: () => {
      pellets++;
      return null;
    },
    radiusTargets: () => [],
    spawnRocket: () => {
      rockets++;
    },
  };
  const fx = {
    bulletImpact() {},
    tracer() {},
    muzzleFlash() {},
    explosion() {},
  };
  const frames = [];
  for (let i = 0; i < 90; i++) {
    const dt = i === 60 ? 4 : 0.1;
    const held = i % 4 < 2;
    weapon.setTrigger(held);
    if (i === 40) weapon.reload();
    if (i === 70) weapon.swapIn();
    weapon.update(dt, aim, world, fx);
    frames.push({
      dt,
      held,
      reload: i === 40,
      swap: i === 70,
      magazine: weapon.magazine,
      reserve: weapon.reserve,
      state: weapon.state,
      shots,
      reloads,
      recoil,
      pellets,
      rockets,
    });
  }
  return { id, frames };
});

const camera = new THREE.PerspectiveCamera();
const viewmodel = new WeaponViewmodel(camera);
viewmodel.setWeapon(getWeapon("m4"));
const internals = viewmodel as unknown as {
  gun: THREE.Group;
  knifeMesh: THREE.Group;
};
const operations = [
  { ads: true, shot: true, dt: 0.025 },
  { reload: 2.1, dt: 0.2 },
  { melee: true, dt: 0 },
  { dt: 0.05 },
  { weapon: "m9", dt: 0.1 },
  { dt: 0.15 },
  { ads: false, dt: 0.5 },
  { shot: true, dt: 0.01 },
  { weapon: "knife", dt: 0.1 },
  { ads: true, dt: 0.3 },
  { dt: 1.5 },
];
let ads = false;
let weaponId = "m4";
const visualFrames = operations.map((operation) => {
  if (operation.weapon) {
    weaponId = operation.weapon;
    viewmodel.setWeapon(getWeapon(weaponId));
  }
  if (operation.ads !== undefined) ads = operation.ads;
  viewmodel.setADS(ads, getWeapon(weaponId).adsTime);
  if (operation.shot) viewmodel.onShot();
  if (operation.reload) viewmodel.startReload(operation.reload);
  if (operation.melee) viewmodel.meleeSlash();
  viewmodel.update(operation.dt);
  return {
    operation,
    ads: viewmodel.adsFactor,
    root: viewmodel.root.position.toArray(),
    gun: internals.gun.position.toArray(),
    gunRotation: internals.gun.rotation.toArray().slice(0, 3),
    gunVisible: internals.gun.visible,
    knife: internals.knifeMesh.position.toArray(),
    knifeRotation: internals.knifeMesh.rotation.toArray().slice(0, 3),
    knifeVisible: internals.knifeMesh.visible,
  };
});
viewmodel.dispose();
const human = new ProceduralHuman();
human.root.rotation.y = 0.9;
human.play("die");
human.update(0.125);
human.root.updateMatrix();
const deathMatrix = human.root.matrix.toArray();
human.dispose();
await Deno.mkdir("tests/fixtures", { recursive: true });
await Deno.writeTextFile(
  "tests/fixtures/weapon_source.json",
  JSON.stringify({ weapons, visualFrames, deathMatrix }),
);
console.log(
  `Captured ${weapons.length} source weapon timelines and ${visualFrames.length} viewmodel transitions.`,
);
