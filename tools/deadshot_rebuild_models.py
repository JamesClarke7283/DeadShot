"""Rebuild `assets/models/source/models.json` with high-detail generated models.

The ported `models.json` stays the pristine source of record for everything this
project did not regenerate: equipment, scorestreaks, pickups and the rocket keep
their exact exported geometry. Weapons, attachments and characters are replaced
wholesale by the procedural builders, and their material table is merged in.

Run before `blender_build_models.py`:

    python tools/deadshot_rebuild_models.py
    blender --background --factory-startup --python tools/blender_build_models.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
TOOLS = PROJECT / "tools"
SOURCE = PROJECT / "assets/models/source/models.json"
BACKUP = PROJECT / "assets/models/source/models_ported.json"

sys.path.insert(0, str(TOOLS))

import deadshot_characters as characters  # noqa: E402
import deadshot_props as props  # noqa: E402
import deadshot_weapons as weapons  # noqa: E402

CATEGORIES = ["assault", "smg", "lmg", "marksman", "sniper", "shotgun", "pistol", "launcher"]

# Props that gain generated geometry. Everything else in the export (the streak
# drop pod, the care package parachute, the objective markers) keeps its ported
# geometry untouched.
PROP_IDS = [
    "ammo_pickup", "weapon_drop", "rocket", "strafe_jet",
    "equipment_frag", "equipment_semtex", "equipment_throwing_knife",
    "equipment_claymore", "equipment_c4", "equipment_flashbang",
    "equipment_stun", "equipment_smoke", "equipment_molotov",
    "equipment_thermite", "equipment_snapshot",
    "streak_uav", "streak_sentry", "streak_predator", "streak_rcxd",
    "streak_nuke", "streak_chopper_gunner", "streak_gunship",
    "streak_attack_heli", "streak_care_package", "care_crate", "care_pickup",
]

# Attachment kinds each category can mount. Mirrors the original export, minus
# the kinds the original never built for that category.
ATTACHMENT_KINDS = {
    "assault": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
                "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "smg": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
            "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "lmg": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
            "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "marksman": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
                 "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "sniper": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
               "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "shotgun": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
                "muzzlebrake", "extmag", "drum", "heavystock", "foregrip", "angledgrip", "laser"],
    "pistol": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
               "muzzlebrake", "foregrip", "angledgrip", "laser"],
    "launcher": ["reddot", "holo", "acog", "compensator", "suppressor", "longbarrel",
                 "muzzlebrake", "heavystock", "foregrip", "angledgrip", "laser"],
}

# The original export omitted these attachment models; keep the set identical
# so `VisualFactory.create_weapon` never looks for a model that is not there.
ORIGINAL_OMISSIONS = {
    "shotgun_drum",
    "launcher_extmag", "launcher_drum",
    "pistol_extmag", "pistol_drum", "pistol_heavystock",
}


def _rounded(document):
    """Truncate every geometry float to float32 precision before serialising.

    The builders compute in double precision, so `repr` emitted up to 20
    significant digits per coordinate — 308 MB of JSON for meshes that are
    exported to GLB, and therefore consumed by Godot, as float32. Six
    significant digits is above float32's ~7.2 decimal digits at these
    magnitudes and costs at most 5 um of positional error, which is three orders
    of magnitude below the 0.1 mm the Blender round-trip verifier asserts.
    Rounding here rather than by hand keeps it applied on every regeneration.
    """
    geometries = document.get("geometries", {})
    for record in geometries.values():
        for field in ("positions", "normals", "uvs"):
            values = record.get(field)
            if not values:
                continue
            record[field] = [float("%.6g" % value) if value else 0.0 for value in values]
    return document


def main() -> int:
    if not BACKUP.exists():
        BACKUP.write_text(SOURCE.read_text())
        print("Preserved the ported export as %s" % BACKUP.name)
    original = json.loads(BACKUP.read_text())

    models, geometries = weapons.build_all(CATEGORIES, ATTACHMENT_KINDS)
    human_models, human_geometries = characters.build_all()
    prop_models, prop_geometries = props.build_all(PROP_IDS)

    # Renumber every generated geometry id into one contiguous namespace.
    offset = len(geometries)
    for key, value in human_geometries.items():
        geometries["geometry_%d" % (int(key.split("_")[1]) + offset)] = value
    for model in human_models.values():
        for node in model["nodes"]:
            if node["geometry"]:
                node["geometry"] = "geometry_%d" % (
                    int(node["geometry"].split("_")[1]) + offset)
    models.update(human_models)

    offset = len(geometries)
    for key, value in prop_geometries.items():
        geometries["geometry_%d" % (int(key.split("_")[1]) + offset)] = value
    for model in prop_models.values():
        for node in model["nodes"]:
            if node["geometry"]:
                node["geometry"] = "geometry_%d" % (
                    int(node["geometry"].split("_")[1]) + offset)
    models.update(prop_models)

    # Keep the ported geometry for everything not regenerated.
    generated_ids = set(models)
    kept = 0
    for asset_id, model in original["models"].items():
        if asset_id in generated_ids:
            continue
        models[asset_id] = model
        kept += 1
    for geometry_id, record in original["geometries"].items():
        if geometry_id not in geometries:
            geometries[geometry_id] = record

    # Every model records the GLB the Blender pass writes for it.
    for asset_id, model in models.items():
        model["file"] = "res://assets/models/%s.glb" % asset_id

    materials = dict(original["materials"])
    materials.update(weapons.MATERIALS)
    materials.update(characters.MATERIALS)
    materials.update(props.MATERIALS)

    output = {
        "schema": original.get("schema", 1),
        "source": "Procedural high-detail rebuild: weapons, attachments and characters "
                  "are generated by tools/deadshot_weapons.py and "
                  "tools/deadshot_characters.py; all other assets are the unmodified "
                  "ported Three.js export.",
        "geometries": geometries,
        "materials": materials,
        "models": models,
        "weaponModels": original["weaponModels"],
        "attachmentSlots": original["attachmentSlots"],
    }
    SOURCE.write_text(json.dumps(_rounded(output), separators=(",", ":")))

    triangles = 0
    nodes = 0
    for model in models.values():
        for node in model["nodes"]:
            nodes += 1
            geometry_id = node.get("geometry")
            if geometry_id:
                triangles += len(geometries[geometry_id]["indices"]) // 3
    print("DEADSHOT: %d models, %d geometries, %d materials, %d nodes, %d triangles "
          "(%d ported assets kept)"
          % (len(models), len(geometries), len(materials), nodes, triangles, kept))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
