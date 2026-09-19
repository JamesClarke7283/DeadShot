"""Add architectural detail to the ported maps.

The ported arenas are the original Three.js blockout: every structure is a bare
untextured quad — a 12x5 m "building" is one flat wall panel with no roof, no
openings and no trim. The realistic material system then shades those panels
correctly, which is why they read as flat cardboard.

This pass is purely additive. It never edits or removes an authored node, so:

  * the exported collision boxes, spawn pads and navigation graph are untouched;
  * `MapWorld` keeps building exactly the same world it did before;
  * the new nodes join the bullet-geometry pass, which is correct — a roof
    should stop a bullet.

Everything added is derived from the authored geometry itself: wall panels are
clustered into buildings by shared corner vertices, and each building gains a
roof, a parapet, a base plinth, and window/door frames applied to its facades.

    python tools/deadshot_enrich_maps.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from deadshot_detail import Mesh  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
MAP_DIR = PROJECT / "data/maps"

# New material slots are appended past the authored ones so indices never shift.
MATERIALS = {
    "ds_map_parapet": {"color": [0.40, 0.36, 0.30], "emissive": [0, 0, 0], "opacity": 1,
                       "transparent": False, "doubleSide": False, "unlit": False,
                       "outline": False, "thickness": 0, "depthTest": True,
                       "surface": "plaster", "minLuminance": 0.14, "maxLuminance": 0.46,
                       "dust": 0.24, "grime": 0.26, "roughness": 0.9, "tiling": 0.8},
    "ds_map_plinth": {"color": [0.30, 0.27, 0.23], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "stone", "minLuminance": 0.09, "maxLuminance": 0.26,
                      "dust": 0.20, "grime": 0.40, "roughness": 0.95, "tiling": 1.1},
    "ds_map_frame": {"color": [0.46, 0.42, 0.35], "emissive": [0, 0, 0], "opacity": 1,
                     "transparent": False, "doubleSide": False, "unlit": False,
                     "outline": False, "thickness": 0, "depthTest": True,
                     "surface": "plaster", "minLuminance": 0.15, "maxLuminance": 0.50,
                     "dust": 0.20, "grime": 0.30, "roughness": 0.88, "tiling": 1.0},
    "ds_map_glass_dark": {"color": [0.05, 0.06, 0.07], "emissive": [0.004, 0.006, 0.010],
                          "opacity": 1, "transparent": False, "doubleSide": False,
                          "unlit": False, "outline": False, "thickness": 0,
                          "depthTest": True, "surface": "glass",
                          "minLuminance": 0.03, "maxLuminance": 0.12,
                          "dust": 0.05, "grime": 0.10, "roughness": 0.22,
                          "metallic": 0.10, "specular": 0.85, "tiling": 1.4},
    "ds_map_door": {"color": [0.16, 0.13, 0.10], "emissive": [0, 0, 0], "opacity": 1,
                    "transparent": False, "doubleSide": False, "unlit": False,
                    "outline": False, "thickness": 0, "depthTest": True,
                    "surface": "wood", "minLuminance": 0.08, "maxLuminance": 0.24,
                    "dust": 0.14, "grime": 0.28, "roughness": 0.72, "tiling": 1.3},
    "ds_map_metal_trim": {"color": [0.13, 0.13, 0.14], "emissive": [0, 0, 0], "opacity": 1,
                          "transparent": False, "doubleSide": False, "unlit": False,
                          "outline": False, "thickness": 0, "depthTest": True,
                          "surface": "metal", "minLuminance": 0.14, "maxLuminance": 0.34,
                          "dust": 0.16, "grime": 0.30, "roughness": 0.45, "metallic": 0.7},
    "ds_map_prop_body": {"color": [0.20, 0.19, 0.17], "emissive": [0, 0, 0], "opacity": 1,
                         "transparent": False, "doubleSide": False, "unlit": False,
                         "outline": False, "thickness": 0, "depthTest": True,
                         "surface": "vehicle", "minLuminance": 0.12, "maxLuminance": 0.30,
                         "dust": 0.18, "grime": 0.22, "roughness": 0.42, "metallic": 0.35},
    "ds_map_prop_trim": {"color": [0.28, 0.29, 0.30], "emissive": [0, 0, 0], "opacity": 1,
                         "transparent": False, "doubleSide": False, "unlit": False,
                         "outline": False, "thickness": 0, "depthTest": True,
                         "surface": "metal", "minLuminance": 0.16, "maxLuminance": 0.38,
                         "dust": 0.20, "grime": 0.28, "roughness": 0.48, "metallic": 0.6},
    "ds_map_rubber": {"color": [0.045, 0.045, 0.047], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "rubber", "minLuminance": 0.05, "maxLuminance": 0.16,
                      "dust": 0.10, "grime": 0.14, "roughness": 0.95},
    "ds_map_lamp": {"color": [0.86, 0.84, 0.72], "emissive": [0.10, 0.09, 0.05],
                    "opacity": 1, "transparent": False, "doubleSide": False,
                    "unlit": False, "outline": False, "thickness": 0,
                    "depthTest": True, "surface": "glass", "minLuminance": 0.30,
                    "maxLuminance": 0.80, "roughness": 0.18, "specular": 0.9},
}

# Authored node names that are structural shells worth detailing. Props, cars,
# trees and terrain keep exactly the shapes the original export gave them.
STRUCTURE_NAMES = ("building", "mosque", "stall", "pier", "dock", "container")

# Wall panels are boxes 0.2-0.4 m thick, and a building's walls meet at the same
# footprint corner rather than at identical vertices: a 12 m south wall spans the
# full footprint while the 9 m east wall is centred on the same corner, so their
# extreme vertices differ by up to half a panel thickness. Snapping to a coarse
# cell and searching the neighbouring cells merges them without merging distinct
# structures, which in these blockouts stand metres apart.
CLUSTER_CELL = 0.5

TAU = math.tau


def _triples(values):
    return [values[i:i + 3] for i in range(0, len(values), 3)]


def _transform(matrix, point):
    return (
        matrix[0] * point[0] + matrix[4] * point[1] + matrix[8] * point[2] + matrix[12],
        matrix[1] * point[0] + matrix[5] * point[1] + matrix[9] * point[2] + matrix[13],
        matrix[2] * point[0] + matrix[6] * point[1] + matrix[10] * point[2] + matrix[14],
    )


# --------------------------------------------------------------------------
# Box helpers. All input is world space; the node matrix stays identity.
# --------------------------------------------------------------------------

def add_box(mesh, low, high, skip_bottom=False):
    x0, y0, z0 = low
    x1, y1, z1 = high
    p = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    mesh.quad(p[0], p[3], p[2], p[1])       # -Z
    mesh.quad(p[4], p[5], p[6], p[7])       # +Z
    mesh.quad(p[1], p[2], p[6], p[5])       # +X
    mesh.quad(p[3], p[0], p[4], p[7])       # -X
    mesh.quad(p[2], p[3], p[7], p[6])       # +Y
    if not skip_bottom:
        mesh.quad(p[0], p[1], p[5], p[4])   # -Y


def box_along(mesh, start, end, width, thickness, up):
    """A rectangular member running from `start` to `end` with a square section.

    `up` is the outward direction of the face the member is applied to; the
    member is pushed `thickness` along it so it sits proud of the wall.
    """
    dx, dy, dz = end[0] - start[0], end[1] - start[1], end[2] - start[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-5:
        return
    ux, uy, uz = dx / length, dy / length, dz / length
    # Section axes: `side` perpendicular to the run in the wall plane, `up`
    # outward. Derived so the member keeps its width whatever the run direction.
    sx, sy, sz = uy * up[2] - uz * up[1], uz * up[0] - ux * up[2], ux * up[1] - uy * up[0]
    side_len = math.sqrt(sx * sx + sy * sy + sz * sz)
    if side_len < 1e-6:
        sx, sy, sz = (1.0, 0.0, 0.0)
    else:
        sx, sy, sz = sx / side_len, sy / side_len, sz / side_len
    hw = width * 0.5
    corners_low = []
    corners_high = []
    for along, sign_side, sign_up in ((0.0, -1, 0), (0.0, 1, 0), (0.0, -1, 1), (0.0, 1, 1)):
        pass
    # Build the 8 corners explicitly: two ends x two sides x two depths.
    for t in (0.0, length):
        base = (start[0] + ux * t, start[1] + uy * t, start[2] + uz * t)
        ring = []
        for sign_side in (-1.0, 1.0):
            for sign_up in (0.0, 1.0):
                ring.append((
                    base[0] + sx * hw * sign_side + up[0] * thickness * sign_up,
                    base[1] + sy * hw * sign_side + up[1] * thickness * sign_up,
                    base[2] + sz * hw * sign_side + up[2] * thickness * sign_up,
                ))
        (corners_low if t == 0.0 else corners_high).extend(ring)
    a0, a1, a2, a3 = corners_low
    b0, b1, b2, b3 = corners_high
    mesh.quad(a0, a1, b1, b0)   # side
    mesh.quad(a2, a3, b3, b2)   # side
    mesh.quad(a1, a3, b3, b1)   # outer face
    mesh.quad(a0, a2, b2, b0)   # inner face
    mesh.quad(a2, a0, a1, a3)   # start cap
    mesh.quad(b0, b1, b3, b2)   # end cap


# --------------------------------------------------------------------------
# Wall clustering.
# --------------------------------------------------------------------------

def wall_corners(node, geometries):
    """World-space AABB of a wall panel."""
    geometry = geometries[str(node["geometry"])]
    points = [_transform(node["matrix"], p) for p in _triples(geometry["positions"])]
    if len(points) < 4:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    zs = [p[2] for p in points]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def panel_footprint(bounds):
    """The panel's footprint corners in the XZ plane, ordered around the outline."""
    low, high = bounds
    return ((low[0], low[2]), (high[0], low[2]), (high[0], high[2]), (low[0], high[2]))


