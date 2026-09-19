"""High-detail soldier models for DeadShot.

The ported characters were 2728 triangles of boxes and spheres: a 40 cm cube for
a head, capsule limbs, no kit. This builds a properly proportioned 1.86 m
soldier with a sculpted torso, plate carrier, webbing and pouches, helmet with a
chin strap and accessory mounts, goggles, gloved hands, knee pads and boots.

Pivot contract is preserved exactly, because gameplay code animates it:

  hips        (0, 0.9, 0)        child of root
  head        (0, 0.88, 0)       child of hips
  face        (0, 0, 0)          child of head
  headband    (0, 0.04, 0)       child of face   - team-coloured helmet band
  left_arm    (-0.33, 0.5, 0)    child of hips
  right_arm   (0.33, 0.5, 0)     child of hips
  left_leg    (-0.13, 0, 0)      child of hips
  right_leg   (0.13, 0, 0)       child of hips

`VisualFactory.animate_human` rotates the four limb pivots about X and Z and
translates `hips` on Y, so each limb is one rigid group hanging from its pivot.
"""

from __future__ import annotations

from deadshot_detail import (
    Builder, box, cone, extrude, lerp3, profile_circle, profile_rounded_rect,
    profile_taper, rounded_box, slab, sweep, swept_tube, tube, vadd, vmul, vnorm,
)

HALF_PI = 1.5707963267948966

MATERIALS = {
    "ds_uniform": {
        "name": "ds_uniform", "color": [0.098, 0.104, 0.086], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "camo",
    },
    "ds_vest": {
        "name": "ds_vest", "color": [0.058, 0.062, 0.056], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "cloth",
    },
    "ds_gear": {
        "name": "ds_gear", "color": [0.042, 0.044, 0.040], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "cloth",
    },
    "ds_skin": {
        "name": "ds_skin", "color": [0.42, 0.30, 0.22], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "skin",
    },
    "ds_boot": {
        "name": "ds_boot", "color": [0.030, 0.029, 0.027], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "rubber",
    },
    "ds_helmet": {
        "name": "ds_helmet", "color": [0.070, 0.074, 0.066], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "painted_metal",
    },
    "ds_glove": {
        "name": "ds_glove", "color": [0.035, 0.036, 0.033], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "cloth",
    },
    "ds_team": {
        "name": "ds_team", "color": [0.04, 0.24, 1.0], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "team",
        "surface": "cloth",
    },
    "ds_glass": {
        "name": "ds_glass", "color": [0.10, 0.13, 0.12], "emissive": [0.01, 0.02, 0.02],
        "opacity": 0.55, "transparent": True, "doubleSide": True, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "glass",
    },
    "ds_metal_dark": {
        "name": "ds_metal_dark", "color": [0.080, 0.082, 0.086], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "metal",
    },
}

HIPS_Y = 0.9
HEAD_Y = 0.88
# The arm pivot sits inboard of the torso's widest point so the deltoid overlaps
# the chest instead of hanging beside it with a visible seam.
ARM_X = 0.255
ARM_Y = 0.5
LEG_X = 0.13


# --------------------------------------------------------------------------
# Torso. Built directly in hips-local space, so it needs no extra pivot.
# --------------------------------------------------------------------------

def build_torso():
    body = Builder()
    # Pelvis -> waist -> chest -> shoulders, as a swept stack of rounded
    # rectangles. Real soldiers taper at the waist and widen at the shoulders.
    stations = [
        (-0.02, 0.150, 0.098, 0.020),   # pelvis
        (0.06, 0.158, 0.104, 0.020),
        (0.16, 0.150, 0.100, 0.022),    # waist
        (0.28, 0.172, 0.112, 0.024),
        (0.40, 0.205, 0.128, 0.026),    # chest
        (0.52, 0.225, 0.132, 0.028),
        (0.60, 0.230, 0.126, 0.028),    # shoulders
        (0.66, 0.180, 0.108, 0.026),
    ]
    frames = []
    for y, half_x, half_z, radius in stations:
        frames.append(((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), half_x),
                       vmul((0.0, 0.0, 1.0), half_z), (0.0, 1.0, 0.0)))
    sweep(body, profile_rounded_rect(1.0, 1.0, 0.30, 4), frames, True, True)
    # Collar and neck.
    tube(body, (0.0, 0.60, -0.004), (0.0, 0.74, -0.006), 0.062, 14, steps=2)
    tube(body, (0.0, 0.58, -0.004), (0.0, 0.62, -0.004), 0.078, 16)
    return [("torso", "ds_uniform", body)]


