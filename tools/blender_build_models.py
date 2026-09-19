"""Rebuild the original Three.js models in a fresh, isolated Blender process.

blender --background --factory-startup --python tools/blender_build_models.py
Outputs editable source/models.blend, game-ready GLBs, and a small Godot manifest.
The user's running Blender session is never opened, modified, or saved.
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

PROJECT = Path(__file__).resolve().parent.parent
OUTPUT = PROJECT / "assets/models"
SOURCE = OUTPUT / "source/models.json"
# Three/glTF and Godot are Y-up. Blender authoring is Z-up.
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()
data = json.loads(SOURCE.read_text())
bpy.context.preferences.filepaths.save_version = 0
material_cache = {}
mesh_cache = {}


def triples(values):
    return [values[i:i + 3] for i in range(0, len(values), 3)]


def make_material(key, record):
    if key in material_cache:
        return material_cache[key]
    mat = bpy.data.materials.new(key)
    mat.diffuse_color = (*record["color"], record.get("opacity", 1))
    mat.use_nodes = True
    mat.use_backface_culling = not record.get("doubleSide", False)
    mat["deadshot_record"] = json.dumps(record)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = mat.diffuse_color
    bsdf.inputs["Roughness"].default_value = 1
    bsdf.inputs["Emission Color"].default_value = (*record.get("emissive", [0, 0, 0]), 1)
    bsdf.inputs["Emission Strength"].default_value = 1
    bsdf.inputs["Alpha"].default_value = record.get("opacity", 1)
    if record.get("transparent"):
        mat.surface_render_method = "DITHERED"
    if record.get("unlit"):
        emission = mat.node_tree.nodes.new("ShaderNodeEmission")
        emission.inputs["Color"].default_value = mat.diffuse_color
        emission.inputs["Strength"].default_value = 1
        out = mat.node_tree.nodes.get("Material Output")
        mat.node_tree.links.new(emission.outputs[0], out.inputs["Surface"])
    material_cache[key] = mat
    return mat


def make_mesh(geometry_id, material_id, geometry, material, prefix=""):
    # Baking a back-face hull makes outlines editable in Blender and portable
    # in GLB. The Godot factory marks them unlit without extruding a second time.
    key = (prefix, geometry_id, material_id)
    if key in mesh_cache:
        return mesh_cache[key]
    vertices = triples(geometry["positions"])
    normals = triples(geometry.get("normals", []))
    triangles = triples(geometry["indices"])
    if material.get("outline"):
        thickness = material.get("thickness", 0.03)
        vertices = [(Vector(v) + Vector(normals[i]).normalized() * thickness)[:] for i, v in enumerate(vertices)]
        triangles = [(a, c, b) for a, b, c in triangles]
        normals = [(-Vector(n))[:] for n in normals]
    vertices = [(C.to_3x3() @ Vector(v))[:] for v in vertices]
    normals = [(C.to_3x3() @ Vector(n))[:] for n in normals]
    mesh = bpy.data.meshes.new(f"{prefix}{geometry_id}_{material_id}")
    mesh.from_pydata(vertices, [], triangles)
    mesh.materials.append(make_material(prefix + material_id, material))
    mesh.update()
    if normals:
        for poly in mesh.polygons:
            poly.use_smooth = True
        mesh.normals_split_custom_set_from_vertices(normals)
    uv_values = geometry.get("uvs", [])
    if uv_values:
        uv = mesh.uv_layers.new(name="UVMap")
        for loop in mesh.loops:
            index = loop.vertex_index * 2
            uv.data[loop.index].uv = (uv_values[index], uv_values[index + 1])
    mesh_cache[key] = mesh
    return mesh


def make_scene(asset_id, nodes, geometries, materials, prefix=""):
    scene = bpy.data.scenes.new(asset_id)
    bpy.context.window.scene = scene
    objects = []
    for index, node in enumerate(nodes):
        geometry_id = node.get("geometry")
        material_id = node.get("material")
        mesh = None
        if geometry_id is not None:
            mesh = make_mesh(str(geometry_id), str(material_id), geometries[str(geometry_id)], materials[str(material_id)], prefix)
        name = node["name"] or f"part_{index}"
        obj = bpy.data.objects.new(f"{asset_id}__{name}", mesh)
        scene.collection.objects.link(obj)
        obj["ds_name"] = name
        obj["ds_visible"] = node.get("visible", True)
        obj["ds_cast_shadow"] = node.get("castShadow", False)
        if material_id is not None:
            obj["ds_material"] = prefix + str(material_id)
        parent = node.get("parent", -1)
        if parent >= 0:
            obj.parent = objects[parent]
        values = node["matrix"]
        source_matrix = Matrix(tuple(tuple(values[col * 4 + row] for col in range(4)) for row in range(4)))
        obj.matrix_local = C @ source_matrix @ CI
        objects.append(obj)
    scene["deadshot_source"] = "Exact BufferGeometry extracted from original Three.js r180 project"
    scene["coordinate_system"] = "Z-up authoring; GLB exports convert back to original Y-up"
    return scene


def export_glb(path):
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_active_scene=True,
        export_yup=True, export_normals=True, export_texcoords=True,
        export_materials="EXPORT", export_extras=True, export_animations=False,
    )


# Factory-startup scene belongs exclusively to this background process.
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
original_scene = bpy.context.scene
manifest = {"schema": 1, "materials": data["materials"], "models": {}, "weaponModels": data["weaponModels"], "attachmentSlots": data["attachmentSlots"]}
for asset_id, model in data["models"].items():
    scene = make_scene(asset_id, model["nodes"], data["geometries"], data["materials"])
    export_glb(OUTPUT / f"{asset_id}.glb")
    manifest["models"][asset_id] = {
        "file": model["file"],
        "nodes": {node["name"]: {key: node[key] for key in ("material", "visible", "castShadow") if key in node} for node in model["nodes"]},
    }
bpy.data.scenes.remove(original_scene)
bpy.context.window.scene = bpy.data.scenes["human_blue"]
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "source/models.blend"), compress=True)
(OUTPUT / "manifest.json").write_text(json.dumps(manifest, separators=(",", ":")))
print(f"DEADSHOT: rebuilt {len(data['models'])} exact models in Blender")

# Preserve editable Blender sources for all three environments as well. Maps
# render from the same JSON in Godot to retain instancing and animated foliage.
map_output = PROJECT / "assets/maps"
map_output.mkdir(parents=True, exist_ok=True)
for map_json in sorted((PROJECT / "data/maps").glob("*.json")):
    map_data = json.loads(map_json.read_text())
    if not {"nodes", "geometries", "materials"}.issubset(map_data):
        continue
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    material_cache.clear()
    mesh_cache.clear()
    scene = make_scene(map_json.stem, map_data["nodes"], map_data["geometries"], map_data["materials"], map_json.stem + "_")
    for other_scene in list(bpy.data.scenes):
        if other_scene != scene:
            bpy.data.scenes.remove(other_scene)
    bpy.ops.wm.save_as_mainfile(filepath=str(map_output / f"{map_json.stem}.blend"), compress=True)
    print(f"DEADSHOT: editable Blender map {map_json.stem}, {len(map_data['nodes'])} objects")