def cluster(bounds_list):
    """Groups wall panels into buildings by shared footprint corners.

    Two panels belong to the same structure when a footprint corner of one lies
    within `CLUSTER_CELL` of a footprint corner of the other, tested cell to
    cell so an 8-connected neighbourhood is covered without an O(n^2) sweep.
    """
    parents = list(range(len(bounds_list)))

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parents[rb] = ra

    buckets = {}
    for index, bounds in enumerate(bounds_list):
        keys = set()
        for x, z in panel_footprint(bounds):
            keys.add((int(math.floor(x / CLUSTER_CELL)), int(math.floor(z / CLUSTER_CELL))))
            # A corner sitting on a cell boundary must also claim its neighbours.
            keys.add((int(math.floor((x + CLUSTER_CELL * 0.5) / CLUSTER_CELL)),
                      int(math.floor(z / CLUSTER_CELL))))
            keys.add((int(math.floor(x / CLUSTER_CELL)),
                      int(math.floor((z + CLUSTER_CELL * 0.5) / CLUSTER_CELL))))
        for key in keys:
            if key in buckets:
                union(index, buckets[key])
            else:
                buckets[key] = index
    groups = {}
    for index in range(len(bounds_list)):
        groups.setdefault(find(index), []).append(index)
    return list(groups.values())




