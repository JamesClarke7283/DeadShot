// DeadShot — entry point. Bootstraps the Game orchestrator.

import { Game } from "./core/Game.ts";

function main(): void {
  const canvas = document.getElementById("game") as HTMLCanvasElement | null;
  if (!canvas) throw new Error("#game canvas not found");

  const game = new Game(canvas);
  // Expose for the dev console / debugging (Phase 10 wires a real console UI).
  (globalThis as unknown as { deadshot: Game }).deadshot = game;
  game.start();

  console.info("[DeadShot] engine started");
}

main();
