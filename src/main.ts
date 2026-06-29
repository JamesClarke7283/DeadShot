// DeadShot — entry point.
//
// Phase 0 stub: renders a single toon-shaded test cube on a lit ground plane to
// validate the Deno -> esbuild -> /bundle.js -> browser pipeline. Phase 1 (1.1)
// replaces the body of this file with a bootstrap of the `Game` orchestrator.

import * as THREE from "three";

function hideLoading(): void {
  const el = document.getElementById("loading");
  if (el) el.classList.add("hidden");
}

function main(): void {
  const canvas = document.getElementById("game") as HTMLCanvasElement | null;
  if (!canvas) throw new Error("#game canvas not found");

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio, 2));
  renderer.setSize(globalThis.innerWidth, globalThis.innerHeight);
  renderer.shadowMap.enabled = true;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x9fd3ff);

  const camera = new THREE.PerspectiveCamera(
    70,
    globalThis.innerWidth / globalThis.innerHeight,
    0.1,
    1000,
  );
  camera.position.set(3, 3, 5);
  camera.lookAt(0, 0.5, 0);

  // Lights
  const hemi = new THREE.HemisphereLight(0xffffff, 0x444466, 0.9);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xffffff, 1.4);
  sun.position.set(5, 10, 7);
  sun.castShadow = true;
  scene.add(sun);

  // Toon-shaded test cube
  const cube = new THREE.Mesh(
    new THREE.BoxGeometry(1.5, 1.5, 1.5),
    new THREE.MeshToonMaterial({ color: 0xff6b35 }),
  );
  cube.position.y = 0.75;
  cube.castShadow = true;
  scene.add(cube);

  // Ground
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(40, 40),
    new THREE.MeshToonMaterial({ color: 0x6fae5a }),
  );
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  globalThis.addEventListener("resize", () => {
    camera.aspect = globalThis.innerWidth / globalThis.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(globalThis.innerWidth, globalThis.innerHeight);
  });

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = clock.getDelta();
    cube.rotation.x += dt * 0.6;
    cube.rotation.y += dt * 0.9;
    renderer.render(scene, camera);
  });

  hideLoading();
  console.info("[DeadShot] boot stub running — Three.js r" + THREE.REVISION);
}

main();
