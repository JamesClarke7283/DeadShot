import * as THREE from "../three.ts";
import { Scene } from "../core/Scene.ts";
import { Camera } from "../core/Camera.ts";
import { Input } from "../core/Input.ts";
import { Match } from "./Match.ts";
import { GUNGAME, GunGameTracker } from "./GunGame.ts";
import { getWeapon } from "../weapons/WeaponDefinition.ts";
import { MatchWorld } from "./MatchWorld.ts";

class MockCamera {
  perspective = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
  getLookDirection(out: THREE.Vector3): THREE.Vector3 {
    return out.set(0, 0, -1);
  }
  getForward(out: THREE.Vector3): THREE.Vector3 {
    return out.set(0, 0, -1);
  }
  applyRecoil(_p: number, _y: number): void {}
}
class MockInput {
  isDown(_a: string): boolean {
    return false;
  }
  wasPressed(_a: string): boolean {
    return false;
  }
  wasReleased(_a: string): boolean {
    return false;
  }
  axis(_n: string, _p: string): number {
    return 0;
  }
  consumeWheel(): number {
    return 0;
  }
  isKeyDown(_c: string): boolean {
    return false;
  }
  wasKeyPressed(_c: string): boolean {
    return false;
  }
  wasKeyReleased(_c: string): boolean {
    return false;
  }
  consumeMouseDelta(): { dx: number; dy: number } {
    return { dx: 0, dy: 0 };
  }
  setVirtual(_c: string, _d: boolean): void {}
  endFrame(): void {}
  dispose(): void {}
}

Deno.test("debug knife", () => {
  const scene = new Scene();
  const camera = new MockCamera() as unknown as Camera;
  const input = new MockInput() as unknown as Input;
  const match = new Match(scene, camera, input, {
    mapId: "desert_town",
    mode: GUNGAME,
    botCount: 1,
    difficulty: "recruit",
    hasPlayer: true,
    playerName: "Tester",
    respawnDelay: 99,
    warmup: 0,
  });
  match.build();
  const player = match.player!;
  const bot = match.bots[0];
  const gg = (match as unknown as { gunGame: GunGameTracker }).gunGame;
  for (let i = 0; i < 7; i++) {
    const w = gg.weaponIdOf(player.id);
    gg.onKill(player.id, 999, w, false);
  }
  player.setWeaponClean(getWeapon("knife"));
  (match as unknown as { opts: { playerLethal?: string } }).opts.playerLethal = "knife";
  player.feet.set(0, 0, 0);
  bot.respawn(new THREE.Vector3(0, 0, -3), 0);
  bot.health = 100;
  bot.alive = true;

  const world = (match as unknown as { world: MatchWorld }).world;
  const origRaycast = world.raycast.bind(world);
  let calls = 0;
  world.raycast = (o: THREE.Vector3, d: THREE.Vector3, m: number, i?: THREE.Object3D | null) => {
    const r = origRaycast(o, d, m, i);
    calls++;
    if (calls <= 10) {
      console.log(
        `rc#${calls}: o=(${o.x.toFixed(2)},${o.y.toFixed(2)},${o.z.toFixed(2)}) max=${
          m.toFixed(3)
        } -> ${r ? "HIT d=" + (r as { distance: number }).distance.toFixed(2) : "miss"}`,
      );
    }
    return r;
  };

  match.playerThrowLethal();
  for (let i = 0; i < 10; i++) {
    calls = 0;
    console.log(`--- frame ${i} ---`);
    match.update(1 / 60);
    if (!bot.alive) {
      console.log("KILLED");
      break;
    }
  }
  match.dispose();
});
