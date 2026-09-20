# Editable Blender sources

`models.blend` contains one scene per source model. The library includes team humanoids with
facial details, all weapon category models and the held knife, every attachment with visible
source geometry, all scorestreak vehicles, the care-package crate, and all 11 thrown equipment
models. Every original weapon ID maps to its original category geometry in `../manifest.json`.

The 138 GLBs are produced by Blender from the geometry, vertex normals and local matrices in
`models.json`. Blender authoring is Z-up; GLB export returns to the original Y-up coordinates.
Animation pivots retain their source hierarchy. Godot builds the named animation pivots and the
realistic surface materials through `scripts/visuals/visual_factory.gd`.

## Regenerating

`models.json` is generated, not hand-edited. `models_ported.json` preserves the original ported
Three.js export that the detail builders replace, and is used as the fallback source for every
asset that has no builder of its own.

```sh
python tools/deadshot_rebuild_models.py
blender --background --factory-startup --python tools/blender_build_models.py
godot --headless --path . --import
python tools/run_check.py --script tools/blender_verify_models.gd
```

`models.json` is written with every geometry float truncated to six significant
digits. The builders compute in double precision, so `repr` emitted up to 20
digits per coordinate — 308 MB of JSON describing meshes that are exported to
GLB, and therefore read by Godot, as float32. Six digits is above float32's
precision at these magnitudes and costs at most 5 µm of positional error, three
orders of magnitude below the 0.1 mm the round-trip verifier asserts; it brings
the file to 182 MB. The truncation lives in the generator, so it is reapplied on
every rebuild rather than being a one-off edit to the data.

`deadshot_rebuild_models.py` rewrites `models.json` from the builders and keeps the ported
geometry for anything they do not cover, so the two never drift. It reads that fallback from
`models_ported.json`, and only writes that file when it is absent — so delete it before a first
run and it captures whatever `models.json` currently holds, losing the ported source. Keep it
under version control.

## Detail builders

Weapons, attachments, characters and props are generated procedurally in metres, with +Y up, by:

| Module | Covers | Detail |
| --- | --- | --- |
| `deadshot_detail.py` | shared DSL | sweeping, extrusion, chamfers, smooth-shaded tubes |
| `deadshot_weapons.py` | 8 categories, the knife, all attachments | 168–192 tris → 30 546–48 374 per weapon, 6 352–9 524 per attachment |
| `deadshot_characters.py` | `human_blue`, `human_red`, `human_ffa` | 2728 tris → 59 554 tris each |
| `deadshot_props.py` | scorestreaks, equipment, pickups, rocket | 84–2728 tris → 4 064–26 892 tris |

Detail is chosen for what the renderer can resolve rather than for a triangle
budget alone: true silhouette (chamfers and bevels, not sharp box edges),
separation between adjacent volumes (recessed panel lines), and small proud
features — screws, rivets, hinges, stitches, buckles — that catch a highlight
under the parallax-mapped surface shader. A reusable screw/pin helper and high
primitive station counts are the cheapest levers; adding segments to a cylinder
is nearly free visually, so the structure is what the budget is spent on.

Each asset keeps the named pivots the gameplay code drives: `gun`, `muzzle` and `knife` on every
weapon; `hips`, `head`, `face`, `headband` and the four limb joints on characters; `rotor`,
`mainRotor`, `tailRotor` and the sentry's `gun` on the streaks. `VisualFactory.part()` and the
streak/equipment systems address these by name, so the names are part of the contract rather than
descriptions, and the detail builders preserve them.

Every mesh is built with outward-facing windings from a single code path, and `sweep()` normalises
the winding against each frame's handedness, so no part can silently disappear under back-face
culling.

## Maps

`tools/deadshot_enrich_maps.py` adds the architectural detail the ported blockout omits — parapets,
base plinths, window and door frames, glazing and downpipes — to the structures in
`data/maps/*.json`. It is purely additive: it never edits or removes an authored node, so the
exported collision boxes, spawn pads and navigation graph are untouched, and `MapWorld` builds the
same world it did before.

## Verification

`tools/snapshot_assets.gd` renders every regenerated asset through the real material system into
`assets/models/previews_*.png`, framing each one from its measured world bounds. Those previews are
the visual record of the geometry rebuild; the numeric guarantees live in
`tools/blender_verify_models.gd` (every source local transform, geometry bound, hierarchy node and
material) and `scripts/world/verify_maps.gd` (authored and detail node counts, colliders, spawns
and the navigation graph).
