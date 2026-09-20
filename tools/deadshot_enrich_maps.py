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
clustered into buildings by shared corner vertices, and each building gains the
structure the blockout omits —

  * a masonry envelope: parapet band with coping stones and a drip groove, a
    dentilled cornice under the parapet, a banding course at every storey line,
    corner quoins, and a plinth with a base step and a splayed top;
  * openings on all four facades: doors (multiple on the long facades), windows
    with architraves, reveals deep enough to throw a shadow, sills with a drip
    edge, shutters, lintels, and loading-bay roller shutters on the docks and the
    facility;
  * a roofscape: vent stacks, a condenser with a fan grille, a water tank on
    legs, a hatch on a curb, pipe runs with elbows and brackets, a lightning rod
    and a parapet railing on stanchions — the silhouettes read from inside the
    arena;
  * a paved apron with a kerb ring, kerb returns, drainage gratings, utility
    covers, bollards, a retaining edge with a coping and painted markings, plus a
    patrol road and its own kerbs, centre line, stop bars and hazard chevrons
    around the perimeter;
  * landmark detail on slender structures (the minaret), and container
    corrugation on the docks' lanes.

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
    # A coping stone is dressed stone, not the rendered plaster of the wall
    # beneath it: a colder tone with the quarry grain of the `stone` family.
    "ds_map_coping": {"color": [0.36, 0.35, 0.33], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "stone", "minLuminance": 0.14, "maxLuminance": 0.44,
                      "dust": 0.20, "grime": 0.22, "roughness": 0.84, "tiling": 1.6},
    # Road paint is its own family because it has to read as a flat film laid on
    # asphalt: high albedo, no dust, and a specular that survives the wear.
    "ds_map_paint": {"color": [0.72, 0.70, 0.62], "emissive": [0, 0, 0], "opacity": 1,
                     "transparent": False, "doubleSide": False, "unlit": False,
                     "outline": False, "thickness": 0, "depthTest": True,
                     "surface": "concrete", "minLuminance": 0.34, "maxLuminance": 0.86,
                     "dust": 0.06, "grime": 0.10, "roughness": 0.66, "tiling": 2.2},
    # Railing, stanchions, gratings, covers and cast-iron pipework: bare,
    # slightly corroded iron rather than the galvanised trim of the frames.
    "ds_map_rail": {"color": [0.15, 0.155, 0.16], "emissive": [0, 0, 0], "opacity": 1,
                    "transparent": False, "doubleSide": False, "unlit": False,
                    "outline": False, "thickness": 0, "depthTest": True,
                    "surface": "metal", "minLuminance": 0.13, "maxLuminance": 0.30,
                    "dust": 0.18, "grime": 0.34, "roughness": 0.56, "metallic": 0.8,
                    "tiling": 2.0},
    # Stall fabric and tarpaulins: dyed cloth, so a separate family keeps the
    # weave and the desaturated pigment out of the plaster band.
    "ds_map_canvas": {"color": [0.44, 0.30, 0.21], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "fabric", "minLuminance": 0.12, "maxLuminance": 0.38,
                      "dust": 0.14, "grime": 0.18, "roughness": 0.93, "tiling": 2.6},
    # Roof plant is weathered metal with rust weeping from every fixing, which is
    # what a condenser, a vent cowl and a tank jacket actually look like.
    "ds_map_roof": {"color": [0.26, 0.245, 0.225], "emissive": [0, 0, 0], "opacity": 1,
                    "transparent": False, "doubleSide": False, "unlit": False,
                    "outline": False, "thickness": 0, "depthTest": True,
                    "surface": "rust", "minLuminance": 0.12, "maxLuminance": 0.32,
                    "dust": 0.22, "grime": 0.34, "roughness": 0.72, "metallic": 0.25,
                    "tiling": 1.3},
    # The laid apron and the road band are asphalt: a separate family from the
    # wall stone so the joints and the tyre polish land on the ground only.
    "ds_map_paving": {"color": [0.19, 0.19, 0.185], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "asphalt", "minLuminance": 0.10, "maxLuminance": 0.26,
                      "dust": 0.16, "grime": 0.20, "roughness": 0.90, "tiling": 0.9},
    # Kerbs and the retaining wall are cast concrete: brighter and colder than
    # asphalt, which is what separates the edge from the surface it bounds.
    "ds_map_kerb": {"color": [0.42, 0.415, 0.40], "emissive": [0, 0, 0], "opacity": 1,
                    "transparent": False, "doubleSide": False, "unlit": False,
                    "outline": False, "thickness": 0, "depthTest": True,
                    "surface": "concrete", "minLuminance": 0.20, "maxLuminance": 0.56,
                    "dust": 0.20, "grime": 0.26, "roughness": 0.86, "tiling": 1.4},
    # A shipping container's corner castings are bare, weathered steel: darker
    # and rougher than the painted shell, so the castings read as separate blocks
    # at distance instead of merging into the box.
    "ds_map_container": {"color": [0.20, 0.175, 0.150], "emissive": [0, 0, 0], "opacity": 1,
                         "transparent": False, "doubleSide": False, "unlit": False,
                         "outline": False, "thickness": 0, "depthTest": True,
                         "surface": "rust", "minLuminance": 0.11, "maxLuminance": 0.30,
                         "dust": 0.24, "grime": 0.40, "roughness": 0.78, "metallic": 0.4,
                         "tiling": 1.8},
    # Trunks and branches are bark, not the toon foliage material the authored
    # canopy carries, so they get their own family and keep a woody grain.
    "ds_map_bark": {"color": [0.24, 0.19, 0.15], "emissive": [0, 0, 0], "opacity": 1,
                    "transparent": False, "doubleSide": False, "unlit": False,
                    "outline": False, "thickness": 0, "depthTest": True,
                    "surface": "wood", "minLuminance": 0.10, "maxLuminance": 0.28,
                    "dust": 0.18, "grime": 0.26, "roughness": 0.88, "tiling": 2.2},
    # The canopy lobes are leaf mass, so they take the foliage family — which the
    # surface shader now gives leaf-lobe relief, backlight transmission and
    # two-sided shading — at a mid-green taken from the authored canopies' own
    # colours (0.05-0.08 red, 0.20-0.28 green, 0.04-0.06 blue), not the bark tone.
    # Wind is deliberately left off: the sway is ramped by `VERTEX.y` in model
    # space, and these detail nodes carry an identity matrix, so a wind strength
    # here would displace the canopy by absolute world height while the trunk it
    # sits on stayed still.
    "ds_map_canopy": {"color": [0.09, 0.24, 0.07], "emissive": [0, 0, 0], "opacity": 1,
                      "transparent": False, "doubleSide": False, "unlit": False,
                      "outline": False, "thickness": 0, "depthTest": True,
                      "surface": "foliage", "minLuminance": 0.12, "maxLuminance": 0.30,
                      "dust": 0.08, "grime": 0.06, "roughness": 0.92, "specular": 0.28,
                      "tiling": 1.8},
}

# Authored node names that are structural shells worth detailing. Props, cars,
# trees and terrain keep exactly the shapes the original export gave them.
STRUCTURE_NAMES = ("building", "mosque", "stall", "pier", "dock", "container")

# The dock lanes author their containers as plain boxes under the map's own
# node name, not under a `container` name, so the family is named explicitly.
# Their section is about 2.6 m square and about 6 m long.
CONTAINER_NAMES = ("UrbanDocks",)
CONTAINER_MIN_SIDE = 1.6
CONTAINER_MIN_LENGTH = 4.0
CONTAINER_MAX_LENGTH = 14.0
# A corner casting is a 0.20 m cube on a real container.
CONTAINER_CASTING = 0.20

# Trees are authored as instanced parts under `trees_N` (and the facility's
# understory under `grass_N`). A part narrower than this across is the trunk;
# anything wider is the canopy volume.
TREE_PREFIXES = ("trees_",)
TRUNK_SPAN = 0.80

# Canopy lobe placement, as fractions of the authored canopy's local half-extent.
# Solved against the real authored canopy vertices of all three maps and checked
# against the whole canopy volume, not guessed. My first attempt (7 face lobes at
# 0.22/0.95 plus 8 corner lobes at 0.44/1.00) reached 0.906 of the lobe radius on
# the facility's box-like canopy while the faceted mesh falls ~6% short of its
# analytic surface, so the two errors together exposed the authored box in a
# render — which is the bug this replaced.
#
# Eight lobes, one just inside each corner of the authored AABB, is both the
# tightest and the cheapest layout: the corners are what a box exposes, and a lobe
# near each corner covers the faces between corners as well. Measured analytically
# (never through rasterised triangles, because overlapping lobes make a
# crossing-count even and would read a covered point as uncovered):
#
#   * the whole authored canopy VOLUME, as a 121^3 grid of 1 771 561 points over
#     the AABB, is inside the union with worst normalised distance 0.849;
#   * so is every authored canopy vertex in each part's own local frame —
#     0.821 desert (672 points), 0.849 facility (1 974), 0.849 docks (252).
#
# A 12x7 faceted lobe renders at 0.942 of its analytic radius, so a target of 0.85
# leaves ~10% of headroom and the drawn lobes cover, not merely the analytic ones.
# Because the test passes on the entire AABB, both canopy shapes are covered by
# construction: the desert's squashed sphere, the facility's box-like polyhedron
# and the docks' spheres all lie inside that box.
#
# The union reaches 1.52 of the local half-extent on the axes, against the authored
# box's own 1.732 at its corners, so the tree grows by about 15% of the half-extent
# — roughly 25 cm on a 3.4 m canopy. Covering flat-sided canopies needs lobes large
# enough to bridge their faces, and that is the honest cost of hiding them.
CANOPY_LOBES_OFFSET = 0.50
CANOPY_LOBES_RADIUS = 1.02
CANOPY_LOBES_SEGMENTS = 12
CANOPY_LOBES_RINGS = 7
CANOPY_LOBES = 8
# Beyond this the corner lobes are not needed and the part is a trunk, not a
# canopy; below it a lobe would be too small to matter.
CANOPY_MIN_HALF_EXTENT = 0.15

# Wall panels are boxes 0.2-0.4 m thick, and a building's walls meet at the same
# footprint corner rather than at identical vertices: a 12 m south wall spans the
# full footprint while the 9 m east wall is centred on the same corner, so their
# extreme vertices differ by up to half a panel thickness. Snapping to a coarse
# cell and searching the neighbouring cells merges them without merging distinct
# structures, which in these blockouts stand metres apart.
CLUSTER_CELL = 0.5

# Openings and envelope features are chosen from the map, because what a facade
# carries is what the place is: a desert street has shutters against the sun, a
# facility has steel lintels and roller shutters, a dock shed has loading bays.
# The kind also picks the palette, so one script serves three arenas.
MAP_KIND = {
    "desert_town": "desert",
    "forest_facility": "forest",
    "urban_docks": "docks",
}

# Maps whose ground carries a laid apron and a perimeter patrol road, with the
# terrain's own slope sampled so the paving follows it. The desert and the docks
# are flat quarries; the facility is a generated heightfield.
PAVED_MAPS = ("urban_docks", "desert_town")

# Ground geometry. The apron is the paved working surface at the centre of the
# arena; the patrol road is the band beyond it, and both are laid as slabs with
# real joints so the paving catches the light the way a yard does.
KERB_HEIGHT = 0.14
APRON_HALF_X = 24.0
APRON_HALF_Z = 30.0
PAVER = 3.0
ROAD_WIDTH = 7.0
ROAD_OUTER_X = APRON_HALF_X + ROAD_WIDTH
ROAD_OUTER_Z = APRON_HALF_Z + ROAD_WIDTH

# A banding course and a row of window heads mark one storey.
STOREY_HEIGHT = 3.10

# What each arena's openings are like: a desert street is shuttered against the
# sun, the facility is steel and riveted, the docks are concrete with loading
# bays. The pitch is the bay spacing along a facade.
OPENINGS = {
    "desert": {"pitch": 2.45, "width": 0.92, "height": 1.12, "sill": 1.05,
               "lintel": "door", "shutter": True, "storey": 3.05},
    "forest": {"pitch": 2.80, "width": 1.05, "height": 1.28, "sill": 1.10,
               "lintel": "trim", "shutter": False, "storey": 3.10},
    "docks": {"pitch": 3.30, "width": 1.30, "height": 1.55, "sill": 1.35,
              "lintel": "coping", "shutter": False, "storey": 3.60},
}

# Which arenas carry roller shutters, and on which kinds of structure.
ROLLER_SHUTTER_KINDS = ("forest", "docks")

TAU = math.tau
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
    # Corners are normalised so a caller can pass either corner first. Several
    # call sites derive a second corner as `fixed + reach * sign`; when `sign` is
    # negative that puts `high` below `low`, which would invert the box's winding
    # and leave every face pointing inward.
    x0, x1 = (low[0], high[0]) if low[0] <= high[0] else (high[0], low[0])
    y0, y1 = (low[1], high[1]) if low[1] <= high[1] else (high[1], low[1])
    z0, z1 = (low[2], high[2]) if low[2] <= high[2] else (high[2], low[2])
    p = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    face(mesh, p[0], p[3], p[2], p[1])       # -Z
    face(mesh, p[4], p[5], p[6], p[7])       # +Z
    face(mesh, p[1], p[2], p[6], p[5])       # +X
    face(mesh, p[3], p[0], p[4], p[7])       # -X
    face(mesh, p[2], p[3], p[7], p[6])       # +Y
    if not skip_bottom:
        face(mesh, p[0], p[1], p[5], p[4])   # -Y


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
    face(mesh, a0, a1, b1, b0)   # side
    face(mesh, a2, a3, b3, b2)   # side
    face(mesh, a1, a3, b3, b1)   # outer face
    face(mesh, a0, a2, b2, b0)   # inner face
    face(mesh, a2, a0, a1, a3)   # start cap
    face(mesh, b0, b1, b3, b2)   # end cap


def face(mesh, a, b, c, d=None):
    """Emits one face from its corners listed **counter-clockwise seen outside**.

    `deadshot_detail.Mesh` stores `base, base + 2, base + 1`, so handing it a
    counter-clockwise face stores the two triangles *reversed*, and
    `MapWorld._make_mesh` then reverses them again for Godot. The authored
    blockout stores clockwise-from-outside for exactly that reason — measured on
    its own walls, every stored face's normal points away from the building — so
    every primitive below emits through here and the reversal happens once.
    """
    if d is None:
        mesh.triangle(c, b, a)
        return
    mesh.quad(d, c, b, a)


def solid(mesh, low, high, cap=True):
    """Closes two rings of matching corners into a solid, faces pointing out.

    Both rings MUST run the same way round — counter-clockwise seen from the
    direction `high` lies along, which is towards +axis. The low cap therefore
    has to be reversed, because it faces the other way.
    """
    count = len(low)
    for index in range(count):
        follow = (index + 1) % count
        face(mesh, low[index], low[follow], high[follow], high[index])
    if not cap or count < 3:
        return
    for index in range(1, count - 1):
        face(mesh, low[0], low[index + 1], low[index])
    for index in range(1, count - 1):
        face(mesh, high[0], high[index], high[index + 1])


def cylinder(mesh, centre, axis, radius, length, segments=12, radius_end=None):
    """A capped cylinder about a world axis."""
    cx, cy, cz = centre
    half = length * 0.5
    r1 = radius if radius_end is None else radius_end

    def ring(r, along, angle):
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        if axis == 1:
            # Counter-clockwise seen from +Y, whose 2D frame is (X, -Z).
            return (cx + r * cos_a, cy + along, cz - r * sin_a)
        if axis == 0:
            return (cx + along, cy + r * cos_a, cz + r * sin_a)
        return (cx + r * cos_a, cy + r * sin_a, cz + along)

    low = []
    high = []
    for index in range(segments):
        angle = TAU * index / segments
        low.append(ring(radius, -half, angle))
        high.append(ring(r1, half, angle))
    solid(mesh, low, high)


def floor_quad(mesh, x0, z0, x1, z1, y_x0z0, y_x1z0, y_x1z1, y_x0z1):
    """An upward-facing quad over an XZ cell, each corner carrying its own Y.

    The corner order matches the top face `add_box` emits, so a paved cell, a
    kerb top and a box lid are all wound the same way and lie the same way up.
    """
    face(mesh, (x1, y_x1z0, z0), (x0, y_x0z0, z0), (x0, y_x0z1, z1), (x1, y_x1z1, z1))


def ring_quad(mesh, centre, radius, half_width, segments, rise=0.0, depth=0.0):
    """An annulus, for drum tops, hatch rims and the lip of a coping."""
    cx, cy, cz = centre
    for index in range(segments):
        a0 = TAU * index / segments
        a1 = TAU * (index + 1) / segments
        inner = radius - half_width
        for r0, r1 in ((inner, radius),):
            for low, high in ((cy, cy + rise),):
                p0 = (cx + r0 * math.cos(a0), high, cz + r0 * math.sin(a0))
                p1 = (cx + r0 * math.cos(a1), high, cz + r0 * math.sin(a1))
                p2 = (cx + r1 * math.cos(a1), high, cz + r1 * math.sin(a1))
                p3 = (cx + r1 * math.cos(a0), high, cz + r1 * math.sin(a0))
                del low
                if depth:
                    pass
                face(mesh, p3, p2, p1, p0)
    del depth