def enrich(map_id):
    path = MAP_DIR / ("%s.json" % map_id)
    data = json.loads(path.read_text())
    geometries = data["geometries"]
    materials = data["materials"]

    # Idempotent: drop any detail this pass emitted previously, so re-running
    # replaces rather than stacks the roofs, parapets and openings. Only the
    # geometry those detail nodes referenced is released; authored geometry is
    # never touched, even if it happens to be unreferenced.
    detail_prefix = "detail_%s_" % map_id
    released = set()
    kept_nodes = []
    for node in data["nodes"]:
        if str(node.get("name", "")).startswith(detail_prefix):
            if node.get("geometry") is not None:
                released.add(str(node["geometry"]))
        else:
            kept_nodes.append(node)
    data["nodes"] = kept_nodes
    for key in released:
        geometries.pop(key, None)
    for name in list(materials):
        if str(materials[name].get("name", "")).startswith("ds_map_"):
            del materials[name]

    # Append the new materials without disturbing the authored indices.
    base = max(int(key) for key in materials) + 1
    material_index = {}
    for offset, (name, record) in enumerate(MATERIALS.items()):
        key = str(base + offset)
        materials[key] = dict(record, name=name)
        material_index[name] = key

    # Only the structural panels are considered; props keep their own shapes.
    structural = [(index, node) for index, node in enumerate(data["nodes"])
                  if node["name"] in STRUCTURE_NAMES and node.get("geometry") is not None]
    # Wall panels are the thin ones; a roof must not be built from a slab.
    walls = []
    for index, node in structural:
        bounds = wall_corners(node, geometries)
        if bounds is None:
            continue
        low, high = bounds
        size = (high[0] - low[0], high[1] - low[1], high[2] - low[2])
        # Vertical, thin panels are walls. Their thickness is the smallest of the
        # two horizontal extents.
        if size[1] < 1.2 or min(size[0], size[2]) > 1.0:
            continue
        walls.append((bounds, node["name"]))

    parapet_mesh = Mesh()
    plinth_mesh = Mesh()
    frame_mesh = Mesh()
    glass_mesh = Mesh()
    door_mesh = Mesh()
    trim_mesh = Mesh()

    next_geometry = max(int(key) for key in geometries) + 1

    def add_geometry(mesh, material):
        nonlocal next_geometry
        if mesh.empty():
            return
        key = str(next_geometry)
        next_geometry += 1
        geometries[key] = {
            "positions": mesh.positions,
            "normals": [],
            "uvs": [],
            "indices": mesh.indices,
        }
        data["nodes"].append({
            "name": "detail_%s_%s" % (map_id, material),
            "geometry": key,
            "material": material_index[material],
            "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            "visible": True,
            "castShadow": True,
        })

    groups = cluster([entry[0] for entry in walls])
    built = 0
    for group in groups:
        panels = [walls[index] for index in group]
        lows = [panel[0][0] for panel in panels]
        highs = [panel[0][1] for panel in panels]
        low = (min(p[0] for p in lows), min(p[1] for p in lows), min(p[2] for p in lows))
        high = (max(p[0] for p in highs), max(p[1] for p in highs), max(p[2] for p in highs))
        width, depth = high[0] - low[0], high[2] - low[2]
        height = high[1] - low[1]
        # A roof needs a real enclosed footprint; a lone panel or a pair is a
        # wall run or a fragment, not a structure.
        if width < 1.5 or depth < 1.5 or height < 0.8:
            continue
        if len(panels) < 3:
            continue
        top = high[1]
        thickness = 0.18
        # Roofs already exist in the authored maps (each structure carries a roof
        # slab), so this pass never builds one. It adds only the architectural
        # detail the blockout omits: a parapet above the roof edge, a base plinth
        # at the wall foot, and openings on the facades.
        del thickness
        # Parapet band standing on the roof edge.
        band = min(0.42, max(0.16, height * 0.10))
        band_width = 0.22
        for (x0, x1, z0, z1) in (
                (low[0] - 0.05, high[0] + 0.05, low[2] - 0.05, low[2] - 0.05 + band_width),
                (low[0] - 0.05, high[0] + 0.05, high[2] + 0.05 - band_width, high[2] + 0.05),
                (low[0] - 0.05, low[0] - 0.05 + band_width, low[2] - 0.05, high[2] + 0.05),
                (high[0] + 0.05 - band_width, high[0] + 0.05, low[2] - 0.05, high[2] + 0.05)):
            add_box(parapet_mesh, (x0, top, z0), (x1, top + band, z1))
        # Base plinth: a shallow skirt around the wall foot. Kept thin and low
        # so it grounds the wall instead of reading as a separate ledge.
        plinth = 0.12
        plinth_height = 0.30
        add_box(plinth_mesh, (low[0] - plinth, low[1] - 0.10, low[2] - plinth),
                (high[0] + plinth, low[1] + plinth_height, high[2] + plinth))
        built += 1

        # Openings, applied to each facade rather than cut from the panel: a
        # recessed frame plus a dark inset reads as a window without disturbing
        # the authored wall geometry or its collider.
        _facade_detail(panels[0][1], low, high, frame_mesh, glass_mesh, door_mesh, trim_mesh)

    add_geometry(parapet_mesh, "ds_map_parapet")
    add_geometry(plinth_mesh, "ds_map_plinth")
    add_geometry(frame_mesh, "ds_map_frame")
    add_geometry(glass_mesh, "ds_map_glass_dark")
    add_geometry(door_mesh, "ds_map_door")
    add_geometry(trim_mesh, "ds_map_metal_trim")

    props = _prop_detail(data, material_index, geometry_for_map(data))

    path.write_text(json.dumps(data, separators=(",", ":")))
    print("%-16s %3d wall panels -> %2d buildings, %d structures, %d props, %d nodes total"
          % (map_id, len(walls), built, len(groups), props, len(data["nodes"])))