def build_vest():
    """Plate carrier front and back, cummerbund, pouches, belt and straps."""
    vest = Builder()
    # Front plate: a rounded slab hugging the chest.
    front = profile_rounded_rect(0.168, 0.155, 0.030, 4)
    extrude(vest, front, 0.0, 0.040, origin=(0.0, 0.40, -0.118),
            u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, -1.0))
    # Back plate.
    extrude(vest, profile_rounded_rect(0.160, 0.150, 0.028, 4), 0.0, 0.038,
            origin=(0.0, 0.40, 0.108), u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0),
            w=(0.0, 0.0, 1.0))
    # Cummerbund wrapping the sides.
    for side in (-1.0, 1.0):
        extrude(vest, profile_rounded_rect(0.056, 0.120, 0.022, 3), 0.0, 0.022,
                origin=(side * 0.176, 0.40, 0.0), u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0),
                w=(side, 0.0, 0.0))
    # Three rifle magazine pouches across the front.
    for index in range(3):
        x = (index - 1) * 0.082
        rounded_box(vest, (x, 0.318, -0.150), (0.074, 0.128, 0.052), 0.010, corner_segments=3)
        # Flap and buckle.
        rounded_box(vest, (x, 0.382, -0.150), (0.076, 0.034, 0.056), 0.010, corner_segments=3)
        box(vest, (x, 0.362, -0.178), (0.020, 0.014, 0.008))
    # Utility pouch and radio on the cummerbund.
    rounded_box(vest, (0.196, 0.362, -0.040), (0.048, 0.086, 0.070), 0.010, corner_segments=3)
    rounded_box(vest, (-0.198, 0.372, -0.030), (0.044, 0.106, 0.062), 0.010, corner_segments=3)
    tube(vest, (-0.198, 0.436, -0.030), (-0.198, 0.470, -0.030), 0.0040, 8)
    # Shoulder straps.
    for side in (-1.0, 1.0):
        swept_tube(vest, [
            (side * 0.108, 0.508, -0.104),
            (side * 0.126, 0.560, -0.070),
            (side * 0.118, 0.590, 0.000),
            (side * 0.122, 0.560, 0.070),
            (side * 0.104, 0.508, 0.096),
        ], 0.022, 8)
    # Belt with a buckle and side pouches.
    belt = Builder()
    sweep(belt, profile_rounded_rect(0.166, 0.112, 0.024, 4),
          [((0.0, 0.132, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
           ((0.0, 0.160, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0))],
          True, True)
    box(belt, (0.0, 0.146, -0.118), (0.048, 0.034, 0.014))
    rounded_box(belt, (0.150, 0.140, 0.020), (0.056, 0.070, 0.052), 0.010, corner_segments=3)
    rounded_box(belt, (-0.150, 0.140, 0.020), (0.056, 0.070, 0.052), 0.010, corner_segments=3)
    return [("vest", "ds_vest", vest), ("belt", "ds_gear", belt)]


def build_pack():
    """Hydration pack on the back, with a drinking tube over the shoulder."""
    pack = Builder()
    rounded_box(pack, (0.0, 0.360, 0.176), (0.180, 0.240, 0.086), 0.018, corner_segments=3)
    rounded_box(pack, (0.0, 0.300, 0.226), (0.140, 0.110, 0.036), 0.012, corner_segments=3)
    for index in range(3):
        box(pack, (0.0, 0.430 - index * 0.040, 0.222), (0.150, 0.008, 0.010))
    swept_tube(pack, [
        (0.070, 0.470, 0.182),
        (0.098, 0.540, 0.140),
        (0.104, 0.566, 0.060),
        (0.096, 0.540, -0.020),
    ], 0.0065, 8)
    return [("pack", "ds_gear", pack)]


# --------------------------------------------------------------------------
# Head. Built in head-local space; the head pivot sits at hips-local 0.88, so
# the skull is centred slightly below it and the neck continues down to the
# collar at hips-local 0.74.
# --------------------------------------------------------------------------

def build_head():
    head = Builder()
    # Neck from the collar up into the skull.
    tube(head, (0.0, -0.22, -0.004), (0.0, -0.10, -0.008), 0.058, 14, steps=3)
    # Skull: an ellipsoid swept as a stack of circles.
    skull_stations = [
        (-0.200, 0.062, 0.070),
        (-0.160, 0.082, 0.092),
        (-0.120, 0.090, 0.100),
        (-0.080, 0.094, 0.104),
        (-0.040, 0.092, 0.102),
        (0.000, 0.082, 0.092),
        (0.030, 0.062, 0.070),
    ]
    frames = []
    for y, rx, rz in skull_stations:
        frames.append(((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), rx), vmul((0.0, 0.0, 1.0), rz),
                       (0.0, 1.0, 0.0)))
    sweep(head, profile_circle(1.0, 18), frames, True, True)
    # Brow ridge and cheekbones.
    for side in (-1.0, 1.0):
        rounded_box(head, (side * 0.056, -0.056, -0.082), (0.048, 0.030, 0.034), 0.010, corner_segments=3)
    rounded_box(head, (0.0, -0.052, -0.092), (0.120, 0.026, 0.026), 0.010, corner_segments=3)
    # Jaw and chin.
    rounded_box(head, (0.0, -0.168, -0.046), (0.116, 0.056, 0.088), 0.020, corner_segments=3)
    rounded_box(head, (0.0, -0.196, -0.070), (0.070, 0.030, 0.046), 0.012, corner_segments=3)
    # Ears.
    for side in (-1.0, 1.0):
        rounded_box(head, (side * 0.092, -0.098, 0.000), (0.020, 0.048, 0.030), 0.008, corner_segments=3)
    return [("skull", "ds_skin", head)]


def build_helmet():
    """Ballistic helmet with rim, NVG mount and chin strap. Sits over the skull."""
    shell = Builder()
    shell_stations = [
        (-0.118, 0.106, 0.118),
        (-0.086, 0.116, 0.128),
        (-0.046, 0.118, 0.130),
        (-0.006, 0.110, 0.122),
        (0.028, 0.090, 0.100),
        (0.048, 0.058, 0.064),
    ]
    frames = []
    for y, rx, rz in shell_stations:
        frames.append(((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), rx), vmul((0.0, 0.0, 1.0), rz),
                       (0.0, 1.0, 0.0)))
    # Open at the bottom so the face reads through.
    sweep(shell, profile_circle(1.0, 22), frames, False, True)
    # Rounded rim over the brow.
    rim_frames = [((0.0, -0.120, 0.0), vmul((1.0, 0.0, 0.0), 0.108), vmul((0.0, 0.0, 1.0), 0.120), (0.0, 1.0, 0.0)),
                  ((0.0, -0.140, 0.0), vmul((1.0, 0.0, 0.0), 0.104), vmul((0.0, 0.0, 1.0), 0.116), (0.0, 1.0, 0.0))]
    sweep(shell, profile_circle(1.0, 22), rim_frames, True, True)
    # Side rails and vent holes.
    for side in (-1.0, 1.0):
        rounded_box(shell, (side * 0.112, -0.060, 0.010), (0.014, 0.070, 0.150), 0.006, corner_segments=3)
    for index in range(4):
        rounded_box(shell, (0.0, 0.036, -0.030 + index * 0.024), (0.052, 0.010, 0.014), 0.004)
    return [("helmet", "ds_helmet", shell)]