def tube(mesh, start, end, radius, segments=12, radius_end=None):
    """A cylinder between two arbitrary points, with both caps."""
    dx, dy, dz = end[0] - start[0], end[1] - start[1], end[2] - start[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-5:
        return
    r1 = radius if radius_end is None else radius_end
    w = (dx / length, dy / length, dz / length)
    reference = (0.0, 0.0, 1.0) if abs(w[2]) < 0.9 else (1.0, 0.0, 0.0)
    side = (reference[1] * w[2] - reference[2] * w[1],
            reference[2] * w[0] - reference[0] * w[2],
            reference[0] * w[1] - reference[1] * w[0])
    scale = math.sqrt(side[0] ** 2 + side[1] ** 2 + side[2] ** 2)
    u = (side[0] / scale, side[1] / scale, side[2] / scale)
    v = (w[1] * u[2] - w[2] * u[1], w[2] * u[0] - w[0] * u[2], w[0] * u[1] - w[1] * u[0])
    low = []
    high = []
    for index in range(segments):
        angle = TAU * index / segments
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for target, origin, r in ((low, start, radius), (high, end, r1)):
            target.append((
                origin[0] + r * (u[0] * cos_a + v[0] * sin_a),
                origin[1] + r * (u[1] * cos_a + v[1] * sin_a),
                origin[2] + r * (u[2] * cos_a + v[2] * sin_a),
            ))
    solid(mesh, low, high)


def hook(mesh, centre, radius, tube_radius, arc=0.5, segments=8, axis=1,
         round_segments=6):
    """A bent half-round section about `axis`: a pipe hook or a canopy rib."""
    path = []
    span = TAU * arc
    for index in range(segments + 1):
        angle = -span * 0.5 + span * index / segments
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        if axis == 1:
            path.append((centre[0] + radius * cos_a, centre[1], centre[2] + radius * sin_a))
        elif axis == 0:
            path.append((centre[0], centre[1] + radius * cos_a, centre[2] + radius * sin_a))
        else:
            path.append((centre[0] + radius * cos_a, centre[1] + radius * sin_a, centre[2]))
    for index in range(segments):
        tube(mesh, path[index], path[index + 1], tube_radius, round_segments)


def gable_prism(mesh, low, high, ridge_y, along_x):
    """A two-slope roof over a rectangular plan, gable ends closed.

    `along_x` runs the ridge along X, so the two slopes fall toward Z.
    """
    x0, y0, z0 = low
    x1, _, z1 = high
    a = (x0, y0, z0)
    b = (x1, y0, z0)
    c = (x1, y0, z1)
    d = (x0, y0, z1)
    if along_x:
        mid = (z0 + z1) * 0.5
        r0 = (x0, ridge_y, mid)
        r1 = (x1, ridge_y, mid)
        face(mesh, a, r0, r1, b)            # slope falling to -Z
        face(mesh, c, r1, r0, d)            # slope falling to +Z
        face(mesh, a, d, r0)                # gable at -X
        face(mesh, c, b, r1)                # gable at +X
    else:
        mid = (x0 + x1) * 0.5
        r0 = (mid, ridge_y, z0)
        r1 = (mid, ridge_y, z1)
        face(mesh, b, r0, r1, c)            # slope falling to +X
        face(mesh, a, d, r1, r0)            # slope falling to -X
        face(mesh, a, r0, b)                # gable at -Z
        face(mesh, d, c, r1)                # gable at +Z


# --------------------------------------------------------------------------
# Facade envelope. A blockout wall is a bare quad; these are the courses,
# copings, quoins and mouldings that make it read as masonry, all expressed as
# real world-space members standing proud of the panel.
# --------------------------------------------------------------------------

def _storey_courses(low, high, kind, band_mesh, trim_mesh):
    """A banding course at every storey line, with a drip and a weathering top.

    A course is raised off the wall on all four faces and given a thin lip under
    it and a capping over it, so it throws two lines of shadow along the facade
    rather than reading as a painted stripe.
    """
    storey = OPENINGS[kind]["storey"]
    height = high[1] - low[1]
    floors = max(0, int(height // storey) - 1)
    proud = 0.075
    for floor in range(1, floors + 1):
        y = low[1] + storey * floor
        if y > high[1] - 0.95:
            break
        add_box(band_mesh, (low[0] - proud, y - 0.09, low[2] - proud),
                (high[0] + proud, y + 0.09, high[2] + proud))
        add_box(trim_mesh, (low[0] - proud - 0.03, y - 0.145, low[2] - proud - 0.03),
                (high[0] + proud + 0.03, y - 0.09, high[2] + proud + 0.03))
        add_box(trim_mesh, (low[0] - proud - 0.02, y + 0.09, low[2] - proud - 0.02),
                (high[0] + proud + 0.02, y + 0.13, high[2] + proud + 0.02))



def _cornice(low, high, kind, trim_mesh, coping_mesh):
    """A moulded cornice under the parapet: bed, cove and a run of dentils.

    The blockout wall ends flush at the parapet. A cornice steps the top of the
    facade out over three courses and then blocks the underside out with dentils,
    which is the one feature that makes the roofline read at any distance.
    """
    reach = 0.30
    top = high[1]
    add_box(trim_mesh, (low[0] - reach, top - 0.62, low[2] - reach),
            (high[0] + reach, top - 0.44, high[2] + reach))
    add_box(trim_mesh, (low[0] - reach * 0.62, top - 0.44, low[2] - reach * 0.62),
            (high[0] + reach * 0.62, top - 0.30, high[2] + reach * 0.62))
    add_box(trim_mesh, (low[0] - reach * 0.42, top - 0.30, low[2] - reach * 0.42),
            (high[0] + reach * 0.42, top - 0.18, high[2] + reach * 0.42))
    # Dentils: short blocks standing under the bed mould, evenly spaced.
    for along_x, fixed, span_low, span_high in (
            (True, low[2], low[0], high[0]),
            (True, high[2], low[0], high[0]),
            (False, low[0], low[2], high[2]),
            (False, high[0], low[2], high[2])):
        run = span_high - span_low
        count = int(run // 0.42)
        if count < 2:
            continue
        step = run / count
        for index in range(count):
            centre = span_low + step * (index + 0.5)
            wide = step * 0.26
            if along_x:
                near = fixed - 0.06 if fixed == low[2] else fixed
                far = fixed if fixed == low[2] else fixed + 0.06
                add_box(trim_mesh, (centre - wide, top - 0.62, near),
                        (centre + wide, top - 0.44, far))
            else:
                near = fixed - 0.06 if fixed == low[0] else fixed
                far = fixed if fixed == low[0] else fixed + 0.06
                add_box(trim_mesh, (near, top - 0.62, centre - wide),
                        (far, top - 0.44, centre + wide))
    del kind, coping_mesh



def _parapet(low, high, kind, parapet_mesh, coping_mesh, trim_mesh):
    """The parapet band, its coping stones and the drip grooves beneath them.

    The coping overhangs the band on both faces and is broken into stones with a
    joint between them, so the roof edge reads as a run of blocks rather than as
    one strip; the groove under the overhang is what keeps the wall below it dry.
    """
    band = 0.46
    proud = 0.05
    width = 0.24
    reach = 0.09
    top = high[1]
    faces = (
        (low[0] - proud, high[0] + proud, low[2] - proud, low[2] - proud + width, True),
        (low[0] - proud, high[0] + proud, high[2] + proud - width, high[2] + proud, True),
        (low[0] - proud, low[0] - proud + width, low[2] - proud, high[2] + proud, False),
        (high[0] + proud - width, high[0] + proud, low[2] - proud, high[2] + proud, False),
    )
    for (x0, x1, z0, z1, _) in faces:
        add_box(parapet_mesh, (x0, top, z0), (x1, top + band, z1))
    for (x0, x1, z0, z1, along_x) in faces:
        over_x = 0.0 if along_x else reach
        over_z = reach if along_x else 0.0
        add_box(coping_mesh, (x0 - over_x, top + band, z0 - over_z),
                (x1 + over_x, top + band + 0.14, z1 + over_z))
        add_box(trim_mesh, (x0 - over_x - 0.01, top + band - 0.040, z0 - over_z - 0.01),
                (x1 + over_x + 0.01, top + band - 0.006, z1 + over_z + 0.01))
        run = (x1 - x0) if along_x else (z1 - z0)
        stones = max(2, int(run // 0.74))
        for index in range(stones):
            a = run * index / stones
            b = run * (index + 1) / stones
            gap = min(0.035, (b - a) * 0.12)
            if along_x:
                add_box(coping_mesh, (x0 + a + gap, top + band + 0.13, z0 - reach),
                        (x0 + b - gap, top + band + 0.20, z1 + reach))
            else:
                add_box(coping_mesh, (x0 - reach, top + band + 0.13, z0 + a + gap),
                        (x1 + reach, top + band + 0.20, z0 + b - gap))
    del kind



def _quoins(low, high, kind, trim_mesh):
    """Alternating corner stones up every arris, larger at the base.

    Quoins are how a masonry corner is bonded, and alternating which face each
    course runs long down is what makes the arris read as stonework instead of as
    a painted edge.
    """
    storey = OPENINGS[kind]["storey"]
    height = high[1] - low[1]
    rows = max(2, int(height // (storey / 5.0)))
    step = height / rows
    for on_high_x in (False, True):
        for on_high_z in (False, True):
            x = high[0] if on_high_x else low[0]
            z = high[2] if on_high_z else low[2]
            out_x = 1.0 if on_high_x else -1.0
            out_z = 1.0 if on_high_z else -1.0
            for row in range(rows):
                y0 = low[1] + step * row
                if y0 > high[1] - 0.80:
                    break
                long_along_z = (row % 2 == 0)
                reach_z = 0.46 if long_along_z else 0.26
                reach_x = 0.26 if long_along_z else 0.46
                add_box(trim_mesh,
                        (min(x, x + out_x * reach_x), y0 + 0.02, min(z, z + out_z * reach_z)),
                        (max(x, x + out_x * reach_x), y0 + step - 0.02,
                         max(z, z + out_z * reach_z)))



def _plinth(low, high, kind, plinth_mesh, coping_mesh):
    """A plinth with a base step, a shaft and a chamfered weather capping.

    The wall foot steps out onto a base course, the shaft rises from it, and the
    whole thing is capped with a chamfer so water leaves the base of the wall.
    """
    depth = 0.20
    base_height = 0.26
    shaft = 0.52
    foot = low[1] - 0.12
    add_box(plinth_mesh, (low[0] - depth - 0.10, foot, low[2] - depth - 0.10),
            (high[0] + depth + 0.10, foot + base_height, high[2] + depth + 0.10))
    add_box(plinth_mesh, (low[0] - depth, foot + base_height, low[2] - depth),
            (high[0] + depth, foot + base_height + shaft, high[2] + depth))
    add_box(coping_mesh, (low[0] - depth - 0.07, foot + base_height + shaft, low[2] - depth - 0.07),
            (high[0] + depth + 0.07, foot + base_height + shaft + 0.12, high[2] + depth + 0.07))
    del kind



# --------------------------------------------------------------------------
# Openings: arches, architraves, reveals, sills, shutters and roller shutters.
# --------------------------------------------------------------------------

def _door(low, high, centre, width, height, kind, door_mesh, frame_mesh,
          trim_mesh, glass_mesh, facing="z", side="low"):
    """One doorway: reveal, architrave, threshold, lintel and leaf."""
    height = min(height, high[1] - low[1] - 0.35)
    bottom = low[1]
    top = bottom + height
    reveal = 0.14
    if facing == "z":
        face_z = low[2] if side == "low" else high[2]
        outward = -1.0 if side == "low" else 1.0
        a, b = centre - width * 0.5, centre + width * 0.5
        # The leaf, set back into a real reveal so the opening shades itself.
        add_box(door_mesh, (a, bottom, face_z - reveal * outward if outward > 0 else face_z),
                (b, top, face_z if outward > 0 else face_z + reveal))
        # Jambs and head of the architrave, standing proud of the wall.
        add_box(frame_mesh, (a - 0.13, bottom, face_z), (a, top + 0.13, face_z + 0.085 * outward))
        add_box(frame_mesh, (b, bottom, face_z), (b + 0.13, top + 0.13, face_z + 0.085 * outward))
        add_box(frame_mesh, (a - 0.13, top, face_z), (b + 0.13, top + 0.13, face_z + 0.085 * outward))
        if kind == "desert":
            _arched_head(low, high, centre, width, top, frame_mesh, door_mesh, facing, side)
        # Threshold and a drip over the head.
        add_box(trim_mesh, (a - 0.16, bottom, face_z - 0.02 * outward),
                (b + 0.16, bottom + 0.05, face_z + 0.10 * outward))
        add_box(trim_mesh, (a - 0.16, top + 0.13, face_z), (b + 0.16, top + 0.17, face_z + 0.12 * outward))
        # A transom light over the leaf.
        add_box(glass_mesh, (a + 0.10, top - 0.34, face_z - 0.01 * outward),
                (b - 0.10, top - 0.10, face_z + 0.03 * outward))
        del kind
        return
    face_x = low[0] if side == "low" else high[0]
    outward = -1.0 if side == "low" else 1.0
    a, b = centre - width * 0.5, centre + width * 0.5
    add_box(door_mesh, (face_x, bottom, a), (face_x + reveal, top, b))
    add_box(frame_mesh, (face_x, bottom, a - 0.13), (face_x + 0.085 * outward, top + 0.13, a))
    add_box(frame_mesh, (face_x, bottom, b), (face_x + 0.085 * outward, top + 0.13, b + 0.13))
    add_box(frame_mesh, (face_x, top, a - 0.13), (face_x + 0.085 * outward, top + 0.13, b + 0.13))
    if kind == "desert":
        _arched_head(low, high, centre, width, top, frame_mesh, door_mesh, facing, side)
    add_box(trim_mesh, (face_x - 0.02 * outward, bottom, a - 0.16),
            (face_x + 0.10 * outward, bottom + 0.05, b + 0.16))
    add_box(trim_mesh, (face_x, top + 0.13, a - 0.16), (face_x + 0.12 * outward, top + 0.17, b + 0.16))
    add_box(glass_mesh, (face_x - 0.01 * outward, top - 0.34, a + 0.10),
            (face_x + 0.03 * outward, top - 0.10, b - 0.10))
    del kind


def _arched_head(low, high, centre, width, spring_y, frame_mesh, trim_mesh, facing, side):
    """A round-headed head over a doorway, with voussoirs and a keystone.

    A flat lintel over a two-metre opening in stone is wrong; a desert doorway
    carries a half-round arch. The ring is laid as individual voussoirs, each a
    small block on the radius, with a keyed stone at the crown.
    """
    radius = width * 0.56
    segments = 7
    if facing == "z":
        face_z = low[2] if side == "low" else high[2]
        outward = -1.0 if side == "low" else 1.0
        for index in range(segments):
            angle = math.pi * (index + 0.5) / segments
            bx = centre + radius * math.cos(angle)
            by = spring_y + radius * math.sin(angle)
            wide = math.pi * radius / segments * 0.92
            add_box(frame_mesh, (bx - wide * 0.5, by - 0.09, face_z),
                    (bx + wide * 0.5, by + 0.09, face_z + 0.09 * outward))
            add_box(trim_mesh, (bx - wide * 0.42, by - 0.055, face_z + 0.09 * outward),
                    (bx + wide * 0.42, by + 0.055, face_z + 0.15 * outward))
        # The keystone at the crown, taller than the rest.
        add_box(frame_mesh, (centre - 0.10, spring_y + radius - 0.06, face_z),
                (centre + 0.10, spring_y + radius + 0.26, face_z + 0.11 * outward))
        return
    face_x = low[0] if side == "low" else high[0]
    outward = -1.0 if side == "low" else 1.0
    for index in range(segments):
        angle = math.pi * (index + 0.5) / segments
        bz = centre + radius * math.cos(angle)
        by = spring_y + radius * math.sin(angle)
        wide = math.pi * radius / segments * 0.92
        add_box(frame_mesh, (face_x, by - 0.09, bz - wide * 0.5),
                (face_x + 0.09 * outward, by + 0.09, bz + wide * 0.5))
        add_box(trim_mesh, (face_x + 0.09 * outward, by - 0.055, bz - wide * 0.42),
                (face_x + 0.15 * outward, by + 0.055, bz + wide * 0.42))
    add_box(frame_mesh, (face_x, spring_y + radius - 0.06, centre - 0.10),
            (face_x + 0.11 * outward, spring_y + radius + 0.26, centre + 0.10))


def _window(low, high, centre, sill, config, kind, opening_mesh, glass_mesh,
            frame_mesh, shutter_mesh, trim_mesh, facing="z", side="low"):
    """One window: a recessed reveal, architrave, sill with a drip, and glazing."""
    width = config["width"]
    height = config["height"]
    reveal = 0.15
    top = sill + height
    if facing == "z":
        face_z = low[2] if side == "low" else high[2]
        outward = -1.0 if side == "low" else 1.0
        back = face_z - reveal if outward < 0 else face_z + reveal
        a, b = centre - width * 0.5, centre + width * 0.5
        # A dark recess behind the glazing is what gives the opening its depth.
        add_box(opening_mesh, (a, sill, min(face_z, back)), (b, top, max(face_z, back)))
        add_box(glass_mesh, (a + 0.04, sill + 0.05, back), (b - 0.04, top - 0.05, back - 0.02 * outward))
        add_box(frame_mesh, (a - 0.10, sill, face_z), (a, top + 0.10, face_z + 0.07 * outward))
        add_box(frame_mesh, (b, sill, face_z), (b + 0.10, top + 0.10, face_z + 0.07 * outward))
        add_box(frame_mesh, (a - 0.10, top, face_z), (b + 0.10, top + 0.10, face_z + 0.07 * outward))
        add_box(frame_mesh, (a, sill + height * 0.5 - 0.035, back),
                (b, sill + height * 0.5 + 0.035, back - 0.05 * outward))
        add_box(frame_mesh, (centre - 0.035, sill, back), (centre + 0.035, top, back - 0.05 * outward))
        # Sill, with a drip edge proud of the head of the wall below.
        add_box(trim_mesh, (a - 0.14, sill - 0.09, face_z - 0.02 * outward),
                (b + 0.14, sill, face_z + 0.11 * outward))
        add_box(trim_mesh, (a - 0.10, sill - 0.13, face_z), (b + 0.10, sill - 0.09, face_z + 0.05 * outward))
        if config["shutter"]:
            for sign in (-1.0, 1.0):
                leaf_centre = centre + sign * (width * 0.5 + 0.16)
                add_box(shutter_mesh, (leaf_centre - 0.15, sill, face_z + 0.02 * outward),
                        (leaf_centre + 0.15, top, face_z + 0.08 * outward))
        # A steel or stone lintel over the head, per the arena.
        if config["lintel"] == "trim":
            add_box(trim_mesh, (a - 0.16, top + 0.10, face_z), (b + 0.16, top + 0.20, face_z + 0.12 * outward))
        elif config["lintel"] == "coping":
            add_box(frame_mesh, (a - 0.18, top + 0.10, face_z), (b + 0.18, top + 0.26, face_z + 0.14 * outward))
        else:
            add_box(frame_mesh, (a - 0.14, top + 0.10, face_z), (b + 0.14, top + 0.16, face_z + 0.09 * outward))
        del kind
        return
    face_x = low[0] if side == "low" else high[0]
    outward = -1.0 if side == "low" else 1.0
    back = face_x - reveal if outward < 0 else face_x + reveal
    a, b = centre - width * 0.5, centre + width * 0.5
    add_box(opening_mesh, (min(face_x, back), sill, a), (max(face_x, back), top, b))
    add_box(glass_mesh, (back, sill + 0.05, a + 0.04), (back - 0.02 * outward, top - 0.05, b - 0.04))
    add_box(frame_mesh, (face_x, sill, a - 0.10), (face_x + 0.07 * outward, top + 0.10, a))
    add_box(frame_mesh, (face_x, sill, b), (face_x + 0.07 * outward, top + 0.10, b + 0.10))
    add_box(frame_mesh, (face_x, top, a - 0.10), (face_x + 0.07 * outward, top + 0.10, b + 0.10))
    add_box(frame_mesh, (back, sill + height * 0.5 - 0.035, a), (back - 0.05 * outward, sill + height * 0.5 + 0.035, b))
    add_box(frame_mesh, (back, sill, centre - 0.035), (back - 0.05 * outward, top, centre + 0.035))
    add_box(trim_mesh, (face_x - 0.02 * outward, sill - 0.09, a - 0.14),
            (face_x + 0.11 * outward, sill, b + 0.14))
    add_box(trim_mesh, (face_x, sill - 0.13, a - 0.10), (face_x + 0.05 * outward, sill - 0.09, b + 0.10))
    if config["shutter"]:
        for sign in (-1.0, 1.0):
            leaf_centre = centre + sign * (width * 0.5 + 0.16)
            add_box(shutter_mesh, (face_x + 0.02 * outward, sill, leaf_centre - 0.15),
                    (face_x + 0.08 * outward, top, leaf_centre + 0.15))
    if config["lintel"] == "trim":
        add_box(trim_mesh, (face_x, top + 0.10, a - 0.16), (face_x + 0.12 * outward, top + 0.20, b + 0.16))
    elif config["lintel"] == "coping":
        add_box(frame_mesh, (face_x, top + 0.10, a - 0.18), (face_x + 0.14 * outward, top + 0.26, b + 0.18))
    else:
        add_box(frame_mesh, (face_x, top + 0.10, a - 0.14), (face_x + 0.09 * outward, top + 0.16, b + 0.14))
    del kind


def _roller_shutter(low, high, centre, width, kind, opening_mesh, door_mesh,
                    frame_mesh, trim_mesh, facing="z", side="low"):
    """A loading bay or roller shutter: deep reveal, drum, slats and guides."""
    height = min(2.85, (high[1] - low[1]) * 0.72)
    bottom = low[1]
    drum = 0.30
    if facing == "z":
        face_z = low[2] if side == "low" else high[2]
        outward = -1.0 if side == "low" else 1.0
        a, b = centre - width * 0.5, centre + width * 0.5
        # The deep reveal, then the slatted leaf set back inside it.
        add_box(opening_mesh, (a, bottom, min(face_z, face_z - 0.22 * outward)),
                (b, bottom + height, max(face_z, face_z - 0.22 * outward)))
        slats = max(4, int(height // 0.28))
        for index in range(slats):
            y0 = bottom + height * index / slats
            y1 = bottom + height * (index + 1) / slats
            add_box(door_mesh, (a + 0.03, y0 + 0.015, face_z - 0.21 * outward),
                    (b - 0.03, y1 - 0.015, face_z - 0.14 * outward))
        # Guide rails down both jambs and the drum housing across the head.
        add_box(frame_mesh, (a - 0.09, bottom, face_z), (a + 0.05, bottom + height + drum, face_z + 0.10 * outward))
        add_box(frame_mesh, (b - 0.05, bottom, face_z), (b + 0.09, bottom + height + drum, face_z + 0.10 * outward))
        add_box(frame_mesh, (a - 0.09, bottom + height, face_z), (b + 0.09, bottom + height + drum, face_z + 0.14 * outward))
        add_box(trim_mesh, (a - 0.14, bottom + height + drum, face_z), (b + 0.14, bottom + height + drum + 0.09, face_z + 0.16 * outward))
        # The lintel band the bay is cut through.
        add_box(trim_mesh, (a - 0.20, bottom + height + drum + 0.09, face_z),
                (b + 0.20, bottom + height + drum + 0.24, face_z + 0.12 * outward))
        del kind
        return
    face_x = low[0] if side == "low" else high[0]
    outward = -1.0 if side == "low" else 1.0
    a, b = centre - width * 0.5, centre + width * 0.5
    add_box(opening_mesh, (min(face_x, face_x - 0.22 * outward), bottom, a),
            (max(face_x, face_x - 0.22 * outward), bottom + height, b))
    slats = max(4, int(height // 0.28))
    for index in range(slats):
        y0 = bottom + height * index / slats
        y1 = bottom + height * (index + 1) / slats
        add_box(door_mesh, (face_x - 0.21 * outward, y0 + 0.015, a + 0.03),
                (face_x - 0.14 * outward, y1 - 0.015, b - 0.03))
    add_box(frame_mesh, (face_x, bottom, a - 0.09), (face_x + 0.10 * outward, bottom + height + drum, a + 0.05))
    add_box(frame_mesh, (face_x, bottom, b - 0.05), (face_x + 0.10 * outward, bottom + height + drum, b + 0.09))
    add_box(frame_mesh, (face_x, bottom + height, a - 0.09), (face_x + 0.14 * outward, bottom + height + drum, b + 0.09))
    add_box(trim_mesh, (face_x, bottom + height + drum, a - 0.14), (face_x + 0.16 * outward, bottom + height + drum + 0.09, b + 0.14))
    add_box(trim_mesh, (face_x, bottom + height + drum + 0.09, a - 0.20),
            (face_x + 0.12 * outward, bottom + height + drum + 0.24, b + 0.20))
    del kind


def _facade_openings(low, high, kind, config, meshes):
    """Lays doors, windows and any loading bays across all four facades."""
    opening_mesh, glass_mesh, frame_mesh, door_mesh, shutter_mesh, trim_mesh = meshes
    height = high[1] - low[1]
    if height < 2.0:
        return
    sill = min(config["sill"], max(0.7, height * 0.35))
    if sill + config["height"] > height - 0.55:
        sill = max(0.65, height - config["height"] - 0.65)
    for facing, side, span_low, span_high in (
            ("z", "low", low[0], high[0]),
            ("z", "high", low[0], high[0]),
            ("x", "low", low[2], high[2]),
            ("x", "high", low[2], high[2])):
        span = span_high - span_low
        if span < 2.0:
            continue
        pitch = config["pitch"]
        count = max(1, int(span // pitch))
        step = span / (count + 1)
        long_facade = span >= 6.5
        for index in range(count):
            centre = span_low + step * (index + 1)
            width = min(config["width"], step * 0.62)
            if width < 0.5:
                continue
            _window(low, high, centre, sill, config, kind, opening_mesh, glass_mesh,
                    frame_mesh, shutter_mesh, trim_mesh, facing, side)
        # A door on every facade, and a second on any long one, offset from centre.
        doors = 1
        if long_facade:
            doors = 2
        for index in range(doors):
            offset = 0.0 if doors == 1 else (index * 2.0 - 1.0) * span * 0.30
            _door(low, high, (span_low + span_high) * 0.5 + offset, 1.05, 2.15, kind,
                  door_mesh, frame_mesh, trim_mesh, glass_mesh, facing, side)
        # The docks and the facility cut loading bays through their long walls.
        if kind in ROLLER_SHUTTER_KINDS and span >= 9.0:
            bays = 1 if span < 14.0 else 2
            for index in range(bays):
                offset = (index * 2.0 - 1.0) * span * 0.26 if bays > 1 else 0.0
                _roller_shutter(low, high, (span_low + span_high) * 0.5 + offset, 2.60, kind,
                                opening_mesh, door_mesh, frame_mesh, trim_mesh, facing, side)


# --------------------------------------------------------------------------
# Roofscape. Everything here is what gives a building a silhouette from inside
# the arena: plant, services and edge protection the blockout never had.
# --------------------------------------------------------------------------

def _roof_plant(low, high, kind, index, plant_mesh, trim_mesh, coping_mesh,
                glass_mesh, lamp_mesh):
    """Vent stacks, a condenser, a tank on legs, a hatch, pipework and a rod."""
    top = high[1]
    width = high[0] - low[0]
    depth = high[2] - low[2]
    if width < 3.0 or depth < 3.0:
        return
    inset = 0.85
    x0, x1 = low[0] + inset, high[0] - inset
    z0, z1 = low[2] + inset, high[2] - inset
    # Layout is derived from the roof's own size so no two buildings repeat.
    span_x = x1 - x0
    span_z = z1 - z0
    rows = max(1, min(3, int(span_z // 3.4)))
    for row in range(rows):
        z = z0 + span_z * (row + 0.5) / rows
        stack_x = x0 + span_x * (0.22 + 0.16 * ((index + row) % 3))
        # A vent stack: shaft, collar, cowl and a rain hood over the mouth.
        add_box(plant_mesh, (stack_x - 0.16, top, z - 0.16), (stack_x + 0.16, top + 1.05, z + 0.16))
        add_box(coping_mesh, (stack_x - 0.22, top + 1.05, z - 0.22), (stack_x + 0.22, top + 1.16, z + 0.22))
        add_box(plant_mesh, (stack_x - 0.26, top + 1.16, z - 0.26), (stack_x + 0.26, top + 1.34, z + 0.26))
        add_box(trim_mesh, (stack_x - 0.32, top + 1.34, z - 0.32), (stack_x + 0.32, top + 1.44, z + 0.32))
        # A second, slimmer flue with a banded cap.
        flue_x = stack_x + 0.55
        if flue_x < x1 - 0.4:
            add_box(plant_mesh, (flue_x - 0.09, top, z - 0.09), (flue_x + 0.09, top + 1.55, z + 0.09))
            add_box(trim_mesh, (flue_x - 0.15, top + 1.55, z - 0.15), (flue_x + 0.15, top + 1.66, z + 0.15))
            add_box(trim_mesh, (flue_x - 0.11, top + 0.98, z - 0.11), (flue_x + 0.11, top + 1.05, z + 0.11))
    # A condenser on a raised frame, with a fan grille and louvred flanks.
    unit_x = x0 + span_x * 0.68
    unit_z = z1 - 0.75
    if unit_x < x1 - 0.6 and unit_z > z0 + 0.4:
        add_box(plant_mesh, (unit_x - 0.62, top + 0.24, unit_z - 0.46),
                (unit_x + 0.62, top + 0.94, unit_z + 0.46))
        add_box(trim_mesh, (unit_x - 0.68, top + 0.94, unit_z - 0.52),
                (unit_x + 0.68, top + 1.02, unit_z + 0.52))
        for leg_x in (-0.52, 0.52):
            for leg_z in (-0.36, 0.36):
                add_box(trim_mesh, (unit_x + leg_x - 0.05, top, unit_z + leg_z - 0.05),
                        (unit_x + leg_x + 0.05, top + 0.24, unit_z + leg_z + 0.05))
        # The fan grille, as concentric rims with a hub, on the roof face.
        cylinder(plant_mesh, (unit_x, top + 1.02, unit_z), 0, 0.40, 0.05, 14)
        for rim in (0.40, 0.30, 0.20):
            cylinder(trim_mesh, (unit_x, top + 1.06, unit_z), 0, rim, 0.045, 14)
        cylinder(trim_mesh, (unit_x, top + 1.09, unit_z), 0, 0.07, 0.08, 10)
        # Louvre bays along both flanks.
        for bay in range(4):
            lz = unit_z - 0.32 + bay * 0.21
            add_box(trim_mesh, (unit_x - 0.68, top + 0.36, lz - 0.07),
                    (unit_x - 0.62, top + 0.86, lz + 0.07))
            add_box(trim_mesh, (unit_x + 0.62, top + 0.36, lz - 0.07),
                    (unit_x + 0.68, top + 0.86, lz + 0.07))
    # A water tank on splayed legs, banded and lidded.
    tank_x = x1 - 1.05
    tank_z = z0 + span_z * 0.42
    if tank_x > x0 + 0.7:
        radius = min(0.72, span_x * 0.14)
        cylinder(plant_mesh, (tank_x, top + 0.72 + radius, tank_z), 1, radius, 1.55, 14)
        cylinder(coping_mesh, (tank_x, top + 0.72 + radius * 2.0, tank_z), 1, radius * 0.42, 0.30, 12)
        for band in (0.30, 0.72, 1.14):
            cylinder(trim_mesh, (tank_x, top + 0.72 + band, tank_z), 1, radius * 1.03, 0.07, 14)
        for leg in (-1.0, 1.0):
            for other in (-1.0, 1.0):
                tube(trim_mesh,
                     (tank_x + leg * radius * 0.62, top, tank_z + other * radius * 0.62),
                     (tank_x + leg * radius * 0.80, top + 0.72, tank_z + other * radius * 0.80),
                     0.045, 6)
        # A platform under the tank, so the legs land on something.
        add_box(trim_mesh, (tank_x - radius * 1.05, top + 0.62, tank_z - radius * 1.05),
                (tank_x + radius * 1.05, top + 0.72, tank_z + radius * 1.05))
    # A hatch on a curb, with a hinged lid and a lifting eye.
    hatch_x = x0 + span_x * 0.42
    hatch_z = z0 + 0.95
    if hatch_z < z1 - 0.5:
        add_box(coping_mesh, (hatch_x - 0.54, top, hatch_z - 0.48), (hatch_x + 0.54, top + 0.20, hatch_z + 0.48))
        add_box(plant_mesh, (hatch_x - 0.44, top + 0.20, hatch_z - 0.38),
                (hatch_x + 0.44, top + 0.28, hatch_z + 0.38))
        add_box(trim_mesh, (hatch_x - 0.40, top + 0.28, hatch_z - 0.34),
                (hatch_x + 0.40, top + 0.32, hatch_z + 0.34))
        tube(trim_mesh, (hatch_x, top + 0.32, hatch_z - 0.20), (hatch_x, top + 0.52, hatch_z - 0.20), 0.035, 8)
        cylinder(trim_mesh, (hatch_x, top + 0.54, hatch_z - 0.20), 1, 0.07, 0.06, 10)
    # Pipework: a run along the roof with elbows and wall brackets.
    pipe_y = top + 0.42
    run_x0, run_x1 = x0 + 0.35, x1 - 0.35
    if run_x1 - run_x0 > 1.6:
        add_box(trim_mesh, (run_x0, top, z0 + 1.75), (run_x1, top + 0.16, z0 + 1.95))
        cylinder(trim_mesh, ((run_x0 + run_x1) * 0.5, pipe_y, z0 + 1.85), 0, 0.075, run_x1 - run_x0, 10)
        for bracket in range(max(2, int((run_x1 - run_x0) // 1.6))):
            bx = run_x0 + (run_x1 - run_x0) * (bracket + 0.5) / max(2, int((run_x1 - run_x0) // 1.6))
            add_box(trim_mesh, (bx - 0.05, top, z0 + 1.68), (bx + 0.05, pipe_y + 0.10, z0 + 1.82))
            cylinder(trim_mesh, (bx, pipe_y + 0.10, z0 + 1.85), 0, 0.11, 0.06, 8)
        # Down the far side to the roof.
        tube(trim_mesh, (run_x1, pipe_y, z0 + 1.85), (run_x1, top + 0.06, z0 + 1.85), 0.075, 8)
        add_box(trim_mesh, (run_x1 - 0.10, top + 0.06, z0 + 1.72), (run_x1 + 0.06, top + 0.16, z0 + 1.98))
    # A lightning rod at one corner, with its bond conductor.
    rod_x = x1 - 0.35
    rod_z = z1 - 0.35
    cylinder(coping_mesh, (rod_x, top + 0.18, rod_z), 1, 0.10, 0.36, 8)
    tube(trim_mesh, (rod_x, top + 0.30, rod_z), (rod_x, top + 2.30, rod_z), 0.035, 8)
    cylinder(trim_mesh, (rod_x, top + 2.36, rod_z), 1, 0.05, 0.16, 8)
    tube(trim_mesh, (rod_x, top + 0.36, rod_z), (rod_x - 0.5, top + 0.06, rod_z - 0.5), 0.028, 6)
    # A roof lamp on a bracket, so the plant is not left in the dark.
    lamp_x = x0 + span_x * 0.12
    if lamp_z_check(hatch_z, z0, z1):
        add_box(lamp_mesh, (lamp_x - 0.13, top + 0.80, z0 + 1.50), (lamp_x + 0.13, top + 0.96, z0 + 1.76))
        add_box(trim_mesh, (lamp_x - 0.10, top + 0.96, z0 + 1.55), (lamp_x + 0.10, top + 1.06, z0 + 1.71))
    del kind, glass_mesh


def lamp_z_check(value, z0, z1):
    """A lamp bracket needs roof left under it, not the hatch it might straddle."""
    return z0 + 1.85 < z1 - 0.4 and abs(value - 0.95) > 0.4


def _roof_railing(low, high, kind, rail_mesh, trim_mesh):
    """A stanchion-and-rail guard along the parapet, with brackets and shoes."""
    band = 0.46
    base = high[1] + band
    height = 1.06
    for index, (along_x, low_a, high_a, fixed) in enumerate((
            (True, low[0] - 0.05, high[0] + 0.05, low[2] - 0.05 + 0.12),
            (True, low[0] - 0.05, high[0] + 0.05, high[2] + 0.05 - 0.12),
            (False, low[2] - 0.05, high[2] + 0.05, low[0] - 0.05 + 0.12),
            (False, low[2] - 0.05, high[2] + 0.05, high[0] + 0.05 - 0.12))):
        run = high_a - low_a
        if run < 1.8:
            continue
        posts = max(2, int(run // 1.35) + 1)
        for step in range(posts):
            t = low_a + run * step / (posts - 1)
            if along_x:
                # Base plate, then the standard.
                add_box(trim_mesh, (t - 0.09, base, fixed - 0.09), (t + 0.09, base + 0.05, fixed + 0.09))
                tube(trim_mesh, (t, base + 0.05, fixed), (t, base + height, fixed), 0.038, 8)
                add_box(trim_mesh, (t - 0.07, base + height - 0.05, fixed - 0.09),
                        (t + 0.07, base + height + 0.03, fixed + 0.09))
            else:
                add_box(trim_mesh, (fixed - 0.09, base, t - 0.09), (fixed + 0.09, base + 0.05, t + 0.09))
                tube(trim_mesh, (fixed, base + 0.05, t), (fixed, base + height, t), 0.038, 8)
                add_box(trim_mesh, (fixed - 0.09, base + height - 0.05, t - 0.07),
                        (fixed + 0.09, base + height + 0.03, t + 0.07))
        # Top rail, mid rail and a kick plate at the foot.
        for level, radius in ((height, 0.042), (height * 0.55, 0.030), (0.11, 0.026)):
            if along_x:
                tube(rail_mesh, (low_a, base + level, fixed), (high_a, base + level, fixed), radius, 8)
            else:
                tube(rail_mesh, (fixed, base + level, low_a), (fixed, base + level, high_a), radius, 8)
    del kind


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




def _landmark_detail(data, map_id, kind, material_index):
    """Detail on the slender structures the wall pass cannot cluster.

    A minaret or a crane mast is a single tall shell, so the cluster pass leaves
    it alone and it keeps the blockout silhouette. Each gets the parts its own
    kind of structure carries: the minaret a balcony, a crown and a finial, the
    crane a slew ring and rail base.
    """
    geometries = data["geometries"]
    made = 0
    for node in list(data["nodes"]):
        name = str(node.get("name", ""))
        if name.startswith("detail_") or node.get("geometry") is None:
            continue
        bounds = wall_corners(node, geometries)
        if bounds is None:
            continue
        low, high = bounds
        size = (high[0] - low[0], high[1] - low[1], high[2] - low[2])
        # Slender towers: much taller than they are wide.
        if size[1] < 8.0 or max(size[0], size[2]) > 3.0:
            continue
        tower = Mesh()
        trim = Mesh()
        lamp = Mesh()
        _tower_detail(low, high, size, tower, trim, lamp)
        made += _emit(data, map_id, material_index, (
            (tower, "ds_map_parapet", "ds_map_parapet"),
            (trim, "ds_map_metal_trim", "ds_map_metal_trim"),
            (lamp, "ds_map_lamp", "ds_map_lamp")))
    del kind
    return made


def _tower_detail(low, high, size, tower, trim, lamp):
    """A balcony, a crown and a finial on a slender tower or mast."""
    centre = ((low[0] + high[0]) * 0.5, (low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5)
    radius = max(size[0], size[2]) * 0.62
    # A corbelled balcony two thirds of the way up.
    balcony_y = low[1] + size[1] * 0.68
    for step in range(5):
        reach = radius * (0.72 + step * 0.06)
        add_box(tower, (centre[0] - reach, balcony_y + 0.09 * step, centre[2] - reach),
                (centre[0] + reach, balcony_y + 0.09 * (step + 1), centre[2] + reach))
    # Balustrade posts round the balcony, and its top rail.
    for index in range(12):
        angle = TAU * index / 12.0
        px = centre[0] + radius * 1.02 * math.cos(angle) * 0.92
        pz = centre[2] + radius * 1.02 * math.sin(angle) * 0.92
        cylinder(trim, (px, balcony_y + 0.45, pz), 1, 0.045, 0.42, 8)
    ring_quad(tower, (centre[0], balcony_y + 0.66, centre[2]), radius * 1.04, 0.10, 16)
    # A banded crown near the top and a finial above it.
    crown_y = high[1] - size[1] * 0.12
    add_box(tower, (centre[0] - radius * 0.92, crown_y, centre[2] - radius * 0.92),
            (centre[0] + radius * 0.92, crown_y + 0.22, centre[2] + radius * 0.92))
    add_box(tower, (centre[0] - radius * 0.76, crown_y + 0.22, centre[2] - radius * 0.76),
            (centre[0] + radius * 0.76, crown_y + 0.40, centre[2] + radius * 0.76))
    cylinder(tower, (centre[0], high[1] + 0.26, centre[2]), 1, radius * 0.34, 0.52, 12)
    cylinder(lamp, (centre[0], high[1] + 0.66, centre[2]), 1, radius * 0.16, 0.28, 10)
    tube(trim, (centre[0], high[1] + 0.80, centre[2]), (centre[0], high[1] + 1.30, centre[2]), 0.035, 8)
    del centre, lamp


def _rounded(document):
    """Truncate every geometry float to float32 precision before serialising.

    The detail meshes are computed in double precision, so `repr` emitted up to
    20 significant digits per coordinate. Godot imports the map geometry as
    float32, so those extra digits are bytes that are discarded on load: six
    significant digits is above float32's precision at these magnitudes and
    costs at most 5 um of positional error, three orders of magnitude below the
    tolerances the map verifier asserts. Applied on every run rather than by
    hand so the saving cannot be lost on a regeneration.
    """
    geometries = document.get("geometries", {})
    for record in geometries.values():
        for field in ("positions", "normals", "uvs"):
            values = record.get(field)
            if not values:
                continue
            record[field] = [float("%.6g" % value) if value else 0.0 for value in values]
    return document


def enrich(map_id):
    """Rebuilds this map's detail pass from scratch and reports what it added."""
    path = MAP_DIR / ("%s.json" % map_id)
    data = json.loads(path.read_text())
    geometries = data["geometries"]
    materials = data["materials"]
    kind = MAP_KIND[map_id]

    # Idempotent: drop any detail this pass emitted previously, so re-running
    # replaces rather than stacks the roofs, parapets and openings. Only the
    # geometry those detail nodes referenced is released; authored geometry is
    # never touched, even if it happens to be unreferenced.
    # Every detail node this pass has ever emitted starts with `detail_`, and no
    # authored node does, so releasing on that prefix alone also clears any node
    # left behind by an earlier revision of this pass.
    detail_prefix = "detail_"
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
    slab_like = []
    for index, node in structural:
        bounds = wall_corners(node, geometries)
        if bounds is None:
            continue
        low, high = bounds
        size = (high[0] - low[0], high[1] - low[1], high[2] - low[2])
        if size[1] < 1.2 or min(size[0], size[2]) > 1.0:
            # A roof slab: too shallow and too wide to be a wall, but its
            # footprint is still the building's, which doors and shutters need.
            slab_like.append(bounds)
            continue
        walls.append((bounds, node["name"]))

    parapet_mesh = Mesh()
    coping_mesh = Mesh()
    band_mesh = Mesh()
    plinth_mesh = Mesh()
    frame_mesh = Mesh()
    glass_mesh = Mesh()
    door_mesh = Mesh()
    trim_mesh = Mesh()
    shutter_mesh = Mesh()
    opening_mesh = Mesh()
    plant_mesh = Mesh()
    roof_mesh = Mesh()
    rail_mesh = Mesh()

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
        built += 1
        config = OPENINGS[kind]
        # The masonry envelope: parapet and coping, cornice, banding courses,
        # quoins and a plinth with its step and splay.
        _parapet(low, high, kind, parapet_mesh, coping_mesh, trim_mesh)
        _cornice(low, high, kind, trim_mesh, coping_mesh)
        _storey_courses(low, high, kind, band_mesh, trim_mesh)
        _quoins(low, high, kind, trim_mesh)
        _plinth(low, high, kind, plinth_mesh, coping_mesh)
        # Openings on all four facades, then the roofscape over the top.
        _facade_openings(low, high, kind, config,
                         (opening_mesh, glass_mesh, frame_mesh, door_mesh, shutter_mesh, trim_mesh))
        _roof_plant(low, high, kind, built, plant_mesh, trim_mesh, coping_mesh,
                    glass_mesh, lamp := Mesh())
        _roof_railing(low, high, kind, rail_mesh, trim_mesh)
        del lamp

    # Landmarks: the mosque's walls, minaret and the dock cranes' bases are
    # structural shells in their own right and never cluster into a building.
    landmarks = _landmark_detail(data, map_id, kind, material_index)

    emitted = _emit(data, map_id, material_index, (
        (parapet_mesh, "ds_map_parapet", "ds_map_parapet"),
        (coping_mesh, "ds_map_coping", "ds_map_coping"),
        (band_mesh, "ds_map_band", "ds_map_frame"),
        (plinth_mesh, "ds_map_plinth", "ds_map_plinth"),
        (frame_mesh, "ds_map_frame", "ds_map_frame"),
        (glass_mesh, "ds_map_glass_dark", "ds_map_glass_dark"),
        (door_mesh, "ds_map_door", "ds_map_door"),
        (shutter_mesh, "ds_map_shutter", "ds_map_canvas"),
        (opening_mesh, "ds_map_reveal", "ds_map_metal_trim"),
        (trim_mesh, "ds_map_metal_trim", "ds_map_metal_trim"),
        (plant_mesh, "ds_map_roof_plant", "ds_map_roof"),
        (roof_mesh, "ds_map_roof", "ds_map_roof"),
        (rail_mesh, "ds_map_rail", "ds_map_rail"),
    ))
    ground = _ground_pass(map_id, data, material_index)
    props = _prop_detail(data, map_id, material_index)
    containers = _container_detail(data, map_id, material_index)
    trunks, canopies, tree_nodes = _tree_detail(data, map_id, material_index)

    path.write_text(json.dumps(_rounded(data), separators=(",", ":")))
    print("%-16s %3d wall panels -> %2d buildings, %d structures, %d ground, "
          "%d props, %d containers, %d trunks + %d canopies, %d landmarks, %d detail nodes"
          % (map_id, len(walls), built, len(groups), ground, props, containers,
             trunks, canopies, landmarks, emitted + ground + tree_nodes))


# --------------------------------------------------------------------------
# Ground: paving, kerbs, markings, drainage, bollards and a retaining edge.
# --------------------------------------------------------------------------

def terrain_height(kind, amplitude, x, z):
    """The map's own ground height, so paving follows the terrain it sits on.

    The three arenas either lie flat (`desert_town`, `urban_docks`) or carry the
    authored heightfield (`forest_facility`, 100 segments over 180 m). Sampling
    the same expression the export used keeps a kerb on the ground and a marking
    flat on the road instead of buried or floating.
    """
    if kind == "flat":
        return 0.0
    return (math.sin(x * 0.05) * math.cos(z * 0.045)
            + 0.5 * math.sin(x * 0.11 + 1.3) * math.cos(z * 0.1 - 0.7)
            + 0.25 * math.sin(x * 0.21 - 0.4) * math.cos(z * 0.19 + 0.9)) / 1.75 * amplitude


def _pave_ring(mesh, x0, x1, z0, z1, inner_x0, inner_x1, inner_z0, inner_z1, height_at):
    """Lays a paved band as individual slabs, with a joint between each."""
    joint = 0.055
    along_x = int((x1 - x0) // PAVER)
    along_z = int((z1 - z0) // PAVER)
    for row in range(along_z):
        za = z0 + (z1 - z0) * row / along_z
        zb = z0 + (z1 - z0) * (row + 1) / along_z
        for col in range(along_x):
            xa = x0 + (x1 - x0) * col / along_x
            xb = x0 + (x1 - x0) * (col + 1) / along_x
            cx, cz = (xa + xb) * 0.5, (za + zb) * 0.5
            if inner_x0 < cx < inner_x1 and inner_z0 < cz < inner_z1:
                continue
            ax, az = xa + joint, za + joint
            bx, bz = xb - joint, zb - joint
            if bx - ax < 0.2 or bz - az < 0.2:
                continue
            floor_quad(mesh, ax, az, bx, bz,
                       height_at(ax, az), height_at(bx, az), height_at(bx, bz), height_at(ax, bz))


def _kerb_ring(mesh, cap_mesh, x0, x1, z0, z1, height_at):
    """A kerb run along all four edges, with a return turning at each end.

    The kerb is built as stones: an upright face set `KERB_HEIGHT` proud of the
    road, a battered top course narrower than the face, and a return block where
    the run ends so the line closes instead of stopping square.
    """
    for along_x, fixed, sign in ((True, z0, 1.0), (True, z1, -1.0),
                                 (False, x0, 1.0), (False, x1, -1.0)):
        low_a, high_a = (x0, x1) if along_x else (z0, z1)
        run = high_a - low_a
        stones = max(1, int(run // 1.5))
        inward = 0.22
        for step in range(stones):
            a = low_a + run * step / stones
            b = low_a + run * (step + 1) / stones
            ya = height_at(a, fixed) if along_x else height_at(fixed, a)
            yb = height_at(b, fixed) if along_x else height_at(fixed, b)
            y = max(ya, yb)
            near = fixed + sign * inward * 0.0
            if along_x:
                add_box(mesh, (a, y - 0.14, fixed), (b, y, fixed + sign * inward))
                add_box(cap_mesh, (a, y, fixed), (b, y + KERB_HEIGHT, fixed + sign * inward * 0.72))
            else:
                add_box(mesh, (fixed, y - 0.14, a), (fixed + sign * inward, y, b))
                add_box(cap_mesh, (fixed, y, a), (fixed + sign * inward * 0.72, y + KERB_HEIGHT, b))
            del near
        # The return at the far end of the run.
        edge = high_a
        y = height_at(edge, fixed) if along_x else height_at(fixed, edge)
        if along_x:
            add_box(mesh, (edge - 0.30, y - 0.14, fixed), (edge, y, fixed + sign * inward))
            add_box(cap_mesh, (edge - 0.30, y, fixed), (edge, y + KERB_HEIGHT, fixed + sign * inward * 0.72))
        else:
            add_box(mesh, (fixed, y - 0.14, edge - 0.30), (fixed + sign * inward, y, edge))
            add_box(cap_mesh, (fixed, y, edge - 0.30),
                    (fixed + sign * inward * 0.72, y + KERB_HEIGHT, edge))



def _road_markings(mesh, x0, x1, z0, z1, height_at):
    """A centre line, lane dashes, stop bars and a hatch at each junction."""
    y_at = lambda x, z: height_at(x, z) + KERB_HEIGHT + 0.012
    width = 0.14
    # Centre line: long dashes down the middle of all four road bands.
    for along_x, fixed, low_a, high_a in ((True, (z0 + z1) * 0.5, x0, x1),
                                          (False, (x0 + x1) * 0.5, z0, z1)):
        run = high_a - low_a
        dashes = max(4, int(run // 3.4))
        for step in range(dashes):
            a = low_a + run * step / dashes
            b = a + run / dashes * 0.55
            if along_x:
                floor_quad(mesh, a, fixed - width * 0.5, b, fixed + width * 0.5,
                           y_at(a, fixed - width * 0.5), y_at(b, fixed - width * 0.5),
                           y_at(b, fixed + width * 0.5), y_at(a, fixed + width * 0.5))
            else:
                floor_quad(mesh, fixed - width * 0.5, a, fixed + width * 0.5, b,
                           y_at(fixed - width * 0.5, a), y_at(fixed + width * 0.5, a),
                           y_at(fixed + width * 0.5, b), y_at(fixed - width * 0.5, b))
    # Stop bars and hazard chevrons where the road meets the apron corners.
    for sign_x in (-1.0, 1.0):
        for sign_z in (-1.0, 1.0):
            bx = (x0 + x1) * 0.5 + sign_x * (APRON_HALF_X + ROAD_WIDTH * 0.5 - 1.2)
            bz = (z0 + z1) * 0.5 + sign_z * (APRON_HALF_Z + ROAD_WIDTH * 0.5 - 1.2)
            floor_quad(mesh, bx - 1.6, bz - 0.12, bx + 1.6, bz + 0.12,
                       y_at(bx - 1.6, bz - 0.12), y_at(bx + 1.6, bz - 0.12),
                       y_at(bx + 1.6, bz + 0.12), y_at(bx - 1.6, bz + 0.12))
            # A chevron strip, each bar laid at 45 degrees.
            for bar in range(5):
                t = (bar - 2.0) * 0.34
                cx, cz = bx + t, bz + 0.62 * sign_z
                floor_quad(mesh, cx - 0.20, cz - 0.09, cx + 0.20, cz + 0.09,
                           y_at(cx - 0.20, cz - 0.09), y_at(cx + 0.20, cz - 0.09),
                           y_at(cx + 0.20, cz + 0.09), y_at(cx - 0.20, cz + 0.09))


def _drainage(mesh, trim_mesh, x0, x1, z0, z1, height_at):
    """Drainage gratings in recessed frames, plus flush utility covers.

    A grate sits in a frame cut into the paving, its bars standing below the
    surface so the frame edge catches light all the way round the opening.
    """
    def grating(gx, gz, along_x):
        width, depth = (1.15, 0.46) if along_x else (0.46, 1.15)
        surface = height_at(gx, gz)
        add_box(trim_mesh, (gx - width * 0.5, surface - 0.17, gz - depth * 0.5),
                (gx + width * 0.5, surface - 0.02, gz + depth * 0.5))
        bars = 7
        span = width if along_x else depth
        for bar in range(bars):
            t = (gx if along_x else gz) - span * 0.5 + span * (bar + 0.5) / bars
            if along_x:
                add_box(mesh, (t - 0.035, surface - 0.11, gz - depth * 0.40),
                        (t + 0.035, surface - 0.025, gz + depth * 0.40))
            else:
                add_box(mesh, (gx - depth * 0.40, surface - 0.11, t - 0.035),
                        (gx + depth * 0.40, surface - 0.025, t + 0.035))

    def cover(cx, cz, radius):
        surface = height_at(cx, cz)
        cylinder(mesh, (cx, surface - 0.035, cz), 1, radius, 0.055, 12)
        cylinder(trim_mesh, (cx, surface - 0.005, cz), 1, radius * 0.55, 0.04, 10)

    for sign_x in (-1.0, 1.0):
        for sign_z in (-1.0, 1.0):
            grating(sign_x * (APRON_HALF_X - 3.5), sign_z * (APRON_HALF_Z - 2.0), sign_x < 0)
            cover(sign_x * (APRON_HALF_X - 6.5), sign_z * (APRON_HALF_Z + 2.2), 0.30)
            cover(sign_x * (APRON_HALF_X + 5.0), sign_z * (APRON_HALF_Z - 6.0), 0.26)
    for index in range(4):
        cover((index - 1.5) * 5.5, (index % 2) * 4.0 - 2.0, 0.28)



def _bollards(mesh, trim_mesh, x0, x1, z0, z1, height_at):
    """A line of cast bollards along the apron edge: base, shaft, collar, cap."""
    for along_x, fixed in ((True, z0), (True, z1), (False, x0), (False, x1)):
        low_a, high_a = (x0, x1) if along_x else (z0, z1)
        run = high_a - low_a
        count = max(2, int(run // 3.2))
        for step in range(count):
            t = low_a + run * (step + 0.5) / count
            bx, bz = (t, fixed) if along_x else (fixed, t)
            base_y = height_at(bx, bz)
            cylinder(trim_mesh, (bx, base_y - 0.05, bz), 1, 0.165, 0.12, 12)
            cylinder(mesh, (bx, base_y + 0.60, bz), 1, 0.105, 1.20, 12)
            cylinder(trim_mesh, (bx, base_y + 1.20, bz), 1, 0.135, 0.10, 12)
            cylinder(mesh, (bx, base_y + 1.33, bz), 1, 0.090, 0.18, 12)
            cylinder(trim_mesh, (bx, base_y + 1.44, bz), 1, 0.045, 0.09, 10)



def _retaining_edge(mesh, coping_mesh, trim_mesh, x0, x1, z0, z1, height_at):
    """A low retaining wall along the far apron edge, coped and banded.

    The apron has to be held up by something where the road steps down to it, so
    this closes the edge with a wall, a banding course and a weathered coping.
    """
    for along_x, fixed, sign in ((True, z1, -1.0), (False, x1, -1.0)):
        low_a, high_a = (x0, x1) if along_x else (z0, z1)
        run = high_a - low_a
        stones = max(2, int(run // 4.0))
        for step in range(stones):
            a = low_a + run * step / stones
            b = low_a + run * (step + 1) / stones
            if along_x:
                ya = height_at(a, fixed)
                add_box(mesh, (a + 0.05, ya - 0.34, fixed), (b - 0.05, ya + 0.46, fixed + sign * 0.46))
                add_box(trim_mesh, (a + 0.10, ya + 0.22, fixed - 0.03),
                        (b - 0.10, ya + 0.32, fixed + sign * 0.44))
                add_box(coping_mesh, (a, ya + 0.46, fixed + 0.07),
                        (b, ya + 0.60, fixed + sign * 0.56))
            else:
                ya = height_at(fixed, a)
                add_box(mesh, (fixed, ya - 0.34, a + 0.05), (fixed + sign * 0.46, ya + 0.46, b - 0.05))
                add_box(trim_mesh, (fixed - 0.03, ya + 0.22, a + 0.10),
                        (fixed + sign * 0.44, ya + 0.32, b - 0.10))
                add_box(coping_mesh, (fixed + 0.07, ya + 0.46, a),
                        (fixed + sign * 0.56, ya + 0.60, b))



def _ground_pass(map_id, data, material_index):
    """Lays the arena ground: paving, kerbs, markings, drainage and bollards.

    This is what turns a bare terrain quad into a yard: a paved apron, a kerb
    around every edge, a patrol road with a centre line and stop bars, drainage
    and covers let into the slabs, bollards along the apron edge, and a retaining
    wall closing the far side. The terrain's own height is sampled throughout, so
    the paving follows the map instead of floating over it.
    """
    if map_id not in PAVED_MAPS:
        return 0
    terrain = data.get("terrain", {})
    amplitude = float(terrain.get("amplitude", 0.0))
    terrain_kind = str(terrain.get("kind", "flat"))
    height_at = lambda x, z: terrain_height(terrain_kind, amplitude, x, z)

    paving = Mesh()
    kerb = Mesh()
    paint = Mesh()
    rail = Mesh()
    trim = Mesh()
    # The road band and the apron ring, laid as slabs around a kept-clear core.
    _pave_ring(paving, -ROAD_OUTER_X, ROAD_OUTER_X, -ROAD_OUTER_Z, ROAD_OUTER_Z,
               -APRON_HALF_X, APRON_HALF_X, -APRON_HALF_Z, APRON_HALF_Z, height_at)
    _kerb_ring(kerb, trim, -APRON_HALF_X, APRON_HALF_X, -APRON_HALF_Z, APRON_HALF_Z, height_at)
    _kerb_ring(kerb, trim, -ROAD_OUTER_X, ROAD_OUTER_X, -ROAD_OUTER_Z, ROAD_OUTER_Z, height_at)
    _road_markings(paint, -ROAD_OUTER_X, ROAD_OUTER_X, -ROAD_OUTER_Z, ROAD_OUTER_Z, height_at)
    _drainage(rail, trim, -APRON_HALF_X, APRON_HALF_X, -APRON_HALF_Z, APRON_HALF_Z, height_at)
    _bollards(kerb, trim, -APRON_HALF_X, APRON_HALF_X, -APRON_HALF_Z, APRON_HALF_Z, height_at)
    _retaining_edge(kerb, trim, trim, -ROAD_OUTER_X, ROAD_OUTER_X, -ROAD_OUTER_Z, ROAD_OUTER_Z, height_at)

    return _emit(data, map_id, material_index, (
        (paving, "ds_map_paving", "ds_map_paving"),
        (kerb, "ds_map_kerb", "ds_map_kerb"),
        (paint, "ds_map_paint", "ds_map_paint"),
        (trim, "ds_map_ground_trim", "ds_map_coping"),
        (rail, "ds_map_ground_rail", "ds_map_rail")))



def _emit(data, map_id, material_index, meshes):
    """Appends one detail node per non-empty mesh as `(mesh, slot, material)`.

    The slot decides the node name `detail_<map_id>_<slot>` and the material
    decides shading; they are independent because `verify_maps.gd` matches on the
    slot suffix while the surface pass needs the material key. Repeating a slot
    is allowed and useful — several disjoint pieces can share one material — so a
    trailing index keeps every node name unique.

    Uniqueness is a hard requirement, not a nicety: Godot renames a colliding
    child to `@MeshInstance3D@N`, which no longer starts with `detail_`, so
    `verify_maps.gd` counts it as authored geometry and the authored total no
    longer matches. Names are therefore deduplicated against every name the
    document already holds, not only against the slots this call emits — the
    authored nodes and any earlier pass share the same node list.
    """
    geometries = data["geometries"]
    next_key = max(int(key) for key in geometries) + 1
    used = {str(node.get("name", "")) for node in data["nodes"]}
    made = 0
    for mesh, slot, material in meshes:
        if mesh.empty():
            continue
        name = "detail_%s_%s" % (map_id, slot)
        index = 2
        while name in used:
            name = "detail_%s_%s_%d" % (map_id, slot, index)
            index += 1
        used.add(name)
        geometries[str(next_key)] = {
            "positions": mesh.positions,
            "normals": [],
            "uvs": [],
            "indices": mesh.indices,
        }
        data["nodes"].append({
            "name": name,
            "geometry": str(next_key),
            "material": material_index[material],
            "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            "visible": True,
            "castShadow": True,
        })
        next_key += 1
        made += 1
    return made


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


def _prop_detail(data, map_id, material_index):
    """Adds wheels, glazing, machinery and lamp detail to the authored props.

    Detail is derived per *part* rather than per instance. A prop is authored as
    several boxes whose world positions overlap heavily — four cars parked in a
    row stand about 1.8 m apart while the parts of one car sit within 1 m of each
    other — so no proximity threshold separates instances reliably. Keying off
    each part's own proportions instead is exact: a car's chassis is the wide, low
    part and its cabin is the narrow, raised one, wherever they stand.
    """
    geometries = data["geometries"]
    parts = {slot: Mesh() for slot in PROP_SLOTS}
    made = 0
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
            rule(parts, tuple(low), tuple(high), tuple(size), centre)
        made += 1

    return made + _emit(data, map_id, material_index, tuple(
        (parts[slot],) + PROP_SLOT_MATERIALS[slot] for slot in PROP_SLOTS
        if not parts[slot].empty()))


# --------------------------------------------------------------------------
# Per-part prop rules. Each receives the part's world bounds and adds only the
# detail that part actually carries.
# --------------------------------------------------------------------------

def _prop_car(parts, low, high, size, centre):
    """Wheels under the chassis, glazing around the cabin, lamps on the ends.

    A car is authored as a chassis box, a cabin box, four wheel boxes and a
    bumper strip. This adds the parts the blockout omits — arch trims and fender
    lips around the wheels, a windscreen with a surround and wipers, door
    handles, a fuel filler, a roof rack and a light bar — all sized from the
    part's own bounds so they land correctly wherever the car stands.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")
    rail = parts["rail"]

    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")

    footprint = max(size[0], size[2])
    if footprint > 3.0:
        # Chassis: the wheel arches, their fender lips, bumpers and lamps.
        radius = min(0.36, max(0.26, size[1] * 0.52))
        for sign_x in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                arch = (centre[0] + sign_x * (size[0] * 0.5 - 0.02),
                        low[1] + radius * 0.62,
                        centre[2] + sign_z * (size[2] * 0.5 - radius * 1.25))
                _arch(rubber, arch, radius, sign_z, size[2])
                # The fender lip: a bead following the arch, proud of the tyre.
                _arch(trim, (arch[0], arch[1], arch[2] + sign_z * 0.05),
                      radius + 0.055, sign_z, size[2] * 0.62)
        for sign_z in (-1.0, 1.0):
            # Bumper and its end caps.
            _slab(trim, (low[0], low[1] + size[1] * 0.15, centre[2] + sign_z * size[2] * 0.5),
                  (high[0], low[1] + size[1] * 0.45, centre[2] + sign_z * (size[2] * 0.5 + 0.08)))
            for sign_x in (-1.0, 1.0):
                _slab(trim, (low[0] if sign_x < 0 else high[0] - 0.10,
                             low[1] + size[1] * 0.15, centre[2] + sign_z * size[2] * 0.5),
                      (low[0] + 0.10 if sign_x < 0 else high[0],
                       low[1] + size[1] * 0.52, centre[2] + sign_z * (size[2] * 0.5 + 0.11)))
            # Head and tail lamps, set into the bumper line.
            _slab(lamp, (low[0] + size[0] * 0.08, low[1] + size[1] * 0.45, centre[2] + sign_z * size[2] * 0.5),
                  (low[0] + size[0] * 0.30, low[1] + size[1] * 0.80, centre[2] + sign_z * (size[2] * 0.5 + 0.04)))
            _slab(lamp, (high[0] - size[0] * 0.30, low[1] + size[1] * 0.45, centre[2] + sign_z * size[2] * 0.5),
                  (high[0] - size[0] * 0.08, low[1] + size[1] * 0.80, centre[2] + sign_z * (size[2] * 0.5 + 0.04)))
            # A rubbing strip along the sill, and the fuel filler on one flank.
            _slab(trim, (low[0] + 0.12, low[1] + size[1] * 0.10, centre[2] + sign_z * size[2] * 0.5),
                  (high[0] - 0.12, low[1] + size[1] * 0.24, centre[2] + sign_z * (size[2] * 0.5 + 0.045)))
        for sign_x in (-1.0, 1.0):
            # Sills down both longer flanks, and the filler cap behind one.
            _slab(trim, (centre[0] + sign_x * size[0] * 0.5, low[1] + size[1] * 0.14, low[2] + 0.30),
                  (centre[0] + sign_x * (size[0] * 0.5 + 0.05), low[1] + size[1] * 0.30, high[2] - 0.30))
            _slab(trim, (centre[0] + sign_x * size[0] * 0.5, low[1] + size[1] * 0.42,
                         high[2] - 0.95),
                  (centre[0] + sign_x * (size[0] * 0.5 + 0.035), low[1] + size[1] * 0.62,
                   high[2] - 0.72))
        # Bonnet and boot: the body panels the chassis box flattens away. Each
        # is a lid lifted off the chassis with a shut line round it.
        for sign_z, panel_depth in ((-1.0, size[2] * 0.24), (1.0, size[2] * 0.20)):
            outer = centre[2] + sign_z * size[2] * 0.5
            inner = outer - sign_z * panel_depth
            body_panel = (min(outer, inner), max(outer, inner))
            _slab(body, (low[0] + 0.06, high[1], body_panel[0]),
                  (high[0] - 0.06, high[1] + 0.07, body_panel[1]))
            _slab(trim, (low[0] + 0.02, high[1], body_panel[0] - sign_z * 0.03),
                  (high[0] - 0.02, high[1] + 0.03, body_panel[1]))
        # A body band along both flanks, below the glazing line.
        for sign_x in (-1.0, 1.0):
            _slab(body, (centre[0] + sign_x * size[0] * 0.5, low[1] + size[1] * 0.30, low[2] + 0.15),
                  (centre[0] + sign_x * (size[0] * 0.5 + 0.03), low[1] + size[1] * 0.62,
                   high[2] - 0.15))
        # A roof rack: two rails and three cross bars over the chassis.
        for sign_x in (-1.0, 1.0):
            _slab(rail, (centre[0] + sign_x * size[0] * 0.32, high[1], low[2] + 0.35),
                  (centre[0] + sign_x * (size[0] * 0.32 + 0.06), high[1] + 0.09, high[2] - 0.35))
        for index in range(3):
            z = low[2] + 0.45 + (size[2] - 0.90) * index / 2.0
            _slab(trim, (centre[0] - size[0] * 0.36, high[1] + 0.06, z - 0.045),
                  (centre[0] + size[0] * 0.36, high[1] + 0.12, z + 0.045))
    elif size[1] >= 0.30 and footprint > 1.0:
        # Cabin: a glazing band inset on all four sides, with the pillars proud of
        # it, a windscreen surround, wipers and a roof-mounted light bar.
        inset = size[0] * 0.04
        band_low = low[1] + size[1] * 0.14
        band_high = low[1] + size[1] * 0.86
        _slab(glass, (low[0] + inset, band_low, low[2] - 0.02), (high[0] - inset, band_high, low[2]))
        _slab(glass, (low[0] + inset, band_low, high[2]), (high[0] - inset, band_high, high[2] + 0.02))
        _slab(glass, (low[0] - 0.02, band_low, low[2] + inset), (low[0], band_high, high[2] - inset))
        _slab(glass, (high[0], band_low, low[2] + inset), (high[0] + 0.02, band_high, high[2] - inset))
        # A-pillars and B-pillars, so the glazing is divided as a real cabin is.
        for sign_x in (-1.0, 1.0):
            _slab(trim, (centre[0] + sign_x * 0.04 - 0.035, band_low - 0.03, low[2] - 0.03),
                  (centre[0] + sign_x * 0.04 + 0.035, band_high + 0.03, low[2] + 0.01))
        for sign_z in (-1.0, 1.0):
            for sign_x in (-1.0, 1.0):
                px = centre[0] + sign_x * size[0] * 0.46
                _slab(trim, (px - 0.03, band_low - 0.03, centre[2] + sign_z * size[2] * 0.5 - 0.03),
                      (px + 0.03, band_high + 0.03, centre[2] + sign_z * size[2] * 0.5 + 0.01))
        # The windscreen surround, a wiper pair parked on it, and the light bar.
        for sign_z in (-1.0, 1.0):
            _slab(trim, (low[0] + inset - 0.03, band_high, centre[2] + sign_z * size[2] * 0.5 - 0.02),
                  (high[0] - inset + 0.03, band_high + 0.06, centre[2] + sign_z * (size[2] * 0.5 + 0.05)))
            _slab(trim, (low[0] + inset - 0.03, band_low - 0.05, centre[2] + sign_z * size[2] * 0.5 - 0.02),
                  (high[0] - inset + 0.03, band_low, centre[2] + sign_z * (size[2] * 0.5 + 0.05)))
            for index in range(2):
                wx = centre[0] + (index * 2.0 - 1.0) * size[0] * 0.22
                _slab(trim, (wx - 0.30, band_low + 0.02, centre[2] + sign_z * (size[2] * 0.5 + 0.02)),
                      (wx + 0.30, band_low + 0.05, centre[2] + sign_z * (size[2] * 0.5 + 0.05)))
        # Door handles on the flanks, at the height a hand falls.
        for sign_z in (-1.0, 1.0):
            for sign_x in (-1.0, 1.0):
                hx = centre[0] + sign_x * size[0] * 0.22
                _slab(trim, (hx - 0.11, band_low + 0.06, centre[2] + sign_z * size[2] * 0.5),
                      (hx + 0.11, band_low + 0.12, centre[2] + sign_z * (size[2] * 0.5 + 0.035)))
        _slab(rail, (low[0] + inset, high[1], low[2] + inset), (high[0] - inset, high[1] + 0.07, high[2] - inset))
        # A roof vent on the plant slot: every cabin roof carries one.
        _slab(parts["roof"], (centre[0] - 0.22, high[1] + 0.07, centre[2] - 0.22),
              (centre[0] + 0.22, high[1] + 0.16, centre[2] + 0.22))
        for index in range(3):
            x = low[0] + inset + (size[0] - inset * 2.0) * (index + 0.5) / 3.0
            _slab(lamp, (x - 0.09, high[1] + 0.07, low[2] + 0.02), (x + 0.09, high[1] + 0.15, low[2] + 0.08))


def _prop_crane(parts, low, high, size, centre):
    """Lattice bracing, a counterweight stack, a glazed cab, a hook and a rail base.

    A crane is authored as a mast box, a jib box, a short counter-jib, a hoist
    cable and a hook. This builds the lattice bracing the mast and jib imply, the
    counterweight the short arm is there to carry, an operator cab with glazing,
    a hook block with sheaves, and a rail-mounted base under the mast.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")

    if size[1] > 6.0 and max(size[0], size[2]) < 3.0:
        # Mast: chord members up the corners and cross bracing between them.
        half = max(size[0], size[2]) * 0.42
        steps = 8
        for sign_x in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                _slab(trim, (centre[0] + sign_x * half - 0.055, low[1], centre[2] + sign_z * half - 0.055),
                      (centre[0] + sign_x * half + 0.055, high[1], centre[2] + sign_z * half + 0.055))
        for index in range(steps):
            y0 = low[1] + size[1] * index / steps
            y1 = low[1] + size[1] * (index + 1) / steps
            for sign_x in (-1.0, 1.0):
                for sign_z in (-1.0, 1.0):
                    # Each bay gets a diagonal and a horizontal, so the mast reads
                    # as a lattice from every side and not as a set of Xs.
                    _bar(trim, (centre[0] + sign_x * half, y0, centre[2] + sign_z * half),
                         (centre[0] - sign_x * half, y1, centre[2] + sign_z * half), 0.10)
                    _bar(trim, (centre[0] + sign_x * half, y1, centre[2] + sign_z * half),
                         (centre[0] - sign_x * half, y1, centre[2] + sign_z * half), 0.075)
                    _bar(trim, (centre[0] + sign_x * half, y0, centre[2] + sign_z * half),
                         (centre[0] + sign_x * half, y1, centre[2] - sign_z * half), 0.075)
        # The slewing ring and the rail-mounted base under the mast.
        cylinder(trim, (centre[0], low[1] + 0.16, centre[2]), 1, half * 1.30, 0.32, 14)
        cylinder(trim, (centre[0], low[1] - 0.10, centre[2]), 1, half * 1.75, 0.22, 14)
        for sign_x in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                _slab(rubber, (centre[0] + sign_x * half * 1.45 - 0.16, low[1] - 0.30,
                               centre[2] + sign_z * half * 1.30 - 0.10),
                      (centre[0] + sign_x * half * 1.45 + 0.16, low[1] - 0.10,
                       centre[2] + sign_z * half * 1.30 + 0.10))
        # Operator cab at the head of the mast, glazed on all four sides.
        cab_x0, cab_x1 = centre[0] - 1.02, centre[0] + 1.02
        cab_z0, cab_z1 = centre[2] - 1.02, centre[2] + 1.02
        cab_y0, cab_y1 = high[1] - 2.45, high[1] - 0.55
        _slab(body, (cab_x0, cab_y0, cab_z0), (cab_x1, cab_y1, cab_z1))
        for name, low_corner, high_corner in (
                ("front", (cab_x0 + 0.06, cab_y0 + 0.34, cab_z0 - 0.02), (cab_x1 - 0.06, cab_y1 - 0.24, cab_z0)),
                ("back", (cab_x0 + 0.06, cab_y0 + 0.34, cab_z1), (cab_x1 - 0.06, cab_y1 - 0.24, cab_z1 + 0.02)),
                ("left", (cab_x0 - 0.02, cab_y0 + 0.34, cab_z0 + 0.06), (cab_x0, cab_y1 - 0.24, cab_z1 - 0.06)),
                ("right", (cab_x1, cab_y0 + 0.34, cab_z0 + 0.06), (cab_x1 + 0.02, cab_y1 - 0.24, cab_z1 - 0.06))):
            del name
            _slab(glass, low_corner, high_corner)
        # A guard rail round the cab roof and a beacon on the corner of it.
        for sign_x in (-1.0, 1.0):
            _slab(trim, (centre[0] + sign_x * cab_x1 * 0.0 + sign_x * 0.95, cab_y1, cab_z0 + 0.20),
                  (centre[0] + sign_x * 0.95 + sign_x * 0.05, cab_y1 + 0.34, cab_z1 - 0.20))
        _slab(trim, (cab_x0, cab_y1 + 0.34, cab_z0 + 0.20), (cab_x1, cab_y1 + 0.40, cab_z1 - 0.20))
        cylinder(lamp, (cab_x1 - 0.20, cab_y1 + 0.48, cab_z1 - 0.20), 1, 0.13, 0.22, 10)
    elif size[0] > 8.0:
        # Jib: a lattice underside with a trolley and a load cable.
        bays = 6
        _slab(trim, (low[0], low[1], centre[2] - 0.05), (high[0], low[1] + 0.10, centre[2] + 0.05))
        _slab(trim, (low[0], high[1], centre[2] - 0.05), (high[0], high[1] - 0.10, centre[2] + 0.05))
        for index in range(bays):
            t0 = index / bays
            t1 = (index + 1) / bays
            _bar(trim, (low[0] + size[0] * t0, low[1], centre[2]),
                 (low[0] + size[0] * t1, low[1] - size[1] * 0.9, centre[2]), 0.09)
            _bar(trim, (low[0] + size[0] * t0, low[1] - size[1] * 0.9, centre[2]),
                 (low[0] + size[0] * t1, low[1], centre[2]), 0.09)
            _slab(trim, (low[0] + size[0] * t1 - 0.04, low[1] - size[1] * 0.9, centre[2] - 0.35),
                  (low[0] + size[0] * t1 + 0.04, low[1], centre[2] + 0.35))
        trolley_x = centre[0] + size[0] * 0.22
        _slab(trim, (trolley_x - 0.42, low[1] - 0.28, centre[2] - 0.30),
              (trolley_x + 0.42, low[1], centre[2] + 0.30))
        # The load cable and its hook block, with two sheaves in a cheek plate.
        _slab(trim, (trolley_x - 0.03, low[1] - 4.20, trolley_x * 0.0 + centre[2] - 0.03),
              (trolley_x + 0.03, low[1] - 0.28, centre[2] + 0.03))
        hook_y = low[1] - 4.55
        for sign_z in (-1.0, 1.0):
            cylinder(trim, (trolley_x, hook_y + 0.30, centre[2] + sign_z * 0.13), 2, 0.17, 0.07, 12)
        _slab(trim, (trolley_x - 0.20, hook_y + 0.10, centre[2] - 0.17),
              (trolley_x + 0.20, hook_y + 0.32, centre[2] + 0.17))
        _slab(trim, (trolley_x - 0.10, hook_y - 0.02, centre[2] - 0.10),
              (trolley_x + 0.10, hook_y + 0.12, centre[2] + 0.10))
        _bar(trim, (trolley_x, hook_y - 0.02, centre[2]),
             (trolley_x + 0.26, hook_y - 0.30, centre[2]), 0.08)
        _bar(trim, (trolley_x + 0.26, hook_y - 0.30, centre[2]),
             (trolley_x, hook_y - 0.52, centre[2]), 0.08)
    else:
        # Counter-jib: a counterweight stack on a platform, with tie bars.
        _slab(body, (low[0] + 0.20, low[1] + 0.20, low[2] + 0.20),
              (high[0] - 0.20, high[1] - 0.20, high[2] - 0.20))
        for index in range(4):
            y = low[1] + 0.26 + index * 0.24
            _slab(trim, (low[0] - 0.04, y, low[2] - 0.04), (high[0] + 0.04, y + 0.20, high[2] + 0.04))
        _bar(trim, (low[0], high[1], centre[2]), (high[0], high[1] + 1.30, centre[2]), 0.11)


def _prop_stall(parts, low, high, size, centre):
    """A canopy frame with ribs, a counter with a skirt and stacked goods.

    A stall is authored as four corner posts and a canopy slab. The frame, the
    ribs, the valance, the counter and the crates are all derived from those two
    parts, so a post gets a foot and a finial and the counter gets its goods.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")
    rail = parts["rail"]

    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")
    canvas = parts["canvas"]

    if size[1] > 1.4 and max(size[0], size[2]) < 0.4:
        # A corner post: a base plate, a capital and a finial, plus the top rail
        # the canopy lands on.
        _slab(trim, (centre[0] - 0.13, low[1], centre[2] - 0.13),
              (centre[0] + 0.13, low[1] + 0.08, centre[2] + 0.13))
        _slab(trim, (centre[0] - 0.10, low[1] + 0.08, centre[2] - 0.10),
              (centre[0] + 0.10, low[1] + 0.30, centre[2] + 0.10))
        _slab(trim, (centre[0] - 0.10, high[1] - 0.22, centre[2] - 0.10),
              (centre[0] + 0.10, high[1], centre[2] + 0.10))
        _slab(trim, (centre[0] - 0.09, high[1], centre[2] - 0.09),
              (centre[0] + 0.09, high[1] + 0.12, centre[2] + 0.09))
        _bar(trim, (centre[0], high[1] + 0.12, centre[2]),
             (centre[0], high[1] + 0.30, centre[2]), 0.05)
        for sign_x in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                _bar(rail, (centre[0], high[1] - 0.14, centre[2]),
                     (centre[0] + sign_x * 1.30, high[1] - 0.14, centre[2] + sign_z * 1.30), 0.045)
        for index in range(4):
            angle = TAU * (index + 0.5) / 4.0
            _bar(trim, (centre[0] + 0.62 * math.cos(angle), high[1] - 1.10, centre[2] + 0.62 * math.sin(angle)),
                 (centre[0] + 0.62 * math.cos(angle), low[1], centre[2] + 0.62 * math.sin(angle)), 0.035)
    elif size[0] > 1.0 and size[1] < 0.25:
        # The counter: a skirt below, boxes stacked above it.
        _slab(trim, (low[0] + 0.05, low[1] - 0.42, low[2] + 0.05),
              (high[0] - 0.05, low[1], high[2] - 0.05))
        for index in range(4):
            x = centre[0] + (index - 1.5) * size[0] * 0.22
            stack = 2 if index % 2 == 0 else 1
            for level in range(stack):
                _slab(trim, (x - 0.17, high[1] + level * 0.24, centre[2] - size[2] * 0.28),
                      (x + 0.17, high[1] + 0.22 + level * 0.24, centre[2] + size[2] * 0.28))


def _prop_radar(parts, low, high, size, centre):
    """A reflector of concentric rings, a feed horn on a tripod, a jointed mast.

    The dish is authored as a plain box, so this replaces its silhouette with a
    parabolic reflector built from rings, puts a feed horn on a tripod at the
    focus, and gives the mast a pedestal with a rotation joint and support
    struts — which is what makes it read as machinery from the ground.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")

    footprint = max(size[0], size[2])
    if size[1] > 4.0 and footprint < 3.0:
        # The mast: a pedestal, a rotation joint, support struts and a beacon.
        _slab(trim, (centre[0] - 0.62, low[1], centre[2] - 0.62),
              (centre[0] + 0.62, low[1] + 0.22, centre[2] + 0.62))
        cylinder(trim, (centre[0], low[1] + 0.34, centre[2]), 1, 0.40, 0.26, 12)
        cylinder(body, (centre[0], high[1] * 0.5, centre[2]), 1, 0.26, size[1] * 0.9, 12)
        for index in range(4):
            angle = TAU * index / 4.0 + 0.4
            _bar(trim, (centre[0], low[1] + 0.24, centre[2]),
                 (centre[0] + 0.62 * math.cos(angle), low[1] + size[1] * 0.34,
                  centre[2] + 0.62 * math.sin(angle)), 0.06)
        # A collar and the rotation joint at the head of the mast.
        cylinder(trim, (centre[0], high[1] - 0.30, centre[2]), 1, 0.34, 0.24, 12)
        cylinder(lamp, (centre[0], high[1], centre[2]), 1, 0.08, 0.30, 10)
        _bar(trim, (centre[0], high[1], centre[2]), (centre[0], high[1] + 1.40, centre[2]), 0.10)
        _slab(lamp, (centre[0] - 0.14, high[1] + 1.40, centre[2] - 0.14),
              (centre[0] + 0.14, high[1] + 1.68, centre[2] + 0.14))
    elif footprint > 3.0:
        # The reflector: concentric rings on a shallow parabola, with a rim and
        # a feed horn on its tripod at the focus.
        radius = footprint * 0.5
        _dish(body, (centre[0], high[1], centre[2]), radius, 0.60)
        _ring_dish(trim, (centre[0], high[1], centre[2]), radius, 0.60)
        for index in range(3):
            angle = TAU * index / 3.0 + 0.5
            _bar(trim, (centre[0], high[1] + 0.72, centre[2]),
                 (centre[0] + radius * 0.72 * math.cos(angle),
                  high[1] - 0.30, centre[2] + radius * 0.72 * math.sin(angle)), 0.055)
        cylinder(trim, (centre[0], high[1] + 0.74, centre[2]), 1, 0.10, 0.22, 10)
        _slab(lamp, (centre[0] - 0.12, high[1] + 0.86, centre[2] - 0.12),
              (centre[0] + 0.12, high[1] + 1.06, centre[2] + 0.12))


def _prop_barrier(parts, low, high, size, centre):
    """End feet, a top rail, reflective plates and a linkage hook.

    A barrier is authored as a rail box and a short foot box. This gives it the
    feet its rail stands on, a top rail, reflective plates set into both faces
    and the hook that links it to the next one in the run.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")

    if max(size[0], size[2]) < 1.5:
        return
    along_x = size[0] >= size[2]
    span = max(size[0], size[2])
    for sign in (-1.0, 1.0):
        offset = sign * (span * 0.5 - 0.08)
        px = centre[0] + (offset if along_x else 0.0)
        pz = centre[2] + (0.0 if along_x else offset)
        # The end post, its foot plate and the shoe bolted to the ground.
        _slab(trim, (px - 0.10, low[1], pz - 0.10), (px + 0.10, high[1] + 0.06, pz + 0.10))
        _slab(trim, (px - 0.20, low[1] - 0.04, pz - 0.20), (px + 0.20, low[1] + 0.03, pz + 0.20))
        if along_x:
            _slab(trim, (px - 0.26, low[1] - 0.04, pz - 0.05), (px + 0.26, low[1] + 0.03, pz + 0.05))
        else:
            _slab(trim, (px - 0.05, low[1] - 0.04, pz - 0.26), (px + 0.05, low[1] + 0.03, pz + 0.26))
    # The top rail, and a mid rail beneath it.
    for level, thickness in ((1.0, 0.05), (0.5, 0.035)):
        y = low[1] + (high[1] - low[1]) * level + 0.04
        if along_x:
            _slab(trim, (low[0] + 0.06, y, centre[2] - thickness),
                  (high[0] - 0.06, y + thickness * 1.6, centre[2] + thickness))
        else:
            _slab(trim, (centre[0] - thickness, y, low[2] + 0.06),
                  (centre[0] + thickness, y + thickness * 1.6, high[2] - 0.06))
    if high[1] - low[1] > 0.2:
        # Reflective plates, proud of the rail on both faces.
        for sign_z in (-1.0, 1.0):
            if along_x:
                _slab(lamp, (low[0] + 0.22, centre[1] - 0.06, centre[2] + sign_z * (size[2] * 0.5)),
                      (high[0] - 0.22, centre[1] + 0.06, centre[2] + sign_z * (size[2] * 0.5 + 0.035)))
            else:
                _slab(lamp, (centre[0] + sign_z * (size[0] * 0.5), centre[1] - 0.06, low[2] + 0.22),
                      (centre[0] + sign_z * (size[0] * 0.5 + 0.035), centre[1] + 0.06, high[2] - 0.22))
        _slab(lamp, (low[0], centre[1] - 0.05, low[2] - 0.03), (high[0], centre[1] + 0.05, high[2] + 0.03))
    # The linkage hook that joins this barrier to the next in the run.
    _bar(trim, (low[0], low[1], low[2]), (low[0], low[1], low[2]), 0.01)
    hook_x = high[0] if along_x else centre[0]
    hook_z = centre[2] if along_x else high[2]
    _bar(trim, (hook_x - 0.02, low[1] + 0.34, hook_z), (hook_x + 0.16, low[1] + 0.34, hook_z), 0.05)
    _bar(trim, (hook_x + 0.16, low[1] + 0.34, hook_z), (hook_x + 0.16, low[1] + 0.12, hook_z), 0.05)
    _bar(trim, (hook_x + 0.16, low[1] + 0.12, hook_z), (hook_x + 0.06, low[1] + 0.12, hook_z), 0.05)


def _prop_stall_canopy(parts, low, high, size, centre):
    """A pitched canopy over the slab, with ribs, a ridge and a hanging valance.

    The canopy is authored as one flat slab. This raises a ridge over it, ribs it
    at intervals, gives it an eave board along both pitches and hangs a scalloped
    valance from every edge, which is what makes a market stall read as a stall.
    """
    body, glass, trim, rubber, lamp = _parts(parts, "body", "glass", "trim", "rubber", "lamp")
    canvas = parts["canvas"]

    if size[0] < 1.2 or size[2] < 1.2 or size[1] > 0.6:
        return
    fabric = canvas if canvas is not None else body
    over = 0.38
    eave_y = high[1]
    ridge_y = high[1] + 0.58
    x0, x1 = low[0] - over, high[0] + over
    z0, z1 = low[2] - over, high[2] + over
    gable_prism(fabric, (x0, eave_y, z0), (x1, eave_y, z1), ridge_y, True)
    # Eave boards along both pitches and a ridge cap over the peak.
    for sign_z in (-1.0, 1.0):
        edge = z0 if sign_z < 0 else z1
        _slab(trim, (x0, eave_y - 0.10, edge - 0.05), (x1, eave_y + 0.02, edge + 0.05))
        # The valance: a hanging skirt, scalloped by a block per bay.
        bays = max(2, int((x1 - x0) // 0.55))
        for index in range(bays):
            a = x0 + (x1 - x0) * index / bays
            b = x0 + (x1 - x0) * (index + 1) / bays
            drop = 0.26 if index % 2 == 0 else 0.20
            _slab(fabric, (a + 0.01, eave_y - 0.10 - drop, edge - 0.03),
                  (b - 0.01, eave_y - 0.10, edge + 0.03))
            _slab(trim, (a + 0.01, eave_y - 0.12, edge - 0.035),
                  (b - 0.01, eave_y - 0.08, edge + 0.035))
    # The ribs: a slat under the fabric for every bay along the ridge.
    ribs = max(2, int((x1 - x0) // 0.62))
    for index in range(ribs + 1):
        x = x0 + (x1 - x0) * index / ribs
        for sign_z in (-1.0, 1.0):
            edge = z0 if sign_z < 0 else z1
            mid_z = (edge + centre[2]) * 0.5
            mid_y = (eave_y + ridge_y) * 0.5
            _bar(trim, (x, eave_y - 0.05, edge), (x, ridge_y - 0.03, centre[2]), 0.045)
            del mid_z, mid_y
    _slab(trim, (x0, ridge_y - 0.04, centre[2] - 0.07), (x1, ridge_y + 0.04, centre[2] + 0.07))


def _dish(mesh, centre, radius, depth):
    """A shallow reflector bowl, built as rings on a parabola opening away.

    A dish has to read as a curved surface from below, so the reflector is laid
    out as concentric rings whose height follows the parabola instead of as the
    flat quad the blockout gave it. The innermost ring is the apex, and it is
    fanned with single triangles rather than quads, because a quad spanning two
    rings that meet at a point emits a zero-area triangle per segment.
    """
    segments = 18
    rings = 4
    cx, cy, cz = centre
    apex_y = cy - depth * radius
    ring_points = []
    for ring in range(1, rings + 1):
        t = ring / rings
        r = radius * t
        y = cy - depth * radius * (1.0 - t * t)
        ring_points.append([(cx + r * math.cos(TAU * i / segments), y, cz + r * math.sin(TAU * i / segments))
                            for i in range(segments)])
    apex = (cx, apex_y, cz)
    first = ring_points[0]
    for index in range(segments):
        face(mesh, apex, first[(index + 1) % segments], first[index])
    for ring in range(len(ring_points) - 1):
        low_ring, high_ring = ring_points[ring], ring_points[ring + 1]
        for index in range(segments):
            follow = (index + 1) % segments
            face(mesh, low_ring[index], low_ring[follow], high_ring[follow], high_ring[index])


def _ring_dish(mesh, centre, radius, depth):
    """Concentric bands proud of a reflector, reading as its panel joints."""
    cx, cy, cz = centre
    for ring in (0.34, 0.62, 0.88):
        r = radius * ring
        y = cy - depth * radius * (1.0 - ring * ring) + 0.014
        cylinder(mesh, (cx, y, cz), 1, r, 0.028, 16)


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
    face(mesh, a0, a1, b1, b0)
    face(mesh, a2, a3, b3, b2)
    face(mesh, a1, a3, b3, b1)
    face(mesh, a0, a2, b2, b0)
    face(mesh, a2, a0, a1, a3)
    face(mesh, b0, b1, b3, b2)


def _parts(parts, *names):
    """Pulls the named meshes out of a prop's slot mapping, in order."""
    return tuple(parts[name] for name in names)


# The material and node-name suffix each prop slot uses. `prop_body`,
# `prop_trim`, `prop_rubber` and `prop_lamp` keep their original slot names,
# because `verify_maps.gd` requires those four suffixes to keep emitting
# geometry; the material key behind a slot is free to change.
PROP_SLOT_MATERIALS = {
    "body": ("prop_body", "ds_map_prop_body"),
    "glass": ("prop_glass", "ds_map_glass_dark"),
    "trim": ("prop_trim", "ds_map_prop_trim"),
    "rubber": ("prop_rubber", "ds_map_rubber"),
    "lamp": ("prop_lamp", "ds_map_lamp"),
    "canvas": ("prop_canvas", "ds_map_canvas"),
    "rail": ("prop_rail", "ds_map_rail"),
    "roof": ("prop_roof", "ds_map_roof"),
    # Corrugation, rails and door leaves of a shipping container are the painted
    # shell itself, so they land on the body slot; the castings are bare steel.
    "casting": ("prop_casting", "ds_map_container"),
    # Trunks and limbs are bark, kept off the toon foliage material.
    "bark": ("prop_bark", "ds_map_bark"),
}

PROP_SLOTS = ("body", "glass", "trim", "rubber", "lamp", "canvas", "rail", "roof",
              "casting", "bark")


PROP_RULES = {
    "car": [_prop_car],
    "crane": [_prop_crane],
    # A stall is authored as four posts plus a canopy slab, which the two rules
    # below distinguish by proportions.
    "stall": [_prop_stall, _prop_stall_canopy],
    "radar": [_prop_radar],
    "barrier": [_prop_barrier],
    # A container is authored as one plain box per lane, and a tree as an
    # instanced trunk plus an instanced canopy. Both are handled by their own
    # passes rather than by these rules, because both arrive rotated and scaled
    # and the detail has to be built in the box's own frame.
}


# --------------------------------------------------------------------------
# Containers and trees. Both families arrive as rotated, non-uniformly scaled
# instances, so their detail is built in the authored *local* frame of each
# part's own geometry and mapped out through the node matrix. Measuring in world
# space would be sheared by the instance's scale, and emitting untransformed
# would pile every copy on the origin; mapping local points through the matrix is
# exact for rotation, scale and translation alike.
# --------------------------------------------------------------------------

def _local_bounds(node, geometries):
    """The local-frame AABB of a node's own geometry."""
    positions = geometries[str(node["geometry"])]["positions"]
    if len(positions) < 12:
        return None
    low = [min(positions[axis::3]) for axis in range(3)]
    high = [max(positions[axis::3]) for axis in range(3)]
    return tuple(low), tuple(high)


def _map_box(mesh, matrix, low, high):
    """An axis-aligned box in the local frame, mapped out into world space.

    The corner order is `add_box`'s own, so a mapped box has exactly the topology
    an authored one has and is wound identically. The instance matrices all have
    a positive determinant — rotation and scale, never a mirror — so mapping
    preserves that winding; a mirrored matrix would invert every face.
    """
    x0, x1 = (low[0], high[0]) if low[0] <= high[0] else (high[0], low[0])
    y0, y1 = (low[1], high[1]) if low[1] <= high[1] else (high[1], low[1])
    z0, z1 = (low[2], high[2]) if low[2] <= high[2] else (high[2], low[2])
    p = [_transform(matrix, corner) for corner in (
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    )]
    face(mesh, p[0], p[3], p[2], p[1])       # -Z
    face(mesh, p[4], p[5], p[6], p[7])       # +Z
    face(mesh, p[1], p[2], p[6], p[5])       # +X
    face(mesh, p[3], p[0], p[4], p[7])       # -X
    face(mesh, p[2], p[3], p[7], p[6])       # +Y
    face(mesh, p[0], p[1], p[5], p[4])       # -Y


def _map_tube(mesh, matrix, start, end, radius, segments=8):
    """A cylinder between two points of the local frame, mapped into world space.

    The ring is built in local space and only then mapped, so the instance's own
    scale and rotation carry the cylinder with it instead of stretching it.
    """
    dx, dy, dz = end[0] - start[0], end[1] - start[1], end[2] - start[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-6:
        return
    w = (dx / length, dy / length, dz / length)
    reference = (0.0, 0.0, 1.0) if abs(w[2]) < 0.9 else (1.0, 0.0, 0.0)
    side = (reference[1] * w[2] - reference[2] * w[1],
            reference[2] * w[0] - reference[0] * w[2],
            reference[0] * w[1] - reference[1] * w[0])
    scale = math.sqrt(side[0] ** 2 + side[1] ** 2 + side[2] ** 2)
    u = (side[0] / scale, side[1] / scale, side[2] / scale)
    v = (w[1] * u[2] - w[2] * u[1], w[2] * u[0] - w[0] * u[2], w[0] * u[1] - w[1] * u[0])
    low = []
    high = []
    for index in range(segments):
        angle = TAU * index / segments
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for target, origin in ((low, start), (high, end)):
            target.append(_transform(matrix, (
                origin[0] + radius * (u[0] * cos_a + v[0] * sin_a),
                origin[1] + radius * (u[1] * cos_a + v[1] * sin_a),
                origin[2] + radius * (u[2] * cos_a + v[2] * sin_a),
            )))
    solid(mesh, low, high)


def _map_blob(mesh, matrix, centre, radii, segments=9, rings=5):
    """A squashed sphere in the local frame, mapped into world space.

    Both poles are fanned with single triangles. Winding quads up to a pole emits
    a zero-area triangle at every segment, which is exactly the kind of filler
    this pass must not add.
    """
    rows = []
    for ring in range(1, rings):
        phi = math.pi * ring / rings
        row = []
        for index in range(segments):
            angle = TAU * index / segments
            row.append(_transform(matrix, (
                centre[0] + radii[0] * math.sin(phi) * math.cos(angle),
                centre[1] + radii[1] * math.cos(phi),
                centre[2] - radii[2] * math.sin(phi) * math.sin(angle),
            )))
        rows.append(row)
    top = _transform(matrix, (centre[0], centre[1] + radii[1], centre[2]))
    bottom = _transform(matrix, (centre[0], centre[1] - radii[1], centre[2]))
    for index in range(segments):
        follow = (index + 1) % segments
        face(mesh, top, rows[0][index], rows[0][follow])
        face(mesh, bottom, rows[-1][follow], rows[-1][index])
    for row in range(len(rows) - 1):
        near, far = rows[row], rows[row + 1]
        for index in range(segments):
            follow = (index + 1) % segments
            face(mesh, near[follow], near[index], far[index], far[follow])


def _container_detail(data, map_id, material_index):
    """Corrugation, rails, corner castings and door hardware on the containers.

    The dock lanes author each container as a plain box, which is why they render
    as flat coloured blocks. This gives every one the features that make it read
    as an ISO container: vertical ribs at a real pitch proud of the shell, the
    top and bottom rails the ribs die into, the eight corner castings — a
    container's most recognisable detail, with the twistlock slot through each —
    double end doors with locking bars, cam keepers and hinges, and the painted
    stencil block.
    """
    geometries = data["geometries"]
    body = Mesh()
    trim = Mesh()
    casting = Mesh()
    stencil = Mesh()
    made = 0
    for node in list(data["nodes"]):
        name = str(node.get("name", ""))
        if name.startswith("detail_") or node.get("geometry") is None:
            continue
        if "container" not in name.lower() and name not in CONTAINER_NAMES:
            continue
        # Classified on the geometry's own extents, because a container is
        # distinguished by its proportions and not by what it is called.
        bounds = _local_bounds(node, geometries)
        if bounds is None:
            continue
        local_low, local_high = bounds
        size = [local_high[axis] - local_low[axis] for axis in range(3)]
        if min(size) < CONTAINER_MIN_SIDE or max(size) > CONTAINER_MAX_LENGTH:
            continue
        if max(size) < CONTAINER_MIN_LENGTH:
            continue
        made += 1
        _container_frame(body, trim, casting, stencil, node, local_low, local_high)

    return made + _emit(data, map_id, material_index, (
        (body, "ds_map_container_shell", "ds_map_prop_body"),
        (trim, "ds_map_container_trim", "ds_map_prop_trim"),
        (casting, "ds_map_container_casting", "ds_map_container"),
        (stencil, "ds_map_container_stencil", "ds_map_lamp")))


def _container_frame(body, trim, casting, stencil, node, local_low, local_high):
    """Builds one container's detail in its own authored local frame."""
    matrix = node["matrix"]
    low, high = list(local_low), list(local_high)
    size = [high[axis] - low[axis] for axis in range(3)]
    # The length runs along whichever local axis is longest; a container is about
    # 6 m by 2.6 m by 2.6 m, so this is unambiguous from the extents alone.
    long_axis = 0 if size[0] >= size[2] else 2
    across_axis = 2 if long_axis == 0 else 0
    length = size[long_axis] * 0.5
    breadth = size[across_axis] * 0.5
    middle_along = (low[long_axis] + high[long_axis]) * 0.5
    middle_across = (low[across_axis] + high[across_axis]) * 0.5
    top, bottom = high[1], low[1]

    def place(along, height, across):
        point = [0.0, height, 0.0]
        point[long_axis] = along
        point[across_axis] = across
        return point

    # Ribs: vertical, on both long faces, at about a 0.30 m pitch, each a pair of
    # proud faces so the section has a nose rather than a flat plate.
    pitch = 0.30
    count = max(4, int(size[long_axis] // pitch))
    step = size[long_axis] / count
    for index in range(count):
        along = low[long_axis] + step * (index + 0.5)
        for side in (-1.0, 1.0):
            face_centre = middle_across + side * breadth
            near = [0.0, 0.0, 0.0]
            near[long_axis] = along - step * 0.30
            far = [0.0, 0.0, 0.0]
            far[long_axis] = along + step * 0.30
            inner = [0.0, 0.0, 0.0]
            inner[across_axis] = face_centre + side * 0.035
            outer = [0.0, 0.0, 0.0]
            outer[across_axis] = face_centre + side * 0.075
            box_low = [0.0, bottom + 0.20, 0.0]
            box_high = [0.0, top - 0.20, 0.0]
            box_low[long_axis], box_high[long_axis] = near[long_axis], far[long_axis]
            box_low[across_axis] = min(inner[across_axis], outer[across_axis])
            box_high[across_axis] = max(inner[across_axis], outer[across_axis])
            _map_box(body, matrix, box_low, box_high)

    # The top and bottom rails the ribs die into, on both long faces.
    for height in (bottom + 0.12, top - 0.12):
        for side in (-1.0, 1.0):
            face_centre = middle_across + side * breadth
            box_low = [0.0, height - 0.11, 0.0]
            box_high = [0.0, height + 0.11, 0.0]
            box_low[long_axis], box_high[long_axis] = low[long_axis] - 0.02, high[long_axis] + 0.02
            a = face_centre + side * 0.04
            b = face_centre + side * 0.09
            box_low[across_axis], box_high[across_axis] = min(a, b), max(a, b)
            _map_box(trim, matrix, box_low, box_high)

    # The eight corner castings, each with its twistlock slot through the outer
    # face. These are what a crane actually grabs, so they are modelled proud on
    # all three axes.
    half_casting = CONTAINER_CASTING * 0.5
    for end_along in (low[long_axis], high[long_axis]):
        for across in (middle_across - breadth, middle_across + breadth):
            for height in (bottom, top):
                centre = place(end_along, height, across)
                _map_box(casting, matrix,
                         [centre[i] - half_casting for i in range(3)],
                         [centre[i] + half_casting for i in range(3)])
                away = 1.0 if across > middle_across else -1.0
                slot_low = place(end_along, height - 0.05,
                                 across + away * (half_casting - 0.04))
                slot_high = place(end_along, height + 0.05, across + away * half_casting)
                slot_low[long_axis] = min(end_along, end_along + (0.08 if end_along > middle_along else -0.08))
                slot_high[long_axis] = max(end_along, end_along + (0.08 if end_along > middle_along else -0.08))
                _map_box(trim, matrix,
                         [min(slot_low[i], slot_high[i]) for i in range(3)],
                         [max(slot_low[i], slot_high[i]) for i in range(3)])

    # Double end doors: a leaf pair per end, each with two vertical locking bars
    # carrying a cam keeper top and bottom, plus hinges on the outer edge.
    for end_along, outward in ((low[long_axis], -1.0), (high[long_axis], 1.0)):
        for side in (-1.0, 1.0):
            for bar in range(2):
                across = middle_across + side * breadth * (0.34 + bar * 0.32)
                near = end_along + outward * 0.03
                far = end_along + outward * 0.09
                start = place(near, bottom + 0.30, across)
                end = place(far, top - 0.30, across)
                _map_tube(trim, matrix, start, end, 0.032, 8)
                for height, upper in ((top - 0.34, True), (bottom + 0.36, False)):
                    keeper_low = place(min(near, far), height - 0.05, across - 0.055)
                    keeper_high = place(max(near, far), height + 0.05, across + 0.055)
                    _map_box(casting, matrix,
                             [min(keeper_low[i], keeper_high[i]) for i in range(3)],
                             [max(keeper_low[i], keeper_high[i]) for i in range(3)])
                    del upper
            # The centre post between the two leaves.
            post_low = place(min(end_along + outward * 0.02, end_along + outward * 0.06),
                             bottom + 0.30, middle_across - 0.035)
            post_high = place(max(end_along + outward * 0.02, end_along + outward * 0.06),
                              top - 0.30, middle_across + 0.035)
            _map_box(trim, matrix, post_low, post_high)
            # Hinges down the outer edge of the leaf.
            for hinge in range(3):
                height = bottom + 0.55 + hinge * (top - bottom - 1.10) * 0.5
                hinge_low = place(min(end_along + outward * 0.02, end_along + outward * 0.10),
                                  height - 0.07, middle_across + side * breadth * 0.90)
                hinge_high = place(max(end_along + outward * 0.02, end_along + outward * 0.10),
                                   height + 0.07, middle_across + side * breadth * 0.99)
                _map_box(casting, matrix, hinge_low, hinge_high)

    # The painted stencil block: the ISO and serial markings every container has.
    for side in (-1.0, 1.0):
        band = [0.0, 0.0, 0.0]
        band[across_axis] = middle_across + side * (breadth + 0.055)
        band_high = list(band)
        band_high[across_axis] = middle_across + side * (breadth + 0.085)
        for along_fraction, height_fraction in ((-0.20, 0.62), (0.60, 0.30)):
            stencil_low = place(low[long_axis] + size[long_axis] * (along_fraction + 0.5 - 0.16),
                                bottom + (top - bottom) * height_fraction, 0.0)
            stencil_high = place(low[long_axis] + size[long_axis] * (along_fraction + 0.5 + 0.16),
                                 bottom + (top - bottom) * height_fraction + 0.20, 0.0)
            for point in (stencil_low, stencil_high):
                point[across_axis] = band[across_axis]
                if point is stencil_high:
                    point[across_axis] = band_high[across_axis]
            stencil_low[across_axis] = min(band[across_axis], band_high[across_axis])
            stencil_high[across_axis] = max(band[across_axis], band_high[across_axis])
            _map_box(stencil, matrix, stencil_low, stencil_high)


def _tree_detail(data, map_id, material_index):
    """Trunk flare, limb levels and canopy lobes on every authored tree.

    A tree is authored as an instanced trunk part and an instanced canopy part:
    the desert canopy is a squashed sphere and the facility's are plain boxes,
    which is why they read as green balls on invisible stems. Each trunk gets a
    root flare, a tapered shaft and two levels of forking limbs, and each canopy
    gets overlapping lobes that fully enclose the authored volume, so its faceted
    silhouette is no longer readable through them. Both are built in the local
    frame of the part's own geometry, so a scaled or rotated instance carries its
    detail correctly.

    The lobes go into their own mesh on the canopy material, because leaf mass
    and bark are different surfaces: shading the lobes as bark reads as dark
    woody blotches on a green ball, and shading branches as metal trim reads as
    reflective rods. The limbs therefore share the trunk's bark.
    """
    geometries = data["geometries"]
    bark = Mesh()
    canopy = Mesh()
    trunk_count = 0
    canopy_count = 0
    for node in list(data["nodes"]):
        name = str(node.get("name", ""))
        if name.startswith("detail_") or node.get("geometry") is None:
            continue
        if not name.startswith(TREE_PREFIXES):
            continue
        bounds = _local_bounds(node, geometries)
        if bounds is None:
            continue
        local_low, local_high = bounds
        size = [local_high[axis] - local_low[axis] for axis in range(3)]
        if max(size) < 0.05:
            continue
        # A trunk is the slim, tall part; the canopy is the wide volume above it.
        if max(size[0], size[2]) <= TRUNK_SPAN and size[1] > 0.8:
            trunk_count += 1
            _trunk_detail(bark, node, local_low, local_high)
        elif min(size) > TRUNK_SPAN:
            canopy_count += 1
            _canopy_detail(canopy, node, local_low, local_high)

    return trunk_count, canopy_count, _emit(data, map_id, material_index, (
        (bark, "ds_map_tree_bark", "ds_map_bark"),
        (canopy, "ds_map_tree_canopy", "ds_map_canopy")))


def _trunk_detail(bark, node, local_low, local_high):
    """A tapered trunk with a root flare and two forking levels of limbs."""
    matrix = node["matrix"]
    base = local_low[1]
    top = local_high[1]
    height = top - base
    radius = max(local_high[0] - local_low[0], local_high[2] - local_low[2]) * 0.5
    centre_x = (local_low[0] + local_high[0]) * 0.5
    centre_z = (local_low[2] + local_high[2]) * 0.5
    # The shaft, as four tapering courses rather than one prism, so the taper is
    # visible and each course reads as a separate run of bark.
    courses = 4
    for index in range(courses):
        low_y = base + height * index / courses
        high_y = base + height * (index + 1) / courses
        taper_low = radius * (1.14 - 0.21 * index)
        taper_high = radius * (1.14 - 0.21 * (index + 1))
        _map_stack(bark, matrix, (centre_x, centre_z), low_y, high_y, taper_low, taper_high, 10)
    # A root flare: four buttresses splaying out onto the ground, which is what
    # stops the trunk meeting the terrain as a cut cylinder.
    for index in range(4):
        angle = TAU * (index + 0.5) / 4.0
        _map_tube(bark, matrix,
                  (centre_x + math.cos(angle) * radius * 0.7, base + 0.02,
                   centre_z + math.sin(angle) * radius * 0.7),
                  (centre_x + math.cos(angle) * radius * 2.6, base + height * 0.20,
                   centre_z + math.sin(angle) * radius * 2.6),
                  radius * 0.44, 7)
    # Two levels of limbs, each forking into a secondary twig. Both are bark: a
    # branch is wood, not metal trim.
    for level, (fraction, spread, count) in enumerate(((0.45, 1.20, 3), (0.72, 0.92, 2))):
        base_y = base + height * fraction
        for index in range(count):
            angle = TAU * (index + 0.5 * level) / count
            tip = (centre_x + math.cos(angle) * radius * (1.9 + spread),
                   base_y + height * 0.26,
                   centre_z + math.sin(angle) * radius * (1.9 + spread))
            _map_tube(bark, matrix, (centre_x, base_y, centre_z), tip, radius * 0.42, 7)
            fork = (tip[0] * 0.55 + centre_x * 0.45 + math.cos(angle + 0.9) * radius * 1.2,
                    tip[1] + height * 0.14,
                    tip[2] * 0.55 + centre_z * 0.45 + math.sin(angle + 0.9) * radius * 1.2)
            _map_tube(bark, matrix, tip, fork, radius * 0.17, 6)


def _canopy_detail(canopy, node, local_low, local_high):
    """Leaf lobes that enclose the authored canopy volume, whatever shape it is.

    The authored canopy is a primitive — a squashed sphere in the desert, a
    box-like polyhedron and spheres in the facility, spheres on the docks — and it
    stays in the map untouched, so the lobes have to *hide* it. One lobe sits just
    inside each of the eight corners of the authored AABB, sized by the constants
    above; that layout covers the whole canopy volume, so no authored facet can
    show through on any of the shapes.

    Enclosure is a property of the analytic ellipsoids, so it is checked
    analytically: for every authored canopy vertex, the normalised distance
    `sqrt(sum(((v - centre) / radius)^2))` to its nearest lobe must stay under the
    target. Never through rasterised triangles — overlapping lobes make a
    crossing-count even and would report a covered point as uncovered.
    """
    matrix = node["matrix"]
    centre = [(local_low[axis] + local_high[axis]) * 0.5 for axis in range(3)]
    radii = [(local_high[axis] - local_low[axis]) * 0.5 for axis in range(3)]
    if min(radii) < CANOPY_MIN_HALF_EXTENT:
        return
    reach = tuple(radius * CANOPY_LOBES_RADIUS for radius in radii)
    for sign_x in (-1.0, 1.0):
        for sign_y in (-1.0, 1.0):
            for sign_z in (-1.0, 1.0):
                # Each lobe sits `CANOPY_LOBES_OFFSET` of the half-extent in from
                # the centre along its own corner's direction, so the eight overlap
                # through the middle of the canopy and seal the faces between them.
                lobe_centre = (centre[0] + radii[0] * sign_x * CANOPY_LOBES_OFFSET,
                               centre[1] + radii[1] * sign_y * CANOPY_LOBES_OFFSET,
                               centre[2] + radii[2] * sign_z * CANOPY_LOBES_OFFSET)
                _map_blob(canopy, matrix, lobe_centre, reach,
                          CANOPY_LOBES_SEGMENTS, CANOPY_LOBES_RINGS)


def _map_stack(mesh, matrix, centre_xz, low_y, high_y, radius_low, radius_high, segments):
    """A tapering drum between two heights of the local frame, mapped out."""
    low = []
    high = []
    for index in range(segments):
        angle = TAU * index / segments
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        low.append(_transform(matrix, (centre_xz[0] + radius_low * cos_a, low_y,
                                       centre_xz[1] - radius_low * sin_a)))
        high.append(_transform(matrix, (centre_xz[0] + radius_high * cos_a, high_y,
                                        centre_xz[1] - radius_high * sin_a)))
    solid(mesh, low, high)


def _arch(mesh, centre, radius, sign_z, depth):
    """A wheel arch: a band over the authored wheel, facing radially outward.

    The band stands on the wheel's own axis, so the face that should be seen is
    the curved outer one. Which corner order puts it out depends on which side of
    the car the arch is on, because the far edge of the band is offset along
    `sign_z`; the order is chosen from that sign rather than fixed, so the arch is
    not culled away from outside on the left-hand wheels.
    """
    segments = 12
    cx, cy, cz = centre
    thickness = 0.05
    inner = radius * 0.94
    outer = radius + thickness
    near_z = cz + sign_z * depth * 0.5
    far_z = cz + sign_z * (depth * 0.5 + 0.06)
    for index in range(segments):
        a0 = math.pi * (index / segments)
        a1 = math.pi * ((index + 1) / segments)
        inner_a0 = (cx + inner * math.cos(a0), cy + inner * math.sin(a0), near_z)
        inner_a1 = (cx + inner * math.cos(a1), cy + inner * math.sin(a1), near_z)
        outer_a1 = (cx + outer * math.cos(a1), cy + outer * math.sin(a1), far_z)
        outer_a0 = (cx + outer * math.cos(a0), cy + outer * math.sin(a0), far_z)
        if sign_z > 0:
            face(mesh, inner_a0, inner_a1, outer_a1, outer_a0)
        else:
            face(mesh, outer_a0, outer_a1, inner_a1, inner_a0)



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