def geometry_for_map(data):
    """Returns a `geometry_for(builder) -> key` that appends to the map's table."""
    geometries = data["geometries"]
    counter = [max(int(key) for key in geometries) + 1]

    def geometry_for(builder):
        if builder.empty():
            return None
        key = str(counter[0])
        counter[0] += 1
        geometries[key] = {
            "positions": builder.positions,
            "normals": [],
            "uvs": [],
            "indices": builder.indices,
        }
        return key

    return geometry_for


# --------------------------------------------------------------------------
# Props. Vehicles, cranes, market stalls, radar dishes and barriers are authored
# as assemblies of solid boxes, which the realistic surface pass then shades as
# cardboard. Each instance is grouped by its authored world position and given
# the parts that turn a box car into a car.
# --------------------------------------------------------------------------



def _prop_instances(nodes, name, span=3.0):
    """Groups a prop's parts into instances by proximity.

    A prop is authored as several parts whose centres are metres apart (a car's
    body, cabin and bumpers) but which belong to one object, while distinct
    instances of that prop stand much further apart than any of their own parts.
    Bucketing on the rounded position alone splits a single car into several
    one-part clusters, so parts are unioned when they fall within `span`.
    """
    entries = [node for node in nodes
               if node["name"] == name and node.get("geometry") is not None]
    parents = list(range(len(entries)))

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parents[rb] = ra

    for i in range(len(entries)):
        xi = entries[i]["matrix"][12]
        zi = entries[i]["matrix"][14]
        for j in range(i + 1, len(entries)):
            dx = xi - entries[j]["matrix"][12]
            dz = zi - entries[j]["matrix"][14]
            if dx * dx + dz * dz <= span * span:
                union(i, j)
    groups = {}
    for index, entry in enumerate(entries):
        groups.setdefault(find(index), []).append(entry)
    return groups


def _instance_bounds(nodes, geometries):
    low = [1e9, 1e9, 1e9]
    high = [-1e9, -1e9, -1e9]
    for node in nodes:
        points = [_transform(node["matrix"], p)
                  for p in _triples(geometries[str(node["geometry"])]["positions"])]
        for point in points:
            for axis in range(3):
                low[axis] = min(low[axis], point[axis])
                high[axis] = max(high[axis], point[axis])
    return tuple(low), tuple(high)


