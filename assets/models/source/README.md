# Editable Blender sources

`models.blend` contains one scene per source model. The library includes team humanoids with facial
details, all weapon category models and the held knife, every attachment with visible source
geometry, all scorestreak vehicles, the care-package crate, and all 11 thrown equipment models.
Every original weapon ID maps to its original category geometry in `../manifest.json`.

The 138 GLBs are produced by Blender from the original Three.js BufferGeometry, vertex normals, UVs,
material colors, and local matrices in `models.json`. Blender authoring is Z-up; GLB export returns
to the original Y-up coordinates. Animation pivots retain their source hierarchy, and inverted
outline hulls are baked as editable extruded, reversed-winding meshes. Godot restores the source
toon shader and named animation pivots through `scripts/visuals/visual_factory.gd`.

Rebuild from the Godot project directory:

```sh
deno run -A --config ../DeadShot/deno.json tools/export_models.ts
blender --background --factory-startup --python tools/blender_build_models.py
python tools/run_check.py --script tools/blender_verify_models.gd
```

The build runs in a separate Blender process and never modifies an open user scene. The same build
produces editable map sources in `assets/maps/*.blend`. Those maps render from their original
geometry JSON in Godot so foliage wind and instancing remain native. These source folders are
ignored by Godot's importer; the exported GLBs are the runtime assets.

Verified: every imported hierarchy node and material, all source weapon IDs, animation pivots and
formulas, and outline visibility with a real renderer. Whole-game visual comparison remains a
separate migration acceptance step.