def build_helmet_gear():
    """NVG shroud, mount arm, and the chin strap."""
    gear = Builder()
    rounded_box(gear, (0.0, -0.052, -0.134), (0.060, 0.048, 0.026), 0.008, corner_segments=3)
    rounded_box(gear, (0.0, 0.000, -0.166), (0.030, 0.062, 0.030), 0.008, corner_segments=3)
    box(gear, (0.0, -0.030, -0.186), (0.044, 0.016, 0.014))
    # Chin straps down both sides plus the buckle.
    for side in (-1.0, 1.0):
        swept_tube(gear, [
            (side * 0.086, -0.126, -0.010),
            (side * 0.078, -0.180, -0.040),
            (side * 0.048, -0.212, -0.052),
            (0.0, -0.222, -0.050),
        ], 0.0085, 8)
    return [("helmetgear", "ds_gear", gear)]


def build_face():
    """Goggles over the eyes, nose, mouth line and a beard shadow."""
    face = Builder()
    # Nose.
    rounded_box(face, (0.0, -0.108, -0.108), (0.030, 0.062, 0.042), 0.010, corner_segments=3)
    # Brow and cheek planes are part of the skull; add the mouth and eye sockets.
    box(face, (0.0, -0.176, -0.098), (0.052, 0.010, 0.014))
    for side in (-1.0, 1.0):
        rounded_box(face, (side * 0.040, -0.096, -0.100), (0.036, 0.024, 0.020), 0.008, corner_segments=3)
    return [("face_detail", "ds_skin", face)]