def _prop_detail(data, material_index, geometry_for):
    """Adds wheels, glazing, machinery and lamp detail to the authored props.

    Detail is derived per *part* rather than per instance. A prop is authored as
    several boxes whose world positions overlap heavily — four cars parked in a
    row stand about 1.8 m apart while the parts of one car sit within 1 m of each
    other — so no proximity threshold separates instances reliably. Keying off
    each part's own proportions instead is exact: a car's chassis is the wide,
    low part and its cabin is the narrow, raised one, wherever they stand.
    """
    geometries = data["geometries"]
    body = Mesh()
    glass = Mesh()
    trim = Mesh()
    rubber = Mesh()
    lamp = Mesh()
    made = 0

    def emit(mesh, material, name):
        key = geometry_for(mesh)
        if key is None:
            return
        data["nodes"].append({
            "name": "detail_%s_%s" % (data["id"], name),
            "geometry": key,
            "material": material_index[material],
            "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            "visible": True,
            "castShadow": True,
        })

    for node in list(data["nodes"]):
        name = str(node.get("name", ""))
        if name.startswith("detail_") or node.get("geometry") is None:
            continue
        if name not in PROP_RULES:
            continue
        points = [_transform(node["matrix"], p)
                  for p in _triples(geometries[str(node["geometry"])]["positions"])]
        if len(points) < 4:
            continue
        low = [min(point[axis] for point in points) for axis in range(3)]
        high = [max(point[axis] for point in points) for axis in range(3)]
        size = [high[axis] - low[axis] for axis in range(3)]
        if min(size) <= 1e-4:
            continue
        centre = ((low[0] + high[0]) * 0.5, (low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5)
        for rule in PROP_RULES[name]:
            rule(body, glass, trim, rubber, lamp, low, high, size, centre)
        made += 1

    emit(body, "ds_map_prop_body", "prop_body")
    emit(glass, "ds_map_glass_dark", "prop_glass")
    emit(trim, "ds_map_prop_trim", "prop_trim")
    emit(rubber, "ds_map_rubber", "prop_rubber")
    emit(lamp, "ds_map_lamp", "prop_lamp")
    return made


# --------------------------------------------------------------------------
# Per-part prop rules. Each receives the part's world bounds and adds only the
# detail that part actually carries.
# --------------------------------------------------------------------------

def _prop_car(body, glass, trim, rubber, lamp, low, high, size, centre):
    """Wheels under the chassis, glazing around the cabin, lamps on the ends."""
    footprint = max(size[0], size[2])
    if footprint > 3.0:
        # Chassis. The export already carries the wheels as separate parts, so
        # this adds the bumpers, lamps and arches that sit around them.
        radius = min(0.36, max(0.26, size[1] * 0.52))
        for sign_x in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                _arch(rubber, (centre[0] + sign_x * (size[0] * 0.5 - 0.02),
                               low[1] + radius * 0.62,
                               centre[2] + sign_z * (size[2] * 0.5 - radius * 1.25)),
                      radius, sign_z, size[2])
        for sign_z in (-1.0, 1.0):
            _slab(trim, (low[0], low[1] + size[1] * 0.15, centre[2] + sign_z * size[2] * 0.5),
                  (high[0], low[1] + size[1] * 0.45, centre[2] + sign_z * (size[2] * 0.5 + 0.08)))
            _slab(lamp, (low[0] + size[0] * 0.08, low[1] + size[1] * 0.45, centre[2] + sign_z * size[2] * 0.5),
                  (low[0] + size[0] * 0.30, low[1] + size[1] * 0.80, centre[2] + sign_z * (size[2] * 0.5 + 0.04)))
            _slab(lamp, (high[0] - size[0] * 0.30, low[1] + size[1] * 0.45, centre[2] + sign_z * size[2] * 0.5),
                  (high[0] - size[0] * 0.08, low[1] + size[1] * 0.80, centre[2] + sign_z * (size[2] * 0.5 + 0.04)))
    elif size[1] >= 0.30 and footprint > 1.0:
        # Cabin: a glazing band inset on all four sides.
        inset = size[0] * 0.04
        band_low = low[1] + size[1] * 0.14
        band_high = low[1] + size[1] * 0.86
        _slab(glass, (low[0] + inset, band_low, low[2] - 0.02), (high[0] - inset, band_high, low[2]))
        _slab(glass, (low[0] + inset, band_low, high[2]), (high[0] - inset, band_high, high[2] + 0.02))
        _slab(glass, (low[0] - 0.02, band_low, low[2] + inset), (low[0], band_high, high[2] - inset))
        _slab(glass, (high[0], band_low, low[2] + inset), (high[0] + 0.02, band_high, high[2] - inset))


def _prop_crane(body, glass, trim, rubber, lamp, low, high, size, centre):
    """Lattice bracing up the mast, an operator cab and the jib tip."""
    if size[1] > 6.0 and max(size[0], size[2]) < 3.0:
        # Mast: cross bracing on all four faces reads as a lattice.
        steps = 8
        half = max(size[0], size[2]) * 0.42
        for index in range(steps):
            y0 = low[1] + size[1] * index / steps
            y1 = low[1] + size[1] * (index + 1) / steps
            for sign_x in (-1.0, 1.0):
                for sign_z in (-1.0, 1.0):
                    _bar(trim, (centre[0] + sign_x * half, y0, centre[2] + sign_z * half),
                         (centre[0] - sign_x * half, y1, centre[2] + sign_z * half), 0.11)
        # Operator cab at the head of the mast.
        _slab(body, (centre[0] - 1.00, high[1] - 2.40, centre[2] - 1.00),
              (centre[0] + 1.00, high[1] - 0.50, centre[2] + 1.00))
        _slab(glass, (centre[0] - 0.95, high[1] - 2.10, centre[2] - 1.04),
              (centre[0] + 0.95, high[1] - 1.10, centre[2] - 1.00))
        _slab(lamp, (centre[0] - 0.20, high[1], centre[2] - 0.20),
              (centre[0] + 0.20, high[1] + 0.24, centre[2] + 0.20))
    elif size[0] > 8.0:
        # Jib: a lattice underside and a trolley.
        for index in range(6):
            t0 = index / 6.0
            t1 = (index + 1) / 6.0
            _bar(trim, (low[0] + size[0] * t0, low[1], centre[2]),
                 (low[0] + size[0] * t1, low[1] - size[1] * 0.9, centre[2]), 0.10)
            _bar(trim, (low[0] + size[0] * t0, low[1] - size[1] * 0.9, centre[2]),
                 (low[0] + size[0] * t1, low[1], centre[2]), 0.10)
        _slab(body, (centre[0] - 0.45, low[1] - size[1] * 1.5, centre[2] - 0.30),
              (centre[0] + 0.45, low[1], centre[2] + 0.30))


def _prop_stall(body, glass, trim, rubber, lamp, low, high, size, centre):
    """Canopy above the posts, with a valance and goods on the counter."""
    if size[1] > 1.4 and max(size[0], size[2]) < 0.4:
        # A corner post: give it a foot and a finial.
        _slab(trim, (centre[0] - 0.11, low[1], centre[2] - 0.11),
              (centre[0] + 0.11, low[1] + 0.10, centre[2] + 0.11))
        _slab(trim, (centre[0] - 0.09, high[1], centre[2] - 0.09),
              (centre[0] + 0.09, high[1] + 0.14, centre[2] + 0.09))
    elif size[0] > 1.0 and size[1] < 0.25:
        # The counter top: goods stacked on it.
        for index in range(3):
            x = centre[0] + (index - 1) * size[0] * 0.26
            _slab(trim, (x - 0.18, high[1], centre[2] - size[2] * 0.30),
                  (x + 0.18, high[1] + 0.22, centre[2] + size[2] * 0.30))


def _prop_radar(body, glass, trim, rubber, lamp, low, high, size, centre):
    """A curved reflector on the dish, and a feed horn on its mast."""
    footprint = max(size[0], size[2])
    if size[1] > 4.0 and footprint < 3.0:
        # The mast: a feed arm and a beacon.
        _bar(trim, (centre[0], high[1], centre[2]), (centre[0], high[1] + 1.40, centre[2]), 0.10)
        _slab(lamp, (centre[0] - 0.14, high[1] + 1.40, centre[2] - 0.14),
              (centre[0] + 0.14, high[1] + 1.68, centre[2] + 0.14))
    elif footprint > 3.0:
        _dish(body, (centre[0], high[1], centre[2]), footprint * 0.5, 0.60)


def _prop_barrier(body, glass, trim, rubber, lamp, low, high, size, centre):
    """End posts plus a reflective band along the rail."""
    if max(size[0], size[2]) < 1.5:
        return
    along_x = size[0] >= size[2]
    for sign in (-1.0, 1.0):
        offset = sign * (max(size[0], size[2]) * 0.5 - 0.08)
        px = centre[0] + (offset if along_x else 0.0)
        pz = centre[2] + (0.0 if along_x else offset)
        _slab(trim, (px - 0.10, low[1], pz - 0.10), (px + 0.10, high[1], pz + 0.10))
    if high[1] - low[1] > 0.2:
        _slab(lamp, (low[0], centre[1] - 0.05, low[2] - 0.03),
              (high[0], centre[1] + 0.05, high[2] + 0.03))


def _prop_stall_canopy(body, glass, trim, rubber, lamp, low, high, size, centre):
    """A pitched roof over the canopy slab, with a hanging valance."""
    if size[0] < 1.2 or size[2] < 1.2 or size[1] > 0.6:
        return
    over = 0.35
    eave_y = high[1]
    ridge_y = high[1] + 0.52
    _slab(body, (low[0] - over, eave_y, centre[2] - 0.06),
          (high[0] + over, ridge_y, centre[2] + 0.06))
    for sign_z in (-1.0, 1.0):
        _slab(body, (low[0] - over, eave_y, centre[2] + sign_z * 0.06),
              (high[0] + over, ridge_y, high[2] + sign_z * over))
        _slab(trim, (low[0] - over, eave_y - 0.30, high[2] + sign_z * over),
              (high[0] + over, eave_y, high[2] + sign_z * over))






def _dish(mesh, centre, radius, depth):
    """A shallow reflector dome opening away from `centre`."""
    segments = 18
    rings = 4
    cx, cy, cz = centre
    for ring in range(rings):
        t0 = ring / rings
        t1 = (ring + 1) / rings
        r0 = radius * t0
        r1 = radius * t1
        y0 = cy - depth * radius * (1.0 - t0 * t0)
        y1 = cy - depth * radius * (1.0 - t1 * t1)
        for i in range(segments):
            a0 = TAU * i / segments
            a1 = TAU * (i + 1) / segments
            p0 = (cx + r0 * math.cos(a0), y0, cz + r0 * math.sin(a0))
            p1 = (cx + r0 * math.cos(a1), y0, cz + r0 * math.sin(a1))
            p2 = (cx + r1 * math.cos(a1), y1, cz + r1 * math.sin(a1))
            p3 = (cx + r1 * math.cos(a0), y1, cz + r1 * math.sin(a0))
            mesh.quad(p0, p1, p2, p3)


def _bar(mesh, start, end, thickness):
    """A square-section member between two arbitrary points."""
    dx, dy, dz = end[0] - start[0], end[1] - start[1], end[2] - start[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-5:
        return
    ux, uy, uz = dx / length, dy / length, dz / length
    # Any two axes perpendicular to the run give a square section.
    ax, ay, az = (0.0, 0.0, 1.0) if abs(uz) < 0.9 else (1.0, 0.0, 0.0)
    sx = uy * az - uz * ay
    sy = uz * ax - ux * az
    sz = ux * ay - uy * ax
    slen = math.sqrt(sx * sx + sy * sy + sz * sz) or 1.0
    sx, sy, sz = sx / slen, sy / slen, sz / slen
    tx = sy * uz - sz * uy
    ty = sz * ux - sx * uz
    tz = sx * uy - sy * ux
    half = thickness * 0.5
    corners_low = []
    corners_high = []
    for sign_s in (-1.0, 1.0):
        for sign_t in (-1.0, 1.0):
            ox = sx * half * sign_s + tx * half * sign_t
            oy = sy * half * sign_s + ty * half * sign_t
            oz = sz * half * sign_s + tz * half * sign_t
            corners_low.append((start[0] + ox, start[1] + oy, start[2] + oz))
            corners_high.append((end[0] + ox, end[1] + oy, end[2] + oz))
    a0, a1, a2, a3 = corners_low
    b0, b1, b2, b3 = corners_high
    mesh.quad(a0, a1, b1, b0)
    mesh.quad(a2, a3, b3, b2)
    mesh.quad(a1, a3, b3, b1)
    mesh.quad(a0, a2, b2, b0)
    mesh.quad(a2, a0, a1, a3)
    mesh.quad(b0, b1, b3, b2)


PROP_RULES = {
    "car": [_prop_car],
    "crane": [_prop_crane],
    # A stall is authored as four posts plus a canopy slab, which the two rules
    # below distinguish by proportions.
    "stall": [_prop_stall, _prop_stall_canopy],
    "radar": [_prop_radar],
    "barrier": [_prop_barrier],
}


def _arch(mesh, centre, radius, sign_z, depth):
    """A wheel arch: a shallow shell over the authored wheel."""
    segments = 12
    cx, cy, cz = centre
    thickness = 0.05
    for index in range(segments):
        a0 = math.pi * (index / segments)
        a1 = math.pi * ((index + 1) / segments)
        inner = radius * 0.94
        outer = radius + thickness
        p0 = (cx + inner * math.cos(a0), cy + inner * math.sin(a0), cz + sign_z * depth * 0.5)
        p1 = (cx + inner * math.cos(a1), cy + inner * math.sin(a1), cz + sign_z * depth * 0.5)
        p2 = (cx + outer * math.cos(a1), cy + outer * math.sin(a1), cz + sign_z * (depth * 0.5 + 0.06))
        p3 = (cx + outer * math.cos(a0), cy + outer * math.sin(a0), cz + sign_z * (depth * 0.5 + 0.06))
        mesh.quad(p0, p1, p2, p3)



def _facade_detail(kind, low, high, frame_mesh, glass_mesh, door_mesh, trim_mesh):
    """Window and door frames on all four facades of one building.

    Every member is described as an axis-aligned slab spanning two corners, so a
    jamb really is vertical and a head really is horizontal. Describing them as a
    single run between `(x, sill, z)` and `(x, top, z)` instead collapses the run
    to the diagonal between those two points, which is what produced diagonal
    window panes.
    """
    height = high[1] - low[1]
    if height < 2.0:
        return
    sill = low[1] + min(1.15, height * 0.45)
    window_height = 1.05
    window_width = 0.95
    frame = 0.10
    recess = 0.06

    # One door per building, centred on the low-Z facade.
    door_width, door_height = 1.10, 2.15
    door_bottom = max(low[1], high[1] - door_height)
    door_centre = (low[0] + high[0]) * 0.5
    z_face = low[2]
    _slab(door_mesh, (door_centre - door_width * 0.5, door_bottom, z_face - recess - 0.01),
          (door_centre + door_width * 0.5, high[1], z_face))
    _slab(frame_mesh, (door_centre - door_width * 0.5 - frame, door_bottom, z_face - recess - 0.03),
          (door_centre - door_width * 0.5, high[1] + frame, z_face))
    _slab(frame_mesh, (door_centre + door_width * 0.5, door_bottom, z_face - recess - 0.03),
          (door_centre + door_width * 0.5 + frame, high[1] + frame, z_face))
    _slab(frame_mesh, (door_centre - door_width * 0.5 - frame, high[1], z_face - recess - 0.03),
          (door_centre + door_width * 0.5 + frame, high[1] + frame, z_face))

    # Every window opening, described once and mirrored onto all four facades.
    openings = []
    for axis, face, normal, span_low, span_high in (
            (0, low[2], -1.0, low[0], high[0]),
            (0, high[2], 1.0, low[0], high[0]),
            (2, low[0], -1.0, low[2], high[2]),
            (2, high[0], 1.0, low[2], high[2])):
        span = span_high - span_low
        if span < 2.2:
            continue
        count = max(1, min(4, int(span // 2.4)))
        step = span / (count + 1)
        for index in range(count):
            centre = span_low + step * (index + 1)
            a = centre - window_width * 0.5
            b = centre + window_width * 0.5
            openings.append((axis, face, normal, a, b))

    for axis, face, normal, a, b in openings:
        top = sill + window_height
        outward = normal * (recess + 0.01)
        # Glass: inset into the wall, one flat pane.
        if axis == 0:
            _slab(glass_mesh, (a, sill, face + outward - normal * 0.02),
                  (b, top, face + outward))
        else:
            _slab(glass_mesh, (face + outward - normal * 0.02, sill, a),
                  (face + outward, top, b))
        # Frames sit slightly proud of the glass.
        proud = normal * (recess + 0.03)
        if axis == 0:
            _slab(frame_mesh, (a - frame, sill, face + proud - normal * 0.03), (a, top + frame, face + proud))
            _slab(frame_mesh, (b, sill, face + proud - normal * 0.03), (b + frame, top + frame, face + proud))
            _slab(frame_mesh, (a - frame, sill - frame, face + proud - normal * 0.03), (b + frame, sill, face + proud))
            _slab(frame_mesh, (a - frame, top, face + proud - normal * 0.03), (b + frame, top + frame, face + proud))
            _slab(frame_mesh, (a, sill + window_height * 0.5 - 0.03, face + proud - normal * 0.02),
                  (b, sill + window_height * 0.5 + 0.03, face + proud))
        else:
            _slab(frame_mesh, (face + proud - normal * 0.03, sill, a - frame), (face + proud, top + frame, a))
            _slab(frame_mesh, (face + proud - normal * 0.03, sill, b), (face + proud, top + frame, b + frame))
            _slab(frame_mesh, (face + proud - normal * 0.03, sill - frame, a - frame), (face + proud, sill, b + frame))
            _slab(frame_mesh, (face + proud - normal * 0.03, top, a - frame), (face + proud, top + frame, b + frame))
            _slab(frame_mesh, (face + proud - normal * 0.02, sill + window_height * 0.5 - 0.03, a),
                  (face + proud, sill + window_height * 0.5 + 0.03, b))

    # A drip line where the wall meets the parapet, and a downpipe at one corner.
    for z_face, normal in ((low[2] - 0.05, -1.0), (high[2] + 0.05, 1.0)):
        _slab(trim_mesh, (low[0] - 0.06, high[1] - 0.24, z_face - 0.03 * normal),
              (high[0] + 0.06, high[1] - 0.14, z_face))
    _slab(trim_mesh, (low[0] - 0.09, low[1], low[2] - 0.09),
          (low[0] - 0.02, high[1] - 0.25, low[2] - 0.02))

    del kind


def _slab(mesh, low, high):
    """Axis-aligned box between two corners, skipping degenerate extents."""
    if high[0] - low[0] <= 1e-6 or high[1] - low[1] <= 1e-6 or high[2] - low[2] <= 1e-6:
        return
    add_box(mesh, low, high)


def main():
    for map_id in ("desert_town", "forest_facility", "urban_docks"):
        enrich(map_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
