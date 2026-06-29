import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { buildAttachmentMeshes } from "./AttachmentVisuals.ts";

function meshCount(g: THREE.Object3D): number {
  let n = 0;
  g.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) n++;
  });
  return n;
}

Deno.test("iron sights / no optic build no attachment geometry", () => {
  assertEquals(meshCount(buildAttachmentMeshes("assault", ["iron"])), 0);
  assertEquals(meshCount(buildAttachmentMeshes("assault", [])), 0);
});

Deno.test("each optic builds visible geometry", () => {
  assert(meshCount(buildAttachmentMeshes("assault", ["reddot"])) >= 3, "red dot: mount+ring+dot");
  assert(meshCount(buildAttachmentMeshes("assault", ["holo"])) >= 3, "holo: frame+pane+reticle");
  assert(meshCount(buildAttachmentMeshes("assault", ["acog"])) >= 2, "acog: tube+lens");
});

Deno.test("barrel, grip and magazine attachments add geometry", () => {
  assert(meshCount(buildAttachmentMeshes("assault", ["suppressor"])) >= 1);
  assert(meshCount(buildAttachmentMeshes("assault", ["foregrip"])) >= 1);
  assert(meshCount(buildAttachmentMeshes("assault", ["laser"])) >= 2); // box + beam
  assert(meshCount(buildAttachmentMeshes("assault", ["drum"])) >= 1);
});

Deno.test("a fully-kitted loadout stacks all attachment meshes", () => {
  const g = buildAttachmentMeshes("assault", ["acog", "suppressor", "foregrip", "extmag"]);
  assert(meshCount(g) >= 4, "optic + barrel + grip + mag");
});

Deno.test("pistols don't get a magazine attachment, launchers skip mags too", () => {
  assertEquals(meshCount(buildAttachmentMeshes("pistol", ["extmag"])), 0);
  assertEquals(meshCount(buildAttachmentMeshes("launcher", ["drum"])), 0);
});

Deno.test("unknown attachment ids are ignored, not thrown", () => {
  assertEquals(meshCount(buildAttachmentMeshes("assault", ["nope", "bogus"])), 0);
});