def build_goggles():
    """Ballistic goggles: frame band, two lenses and a strap round the helmet."""
    goggles = Builder()
    for side in (-1.0, 1.0):
        rounded_box(goggles, (side * 0.046, -0.098, -0.128), (0.072, 0.048, 0.026), 0.012, corner_segments=3)
    rounded_box(goggles, (0.0, -0.098, -0.134), (0.030, 0.044, 0.020), 0.008, corner_segments=3)
    swept_tube(goggles, [
        (-0.104, -0.086, -0.020),
        (-0.114, -0.058, 0.040),
        (-0.100, -0.040, 0.096),
        (0.0, -0.032, 0.124),
        (0.100, -0.040, 0.096),
        (0.114, -0.058, 0.040),
        (0.104, -0.086, -0.020),
    ], 0.0095, 8)
    parts = [("goggles", "ds_gear", goggles)]
    lens = Builder()
    for side in (-1.0, 1.0):
        rounded_box(lens, (side * 0.046, -0.098, -0.140), (0.062, 0.038, 0.012), 0.010, corner_segments=3)
    parts.append(("goggle_lens", "ds_glass", lens))
    return parts


def build_headband():
    """Team-coloured helmet band. The primary at-a-glance team identifier."""
    band = Builder()
    frames = [((0.0, -0.010, 0.0), vmul((1.0, 0.0, 0.0), 0.1215), vmul((0.0, 0.0, 1.0), 0.1335), (0.0, 1.0, 0.0)),
              ((0.0, 0.026, 0.0), vmul((1.0, 0.0, 0.0), 0.1185), vmul((0.0, 0.0, 1.0), 0.1305), (0.0, 1.0, 0.0))]
    sweep(band, profile_circle(1.0, 22), frames, True, True)
    return [("band", "ds_team", band)]


def build_patch():
    """Shoulder and chest team patches plus the rank tab."""
    patch = Builder()
    for side in (-1.0, 1.0):
        rounded_box(patch, (side * 0.238, 0.500, 0.0), (0.016, 0.062, 0.062), 0.008, corner_segments=3)
    rounded_box(patch, (0.096, 0.436, -0.146), (0.048, 0.030, 0.014), 0.006, corner_segments=3)
    return [("patch", "ds_team", patch)]


# --------------------------------------------------------------------------
# Arms. One rigid group per pivot, hanging down from hips-local y = +0.5, so
# `animate_human`'s X/Z rotations swing the whole arm from the shoulder.
# --------------------------------------------------------------------------

def build_arm():
    arm = Builder()
    # Shoulder / deltoid, widening then narrowing into the upper arm.
    shoulder = [(0.030, 0.062), (0.010, 0.086), (-0.030, 0.092), (-0.076, 0.078)]
    frames = [((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), r), vmul((0.0, 0.0, 1.0), r * 0.94), (0.0, 1.0, 0.0))
              for y, r in shoulder]
    sweep(arm, profile_circle(1.0, 16), frames, True, False)
    # Upper arm down to the elbow.
    tube(arm, (0.0, -0.070, 0.0), (0.0, -0.300, 0.004), 0.058, 16, radius_end=0.052, steps=3)
    # Elbow pad.
    rounded_box(arm, (0.0, -0.312, 0.010), (0.088, 0.062, 0.086), 0.020, corner_segments=3)
    # Forearm.
    tube(arm, (0.0, -0.322, 0.004), (0.0, -0.580, 0.010), 0.050, 16, radius_end=0.044, steps=3)
    # Wrist and gloved hand, curled as if gripping.
    tube(arm, (0.0, -0.586, 0.010), (0.0, -0.628, 0.012), 0.040, 14, steps=2)
    rounded_box(arm, (0.0, -0.666, 0.004), (0.072, 0.086, 0.094), 0.020, corner_segments=3)
    # Thumb.
    tube(arm, (0.030, -0.640, -0.038), (0.044, -0.664, -0.052), 0.017, 10)
    return arm


def build_leg():
    leg = Builder()
    # Hip / upper thigh.
    frames = [((0.0, 0.026, 0.0), vmul((1.0, 0.0, 0.0), 0.092), vmul((0.0, 0.0, 1.0), 0.098), (0.0, 1.0, 0.0)),
              ((0.0, -0.060, 0.0), vmul((1.0, 0.0, 0.0), 0.090), vmul((0.0, 0.0, 1.0), 0.094), (0.0, 1.0, 0.0))]
    sweep(leg, profile_circle(1.0, 16), frames, True, False)
    # Thigh.
    tube(leg, (0.0, -0.050, 0.0), (0.0, -0.400, 0.004), 0.090, 16, radius_end=0.074, steps=3)
    # Knee pad.
    rounded_box(leg, (0.0, -0.430, -0.014), (0.116, 0.106, 0.100), 0.024, corner_segments=3)
    # Calf, tapering to the ankle.
    tube(leg, (0.0, -0.440, 0.004), (0.0, -0.800, 0.008), 0.076, 16, radius_end=0.050, steps=3)
    # Boot: ankle cuff, upper, sole and toe.
    tube(leg, (0.0, -0.798, 0.008), (0.0, -0.856, 0.006), 0.062, 14, radius_end=0.058, steps=2)
    rounded_box(leg, (0.0, -0.872, 0.010), (0.104, 0.056, 0.196), 0.022, corner_segments=3)
    rounded_box(leg, (0.0, -0.912, 0.020), (0.108, 0.030, 0.230), 0.024, corner_segments=3)
    rounded_box(leg, (0.0, -0.928, 0.026), (0.100, 0.018, 0.220), 0.016, corner_segments=3)
    # Laces.
    for index in range(4):
        box(leg, (0.0, -0.860 + index * 0.020, -0.078 + index * 0.004), (0.070, 0.006, 0.010))
    return leg


# --------------------------------------------------------------------------
# Assembly.
# --------------------------------------------------------------------------

PIVOTS = {
    # name: (x, y, z, parent pivot name)
    "hips": (0.0, HIPS_Y, 0.0, None),
    "head": (0.0, HEAD_Y, 0.0, "hips"),
    "face": (0.0, 0.0, 0.0, "head"),
    "headband": (0.0, 0.04, 0.0, "face"),
    "left_arm": (-ARM_X, ARM_Y, 0.0, "hips"),
    "right_arm": (ARM_X, ARM_Y, 0.0, "hips"),
    "left_leg": (-LEG_X, 0.0, 0.0, "hips"),
    "right_leg": (LEG_X, 0.0, 0.0, "hips"),
}


def build_soldier(team):
    """Returns `(asset_id, nodes, geometries, geometry_count)` for one team."""
    geometries = {}
    counter = [0]

    def geometry_for(builder):
        if builder.count_triangles() == 0:
            return None
        geometry_id = "geometry_%d" % counter[0]
        counter[0] += 1
        geometries[geometry_id] = builder.record()
        return geometry_id

    asset_id = "human_" + team
    nodes = [{"name": asset_id, "geometry": None, "matrix": _identity(),
              "visible": True, "castShadow": True, "parent": -1}]
    index = {"root": 0}
    for name in ("hips", "head", "face", "headband", "left_arm", "right_arm",
                 "left_leg", "right_leg"):
        x, y, z, parent = PIVOTS[name]
        index[name] = len(nodes)
        nodes.append({
            "name": name, "geometry": None,
            "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1],
            "visible": True, "castShadow": True,
            "parent": index[parent] if parent else 0,
        })

    def attach(parts, pivot):
        parent = index[pivot]
        for name, material_key, builder in parts:
            geometry_id = geometry_for(builder)
            if geometry_id is None:
                continue
            nodes.append(_mesh(asset_id + "__" + name, geometry_id, material_key, parent))

    attach(build_torso(), "hips")
    attach(build_vest(), "hips")
    attach(build_pack(), "hips")
    attach(build_patch(), "hips")
    attach(build_head(), "head")
    attach(build_helmet(), "head")
    attach(build_helmet_gear(), "head")
    attach(build_face(), "face")
    attach(build_goggles(), "face")
    attach(build_headband(), "headband")
    attach([("left_arm", "ds_uniform", build_arm())], "left_arm")
    attach([("right_arm", "ds_uniform", build_arm())], "right_arm")
    attach([("left_leg", "ds_uniform", build_leg())], "left_leg")
    attach([("right_leg", "ds_uniform", build_leg())], "right_leg")
    return asset_id, nodes, geometries, counter[0]


def build_all():
    models = {}
    geometries = {}
    counter = 0
    for team in ("blue", "red", "ffa"):
        asset_id, nodes, team_geometries, used = build_soldier(team)
        offset = counter
        for key, value in team_geometries.items():
            geometries["geometry_%d" % (int(key.split("_")[1]) + offset)] = value
        for node in nodes:
            if node["geometry"]:
                node["geometry"] = "geometry_%d" % (int(node["geometry"].split("_")[1]) + offset)
        counter += used
        models[asset_id] = {"nodes": nodes}
    return models, geometries


def _identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def _mesh(name, geometry_id, material_key, parent):
    return {
        "name": name, "geometry": geometry_id, "material": material_key,
        "matrix": _identity(), "visible": True, "castShadow": True, "parent": parent,
    }
