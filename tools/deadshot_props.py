"""High-detail props: scorestreaks, equipment, pickups and the rocket.

Same conventions as the weapons and characters builders: local metres, +Y up,
deterministic, and every named pivot the gameplay code animates is preserved.

Named pivots the gameplay drives, and where they are used:

  `streak_sentry`                 `gun`      - the turret head the streak
                                    system traverses about Y
  `streak_uav`                    `rotor`    - the spinning radar bar
  `streak_chopper_gunner`,
  `streak_gunship`,
  `streak_attack_heli`            `mainRotor`, `tailRotor`
  `care_crate`, `care_pickup`     marker lamp geometry only; the root moves
  `rocket`, `ammo_pickup`, `weapon_drop`, `equipment_*`  no named pivots
"""

from __future__ import annotations

import math

from deadshot_detail import (
    Builder, box, profile_circle, profile_rounded_rect, rounded_box, sweep,
    swept_tube, tube, vmul,
)

TAU = math.tau
HALF_PI = math.pi * 0.5
QUARTER = math.pi * 0.25

MATERIALS = {
    "ds_p_hull": {
        "name": "ds_p_hull", "color": [0.055, 0.058, 0.060], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "painted_metal",
    },
    "ds_p_metal": {
        "name": "ds_p_metal", "color": [0.115, 0.118, 0.124], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "metal",
    },
    "ds_p_dark": {
        "name": "ds_p_dark", "color": [0.020, 0.021, 0.023], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "rubber",
    },
    "ds_p_accent": {
        "name": "ds_p_accent", "color": [0.62, 0.30, 0.03], "emissive": [0.05, 0.02, 0.0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "painted_metal",
    },
    "ds_p_lens": {
        "name": "ds_p_lens", "color": [0.06, 0.09, 0.12], "emissive": [0.01, 0.02, 0.03],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "glass",
    },
    "ds_p_lamp": {
        "name": "ds_p_lamp", "color": [1.0, 0.55, 0.10], "emissive": [1.0, 0.45, 0.06],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
    },
    "ds_p_green": {
        "name": "ds_p_green", "color": [0.20, 0.85, 0.30], "emissive": [0.06, 0.45, 0.10],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
    },
    "ds_p_red": {
        "name": "ds_p_red", "color": [0.90, 0.10, 0.06], "emissive": [0.50, 0.03, 0.02],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
    },
    "ds_p_beam": {
        "name": "ds_p_beam", "color": [0.80, 0.92, 0.43], "emissive": [0.22, 0.30, 0.06],
        "opacity": 0.22, "transparent": True, "doubleSide": True, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
    },
    "ds_p_crate": {
        "name": "ds_p_crate", "color": [0.42, 0.30, 0.10], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "painted_metal",
    },
    "ds_p_wood": {
        "name": "ds_p_wood", "color": [0.19, 0.14, 0.09], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "wood",
    },
    "ds_p_steel": {
        "name": "ds_p_steel", "color": [0.34, 0.35, 0.37], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "metal",
    },
    "ds_p_bright": {
        "name": "ds_p_bright", "color": [0.78, 0.79, 0.82], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "",
        "surface": "metal",
    },
}


# --------------------------------------------------------------------------
# Shared shapes.
# --------------------------------------------------------------------------

def swept_plate(builder, points, half_thickness):
    """A flat plate from a four-point outline, extruded about its own plane."""
    top = [(p[0], p[1] + half_thickness, p[2]) for p in points]
    bottom = [(p[0], p[1] - half_thickness, p[2]) for p in points]
    builder.quad(top[0], top[1], top[2], top[3])
    builder.quad(bottom[3], bottom[2], bottom[1], bottom[0])
    for index in range(4):
        j = (index + 1) % 4
        builder.quad(top[index], bottom[index], bottom[j], top[j])


def body_of_revolution(builder, stations, segments=16, cap_start=True, cap_end=True):
    """`stations` is `(z, radius)` along the local Z axis."""
    frames = [((0.0, 0.0, z), vmul((1.0, 0.0, 0.0), r), vmul((0.0, 1.0, 0.0), r), (0.0, 0.0, -1.0))
              for z, r in stations]
    sweep(builder, profile_circle(1.0, segments), frames, cap_start, cap_end)


def stacked(builder, stations, segments=16, cap_start=True, cap_end=True):
    """`stations` is `(y, radius)` along the local Y axis."""
    frames = [((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), r), vmul((0.0, 0.0, 1.0), r), (0.0, 1.0, 0.0))
              for y, r in stations]
    sweep(builder, profile_circle(1.0, segments), frames, cap_start, cap_end)


# --------------------------------------------------------------------------
# Scorestreaks.
# --------------------------------------------------------------------------

def build_uav_hull():
    hull = Builder()
    # Fuselage: nose, shoulder, taper to the tail.
    frames = []
    for t, half_w, half_h in ((0.0, 0.030, 0.024), (0.28, 0.056, 0.042),
                              (0.62, 0.052, 0.040), (1.0, 0.020, 0.016)):
        frames.append(((0.0, 0.0, -0.30 + t * 0.60), vmul((1.0, 0.0, 0.0), half_w),
                       vmul((0.0, 1.0, 0.0), half_h), (0.0, 0.0, -1.0)))
    sweep(hull, profile_rounded_rect(1.0, 1.0, 0.35, 3), frames, True, True)
    # Swept, tapered wings.
    for side in (-1.0, 1.0):
        planform = [(side * 0.060, 0.0, -0.100), (side * 0.520, 0.0, 0.030),
                    (side * 0.520, 0.0, 0.130), (side * 0.060, 0.0, 0.050)]
        swept_plate(hull, planform, 0.008)
        rounded_box(hull, (side * 0.545, 0.0, 0.080), (0.018, 0.012, 0.030), 0.004)
    # V-tail.
    for side in (-1.0, 1.0):
        planform = [(side * 0.012, 0.006, 0.280), (side * 0.090, 0.006, 0.420),
                    (side * 0.090, 0.006, 0.320), (side * 0.012, 0.006, 0.240)]
        swept_plate(hull, planform, 0.004)
    # Nose sensor ball, tail beacon, landing skids.
    body_of_revolution(hull, [(-0.300, 0.020), (-0.330, 0.028), (-0.352, 0.026), (-0.362, 0.010)])
    tube(hull, (0.0, 0.010, 0.300), (0.0, 0.010, 0.322), 0.018, 12)
    for side in (-1.0, 1.0):
        swept_tube(hull, [(side * 0.030, -0.030, -0.100), (side * 0.040, -0.062, -0.040),
                          (side * 0.040, -0.070, 0.100)], 0.006, 8)
    parts = [("hull", "ds_p_hull", hull)]

    # `rotor` is the pivot the streak system spins.
    rotor = Builder()
    rounded_box(rotor, (0.0, 0.052, 0.020), (0.070, 0.018, 0.150), 0.006)
    for side in (-1.0, 1.0):
        swept_tube(rotor, [(side * 0.030, 0.052, -0.050), (side * 0.030, 0.062, 0.090)], 0.004, 6)
    parts.append(("rotor", "ds_p_metal", rotor))

    lamp = Builder()
    tube(lamp, (0.0, -0.034, -0.060), (0.0, -0.038, -0.060), 0.014, 12)
    parts.append(("lamp", "ds_p_green", lamp))
    return parts


def build_sentry_base():
    base = Builder()
    for index in range(3):
        angle = index * TAU / 3.0
        dx, dz = math.cos(angle) * 0.30, math.sin(angle) * 0.30
        swept_tube(base, [(0.0, 0.30, 0.0), (dx * 0.7, 0.16, dz * 0.7), (dx, 0.0, dz)], 0.010, 8)
        rounded_box(base, (dx, 0.006, dz), (0.048, 0.012, 0.048), 0.006)
    tube(base, (0.0, 0.10, 0.0), (0.0, 0.40, 0.0), 0.048, 16, radius_end=0.038, steps=3)
    tube(base, (0.0, 0.40, 0.0), (0.0, 0.455, 0.0), 0.062, 20, steps=2)
    rounded_box(base, (0.0, 0.14, 0.13), (0.100, 0.090, 0.070), 0.010, corner_segments=3)
    rounded_box(base, (-0.13, 0.16, -0.02), (0.056, 0.110, 0.080), 0.010, corner_segments=3)
    for index in range(3):
        box(base, (0.0, 0.175 - index * 0.030, 0.166), (0.086, 0.008, 0.006))
    return [("base", "ds_p_hull", base)]


# Height the sentry's traversing head sits at, above the base column.
SENTRY_HEAD_Y = 0.500


def build_sentry_head():
    """The `gun` pivot: everything that traverses about Y.

    `streak_system` rotates this node about Y in place, so the head is modelled
    around its own origin and the node matrix lifts it onto the column.
    """
    head = Builder()
    rounded_box(head, (0.0, 0.0, 0.0), (0.100, 0.088, 0.120), 0.010, corner_segments=3)
    tube(head, (0.0, 0.010, -0.080), (0.0, 0.010, -0.230), 0.019, 16, steps=3)
    for index in range(5):
        z = -0.110 - index * 0.026
        tube(head, (0.0, 0.010, z - 0.005), (0.0, 0.010, z + 0.005), 0.022, 14)
    tube(head, (0.0, 0.010, -0.232), (0.0, 0.010, -0.254), 0.024, 16, radius_end=0.020)
    rounded_box(head, (0.0, 0.062, -0.010), (0.046, 0.040, 0.086), 0.008, corner_segments=3)
    tube(head, (0.0, 0.066, -0.052), (0.0, 0.066, 0.032), 0.017, 16, cap_start=False, cap_end=False)
    rounded_box(head, (-0.062, -0.010, 0.020), (0.040, 0.070, 0.060), 0.008, corner_segments=3)
    tube(head, (0.030, 0.030, -0.070), (0.034, 0.030, -0.086), 0.007, 10)
    return [("gun", "ds_p_hull", head)]


def build_predator():
    body = Builder()
    # Airframe: seeker nose, warhead shoulder, motor section.
    body_of_revolution(body, [(0.300, 0.030), (0.255, 0.040), (0.150, 0.042),
                              (-0.060, 0.040), (-0.270, 0.036), (-0.300, 0.010)])
    tube(body, (0.0, 0.0, -0.300), (0.0, 0.0, -0.336), 0.020, 14, radius_end=0.014)
    # Cruciform fins.
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        planform = [(ux * 0.020, uy * 0.020, -0.160), (ux * 0.105, uy * 0.105, -0.060),
                    (ux * 0.105, uy * 0.105, 0.020), (ux * 0.020, uy * 0.020, 0.000)]
        outer = [(q[0] + uy * 0.005, q[1] - ux * 0.005, q[2]) for q in planform]
        inner = [(q[0] - uy * 0.005, q[1] + ux * 0.005, q[2]) for q in planform]
        body.quad(outer[0], outer[1], outer[2], outer[3])
        body.quad(inner[3], inner[2], inner[1], inner[0])
        for k in range(4):
            j = (k + 1) % 4
            body.quad(outer[k], inner[k], inner[j], outer[j])
    parts = [("body", "ds_p_hull", body)]
    sensor = Builder()
    tube(sensor, (0.0, -0.040, 0.230), (0.0, -0.062, 0.230), 0.026, 16, radius_end=0.020)
    parts.append(("sensor", "ds_p_lens", sensor))
    exhaust = Builder()
    tube(exhaust, (0.0, 0.0, 0.300), (0.0, 0.0, 0.318), 0.024, 14, radius_end=0.030)
    parts.append(("exhaust", "ds_p_lamp", exhaust))
    return parts


def build_rcxd():
    body = Builder()
    rounded_box(body, (0.0, 0.070, 0.0), (0.230, 0.070, 0.400), 0.018, corner_segments=4)
    rounded_box(body, (0.0, 0.086, -0.170), (0.200, 0.056, 0.090), 0.016, corner_segments=3)
    rounded_box(body, (0.0, 0.056, -0.208), (0.240, 0.036, 0.030), 0.010, corner_segments=3)
    swept_tube(body, [(-0.100, 0.112, -0.120), (-0.078, 0.150, -0.040),
                      (0.078, 0.150, -0.040), (0.100, 0.112, -0.120)], 0.009, 8)
    tube(body, (0.070, 0.106, 0.130), (0.078, 0.240, 0.160), 0.0035, 8)
    tube(body, (0.078, 0.240, 0.160), (0.080, 0.268, 0.168), 0.0060, 8)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x, z = sx * 0.108, sz * 0.132
            tube(body, (x - 0.028, 0.052, z), (x + 0.028, 0.052, z), 0.052, 18, steps=2)
            tube(body, (x - 0.032, 0.052, z), (x + 0.032, 0.052, z), 0.026, 14, steps=2)
    parts = [("body", "ds_p_hull", body)]
    charge = Builder()
    rounded_box(charge, (0.0, 0.116, 0.140), (0.150, 0.060, 0.110), 0.010, corner_segments=3)
    parts.append(("charge", "ds_p_accent", charge))
    led = Builder()
    tube(led, (0.0, 0.150, 0.140), (0.0, 0.156, 0.140), 0.010, 10)
    parts.append(("led", "ds_p_red", led))
    return parts


def build_nuke():
    body = Builder()
    body_of_revolution(body, [(0.556, 0.030), (0.460, 0.115), (0.0, 0.140),
                              (-0.480, 0.115), (-0.556, 0.070)], segments=18)
    tube(body, (0.0, 0.0, 0.556), (0.0, 0.0, 0.640), 0.030, 14, radius_end=0.006)
    tube(body, (0.0, 0.0, -0.548), (0.0, 0.0, -0.576), 0.072, 18)
    for index in range(4):
        angle = index * HALF_PI
        rounded_box(body, (math.cos(angle) * 0.128, math.sin(angle) * 0.128, 0.0),
                    (0.028, 0.028, 0.900), 0.006, corner_segments=2)
    parts = [("body", "ds_p_steel", body)]
    band = Builder()
    for z in (-0.190, 0.120):
        sweep(band, profile_circle(1.0, 18),
              [((0.0, 0.0, z), vmul((1.0, 0.0, 0.0), 0.143), vmul((0.0, 1.0, 0.0), 0.143), (0.0, 0.0, -1.0)),
               ((0.0, 0.0, z + 0.040), vmul((1.0, 0.0, 0.0), 0.143), vmul((0.0, 1.0, 0.0), 0.143), (0.0, 0.0, -1.0))],
              True, True)
    parts.append(("band", "ds_p_accent", band))
    return parts


def build_care_crate(falling):
    """Supply crate. `falling` adds the marker beam the dropped crate carries."""
    crate = Builder()
    rounded_box(crate, (0.0, 0.400, 0.0), (1.200, 0.800, 1.200), 0.030, corner_segments=4)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            rounded_box(crate, (sx * 0.58, 0.400, sz * 0.58), (0.090, 0.820, 0.090),
                        0.014, corner_segments=3)
    for y in (0.120, 0.680):
        for sz in (-1.0, 1.0):
            box(crate, (0.0, y, sz * 0.605), (1.230, 0.055, 0.020))
        for sx in (-1.0, 1.0):
            box(crate, (sx * 0.605, y, 0.0), (0.020, 0.055, 1.230))
    rounded_box(crate, (0.0, 0.812, 0.0), (1.180, 0.060, 1.180), 0.024, corner_segments=3)
    box(crate, (0.0, 0.720, -0.640), (0.240, 0.180, 0.050))
    parts = [("crate", "ds_p_crate", crate)]
    lamp = Builder()
    tube(lamp, (0.0, 0.880, 0.0), (0.0, 0.906, 0.0), 0.075, 14)
    parts.append(("marker", "ds_p_lamp", lamp))
    if falling:
        # The open-topped cylinder the pickup beam has always been: no caps, so
        # only the walls draw.
        beam = Builder()
        sweep(beam, profile_circle(1.0, 16),
              [((0.0, 0.0, 0.0), vmul((1.0, 0.0, 0.0), 0.180), vmul((0.0, 0.0, 1.0), 0.180), (0.0, 1.0, 0.0)),
               ((0.0, 9.600, 0.0), vmul((1.0, 0.0, 0.0), 0.180), vmul((0.0, 0.0, 1.0), 0.180), (0.0, 1.0, 0.0))],
              False, False)
        parts.append(("beam", "ds_p_beam", beam))
    return parts


def build_gunship():
    """Attack helicopter used by the chopper gunner and gunship streaks."""
    body = Builder()
    frames = []
    for t, rx, ry in ((0.0, 0.100, 0.100), (0.28, 0.220, 0.200),
                      (0.62, 0.200, 0.180), (1.0, 0.070, 0.070)):
        z = -1.20 + t * 1.60
        frames.append(((0.0, 0.0, z), vmul((1.0, 0.0, 0.0), rx), vmul((0.0, 1.0, 0.0), ry),
                       (0.0, 0.0, -1.0)))
    sweep(body, profile_circle(1.0, 20), frames, True, True)
    # Tail boom and fin.
    tube(body, (0.0, 0.0, 0.400), (0.0, 0.020, 0.940), 0.075, 14, radius_end=0.050, steps=3)
    swept_plate(body, [(0.0, 0.060, 0.820), (0.0, 0.230, 0.960),
                       (0.0, 0.230, 0.880), (0.0, 0.060, 0.760)], 0.010)
    # Stub wings with weapon pylons.
    for side in (-1.0, 1.0):
        swept_plate(body, [(side * 0.160, -0.020, -0.280), (side * 0.620, 0.020, -0.200),
                           (side * 0.620, 0.020, -0.060), (side * 0.160, -0.020, -0.100)], 0.020)
        rounded_box(body, (side * 0.500, -0.070, -0.160), (0.120, 0.140, 0.300), 0.014,
                    corner_segments=3)
        tube(body, (side * 0.500, -0.140, -0.300), (side * 0.500, -0.140, 0.020), 0.036, 12)
    # Skids.
    for side in (-1.0, 1.0):
        swept_tube(body, [(side * 0.200, -0.240, -0.600), (side * 0.260, -0.340, 0.200),
                          (side * 0.260, -0.340, 0.700)], 0.026, 10)
        for z in (-0.400, 0.300):
            tube(body, (side * 0.160, -0.100, z), (side * 0.240, -0.320, z), 0.014, 8)
    # Nose sensor turret and chin gun.
    turret = Builder()
    tube(turret, (0.0, -0.090, -1.020), (0.0, -0.130, -1.020), 0.070, 16, radius_end=0.055)
    tube(turret, (0.0, -0.140, -1.060), (0.0, -0.140, -1.120), 0.022, 12)
    cockpit = Builder()
    frames = []
    for t, rx, ry in ((0.0, 0.050, 0.040), (0.5, 0.140, 0.100), (1.0, 0.060, 0.050)):
        z = -1.15 + t * 0.42
        frames.append(((0.0, 0.100 + t * 0.060, z), vmul((1.0, 0.0, 0.0), rx),
                       vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, -1.0)))
    sweep(cockpit, profile_circle(1.0, 16), frames, True, True)
    return [("body", "ds_p_hull", body), ("cockpit", "ds_p_lens", cockpit),
            ("turret", "ds_p_metal", turret)]


def build_gunship_rotors():
    """`mainRotor` and `tailRotor` are the pivots the streak system spins."""
    main = Builder()
    tube(main, (0.0, 0.0, 0.0), (0.0, 0.090, 0.0), 0.040, 14)
    for index in range(4):
        angle = index * HALF_PI
        ux, uy = math.cos(angle), math.sin(angle)
        swept_plate(main, [(ux * 0.040, 0.085, uy * 0.040), (ux * 2.400, 0.075, uy * 2.400),
                           (ux * 2.400, 0.075, uy * 2.400 + 0.160),
                           (ux * 0.040, 0.085, uy * 0.040 + 0.160)], 0.012)
    tail = Builder()
    tube(tail, (0.0, 0.0, 0.0), (0.040, 0.0, 0.0), 0.028, 12)
    for index in range(2):
        angle = index * math.pi
        uz, uy = math.cos(angle), math.sin(angle)
        swept_plate(tail, [(0.030, uy * 0.030, uz * 0.030), (0.030, uy * 0.520, uz * 0.520),
                           (0.030 + 0.140, uy * 0.520, uz * 0.520),
                           (0.030 + 0.140, uy * 0.030, uz * 0.030)], 0.010)
    return [("mainRotor", "ds_p_dark", main), ("tailRotor", "ds_p_dark", tail)]


def build_strafe_jet():
    body = Builder()
    frames = []
    for t, rx, ry in ((0.0, 0.014, 0.014), (0.22, 0.056, 0.048),
                      (0.58, 0.060, 0.050), (1.0, 0.026, 0.024)):
        frames.append(((0.0, 0.0, -0.62 + t * 1.24), vmul((1.0, 0.0, 0.0), rx),
                       vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, -1.0)))
    sweep(body, profile_circle(1.0, 16), frames, True, True)
    for side in (-1.0, 1.0):
        swept_plate(body, [(side * 0.050, 0.0, -0.120), (side * 0.400, 0.010, 0.140),
                           (side * 0.400, 0.010, 0.240), (side * 0.050, 0.0, 0.120)], 0.012)
        tube(body, (side * 0.180, -0.030, 0.020), (side * 0.180, -0.030, -0.150), 0.014, 12)
        tube(body, (side * 0.260, -0.030, 0.020), (side * 0.260, -0.030, -0.150), 0.014, 12)
        tail_plan = [(side * 0.020, 0.030, 0.480), (side * 0.110, 0.130, 0.620),
                     (side * 0.110, 0.130, 0.520), (side * 0.020, 0.030, 0.460)]
        outer = [(q[0] + 0.008, q[1], q[2]) for q in tail_plan]
        inner = [(q[0] - 0.008, q[1], q[2]) for q in tail_plan]
        if side > 0:
            body.quad(outer[0], outer[1], outer[2], outer[3])
            body.quad(inner[3], inner[2], inner[1], inner[0])
        else:
            body.quad(outer[3], outer[2], outer[1], outer[0])
            body.quad(inner[0], inner[1], inner[2], inner[3])
        for index in range(4):
            j = (index + 1) % 4
            if side > 0:
                body.quad(outer[index], inner[index], inner[j], outer[j])
            else:
                body.quad(outer[j], inner[j], inner[index], outer[index])
        tube(body, (side * 0.030, 0.0, 0.620), (side * 0.030, 0.0, 0.660), 0.026, 14,
             radius_end=0.030)
    canopy = Builder()
    frames = []
    for t, r in ((0.0, 0.012), (0.35, 0.032), (1.0, 0.014)):
        frames.append(((0.0, 0.052 - t * 0.010, -0.400 + t * 0.300), vmul((1.0, 0.0, 0.0), r),
                       vmul((0.0, 1.0, 0.0), r * 0.55), (0.0, 0.0, -1.0)))
    sweep(canopy, profile_circle(1.0, 14), frames, True, True)
    return [("body", "ds_p_hull", body), ("canopy", "ds_p_lens", canopy)]


# --------------------------------------------------------------------------
# Equipment.
# --------------------------------------------------------------------------

def build_frag():
    body = Builder()
    stacked(body, [(-0.052, 0.012), (-0.038, 0.040), (0.0, 0.048), (0.038, 0.040), (0.052, 0.014)],
            segments=18)
    for index in range(6):
        angle = index * TAU / 6.0
        ux, uz = math.cos(angle), math.sin(angle)
        box(body, (ux * 0.046, 0.0, uz * 0.046), (0.020, 0.092, 0.020))
    tube(body, (0.0, 0.052, 0.0), (0.0, 0.082, 0.0), 0.020, 14, radius_end=0.016)
    rounded_box(body, (0.0, 0.092, 0.0), (0.030, 0.020, 0.030), 0.006)
    swept_tube(body, [(0.024, 0.076, 0.0), (0.030, 0.030, 0.0), (0.026, -0.030, 0.0)], 0.005, 8)
    tube(body, (0.0, 0.104, 0.0), (0.0, 0.112, 0.0), 0.010, 10)
    return [("body", "ds_p_hull", body)]


def build_semtex():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.115, 0.046, 0.075), 0.010, corner_segments=3)
    for index in range(3):
        box(body, (0.0, -0.014 + index * 0.014, 0.040), (0.108, 0.006, 0.008))
    rounded_box(body, (0.0, 0.030, 0.0), (0.070, 0.018, 0.048), 0.006, corner_segments=3)
    tube(body, (0.030, 0.030, 0.0), (0.048, 0.048, 0.0), 0.006, 10)
    # `equipment_system` drives the stuck-charge blink by name, so the mesh it
    # tints keeps the asset's own name rather than a role name.
    return [("equipment_semtex", "ds_p_hull", body)]


def build_throwing_knife():
    """The thrown projectile: a real tapered flat with a cord-wrapped grip.

    `VisualFactory.create_equipment("knife")` maps to this asset and the thrown
    projectile spins the whole root, so the blade lies along local Z the way the
    ported model did.
    """
    blade = Builder()
    stations = [(-0.230, 0.0010, 0.0000), (-0.180, 0.0022, 0.0160), (-0.120, 0.0032, 0.0250),
                (-0.060, 0.0038, 0.0300), (-0.010, 0.0040, 0.0290), (0.020, 0.0040, 0.0260)]
    edge = [0.0, -0.052, -0.030, -0.016, -0.008, -0.004]
    for index in range(len(stations) - 1):
        z0, half0, spine0 = stations[index]
        z1, half1, spine1 = stations[index + 1]
        e0, e1 = edge[index], edge[index + 1]
        for side in (-1.0, 1.0):
            spine_a = (side * half0 * 0.28, e0 + spine0, z0)
            spine_b = (side * half1 * 0.28, e1 + spine1, z1)
            flat_a = (side * half0, e0 + spine0 * 0.55, z0)
            flat_b = (side * half1, e1 + spine1 * 0.55, z1)
            root_a = (side * half0, e0 + spine0 * 0.18, z0)
            root_b = (side * half1, e1 + spine1 * 0.18, z1)
            edge_a = (side * half0 * 0.10, e0, z0)
            edge_b = (side * half1 * 0.10, e1, z1)
            if side > 0:
                blade.quad(spine_a, flat_a, flat_b, spine_b)
                blade.quad(flat_a, root_a, root_b, flat_b)
                blade.quad(root_a, edge_a, edge_b, root_b)
            else:
                blade.quad(spine_b, flat_b, flat_a, spine_a)
                blade.quad(flat_b, root_b, root_a, flat_a)
                blade.quad(root_b, edge_b, edge_a, root_a)
    parts = [("blade", "ds_p_bright", blade)]
    # Cord wrap on the tang.
    grip = Builder()
    for index in range(6):
        z = 0.026 + index * 0.010
        rounded_box(grip, (0.0, 0.002, z), (0.026, 0.030, 0.007), 0.003, corner_segments=2)
    parts.append(("grip", "ds_p_wood", grip))
    return parts


def build_claymore():
    body = Builder()
    rounded_box(body, (0.0, 0.070, 0.0), (0.220, 0.140, 0.040), 0.008, corner_segments=3)
    for row in range(4):
        for column in range(5):
            rounded_box(body, ((column - 2) * 0.040, 0.020 + row * 0.034, 0.022),
                        (0.026, 0.026, 0.010), 0.004, corner_segments=2)
    for side in (-1.0, 1.0):
        swept_tube(body, [(side * 0.090, 0.010, 0.010), (side * 0.130, 0.0, 0.060),
                          (side * 0.150, 0.0, 0.130)], 0.0055, 8)
    tube(body, (0.0, 0.070, -0.024), (0.0, 0.070, -0.034), 0.014, 12)
    return [("body", "ds_p_hull", body)]


def build_c4():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.160, 0.060, 0.110), 0.010, corner_segments=3)
    for index in range(3):
        box(body, (0.0, -0.010 + index * 0.010, 0.056), (0.150, 0.005, 0.006))
    tube(body, (0.060, 0.030, -0.040), (0.074, 0.052, -0.058), 0.005, 8)
    swept_tube(body, [(0.074, 0.052, -0.058), (0.050, 0.090, -0.100), (-0.020, 0.080, -0.120)],
               0.0028, 6)
    parts = [("body", "ds_p_hull", body)]
    led = Builder()
    tube(led, (-0.050, 0.032, 0.0), (-0.050, 0.038, 0.0), 0.008, 10)
    # `equipment_system` pulses this LED by name (`part_3`), as the ported asset
    # named it, so the name is part of the contract rather than descriptive.
    parts.append(("part_3", "ds_p_red", led))
    return parts


def build_flashbang():
    body = Builder()
    stacked(body, [(-0.048, 0.014), (-0.029, 0.040), (0.005, 0.042), (0.034, 0.038), (0.048, 0.016)])
    for index in range(4):
        box(body, (0.0, -0.020 + index * 0.016, 0.040), (0.070, 0.006, 0.006))
    tube(body, (0.0, 0.048, 0.0), (0.0, 0.076, 0.0), 0.018, 14, radius_end=0.020)
    for index in range(6):
        angle = index * TAU / 6.0
        box(body, (math.cos(angle) * 0.016, 0.086, math.sin(angle) * 0.016),
            (0.008, 0.020, 0.008))
    swept_tube(body, [(0.022, 0.070, 0.0), (0.028, 0.028, 0.0), (0.024, -0.028, 0.0)], 0.0045, 8)
    return [("body", "ds_p_hull", body)]


def build_stun():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.100, 0.090, 0.100), 0.016, corner_segments=3)
    for index in range(3):
        box(body, (0.0, -0.026 + index * 0.026, 0.052), (0.092, 0.006, 0.008))
    tube(body, (0.0, 0.046, 0.0), (0.0, 0.070, 0.0), 0.018, 14)
    swept_tube(body, [(0.022, 0.062, 0.0), (0.028, 0.024, 0.0), (0.024, -0.024, 0.0)], 0.0045, 8)
    return [("body", "ds_p_hull", body)]


def build_smoke():
    body = Builder()
    stacked(body, [(-0.120, 0.020), (-0.084, 0.062), (0.012, 0.068), (0.091, 0.062), (0.120, 0.024)],
            segments=18)
    for index in range(5):
        box(body, (0.0, -0.070 + index * 0.034, 0.066), (0.100, 0.010, 0.008))
    tube(body, (0.0, 0.120, 0.0), (0.0, 0.148, 0.0), 0.030, 16, radius_end=0.024)
    tube(body, (0.0, 0.150, 0.0), (0.0, 0.162, 0.0), 0.024, 14)
    return [("body", "ds_p_hull", body)]


def build_molotov():
    bottle = Builder()
    stacked(bottle, [(-0.140, 0.030), (-0.112, 0.055), (0.028, 0.062), (0.090, 0.050),
                     (0.118, 0.020), (0.140, 0.018)], segments=18)
    tube(bottle, (0.0, 0.140, 0.0), (0.0, 0.166, 0.0), 0.019, 14)
    parts = [("bottle", "ds_p_lens", bottle)]
    wick = Builder()
    swept_tube(wick, [(0.0, 0.160, 0.0), (0.012, 0.200, 0.006), (0.020, 0.236, 0.014)], 0.0085, 8)
    parts.append(("wick", "ds_p_wood", wick))
    flame = Builder()
    tube(flame, (0.018, 0.236, 0.012), (0.024, 0.276, 0.020), 0.013, 12, radius_end=0.004)
    parts.append(("flame", "ds_p_lamp", flame))
    return parts


def build_thermite():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.140, 0.160, 0.140), 0.014, corner_segments=3)
    for index in range(4):
        box(body, (0.0, -0.058 + index * 0.038, 0.074), (0.128, 0.010, 0.008))
    tube(body, (0.0, 0.080, 0.0), (0.0, 0.102, 0.0), 0.048, 16, radius_end=0.040)
    for index in range(4):
        angle = index * HALF_PI
        box(body, (math.cos(angle) * 0.040, 0.086, math.sin(angle) * 0.040),
            (0.020, 0.016, 0.020))
    parts = [("body", "ds_p_hull", body)]
    glow = Builder()
    tube(glow, (0.0, 0.104, 0.0), (0.0, 0.108, 0.0), 0.034, 14)
    parts.append(("glow", "ds_p_lamp", glow))
    return parts


def build_snapshot():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.110, 0.100, 0.110), 0.014, corner_segments=3)
    tube(body, (0.0, 0.010, -0.058), (0.0, 0.010, -0.080), 0.032, 16, radius_end=0.028)
    tube(body, (0.0, 0.010, -0.082), (0.0, 0.010, -0.086), 0.024, 14)
    for index in range(3):
        box(body, (0.0, -0.030 + index * 0.024, 0.058), (0.100, 0.008, 0.008))
    parts = [("body", "ds_p_hull", body)]
    lens = Builder()
    tube(lens, (0.0, 0.010, -0.086), (0.0, 0.010, -0.092), 0.022, 14)
    parts.append(("lens", "ds_p_green", lens))
    return parts


# --------------------------------------------------------------------------
# Pickups and projectiles.
# --------------------------------------------------------------------------

def build_ammo_pickup():
    can = Builder()
    rounded_box(can, (0.0, 0.140, 0.0), (0.460, 0.280, 0.340), 0.020, corner_segments=3)
    rounded_box(can, (0.0, 0.290, 0.0), (0.430, 0.040, 0.310), 0.014, corner_segments=2)
    rounded_box(can, (0.0, 0.312, 0.0), (0.120, 0.026, 0.070), 0.008, corner_segments=2)
    for side in (-1.0, 1.0):
        swept_tube(can, [(side * 0.200, 0.290, -0.120), (side * 0.212, 0.150, -0.140),
                         (side * 0.212, 0.030, -0.140)], 0.010, 8)
    parts = [("can", "ds_p_crate", can)]
    band = Builder()
    box(band, (0.0, 0.200, 0.0), (0.472, 0.060, 0.352))
    parts.append(("band", "ds_p_accent", band))
    return parts


def build_weapon_drop():
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.070, 0.130, 0.520), 0.010, corner_segments=3)
    rounded_box(body, (0.0, -0.100, -0.070), (0.090, 0.160, 0.110), 0.012, corner_segments=3)
    rounded_box(body, (0.0, -0.030, 0.250), (0.080, 0.110, 0.180), 0.014, corner_segments=3)
    tube(body, (0.0, 0.010, -0.270), (0.0, 0.010, -0.400), 0.020, 14)
    rounded_box(body, (0.0, 0.080, -0.030), (0.060, 0.070, 0.120), 0.010, corner_segments=3)
    parts = [("body", "ds_p_hull", body)]
    optic = Builder()
    tube(optic, (0.0, 0.070, -0.030), (0.0, 0.070, 0.038), 0.026, 16,
         cap_start=False, cap_end=False)
    parts.append(("optic", "ds_p_lens", optic))
    return parts


def build_rocket():
    body = Builder()
    body_of_revolution(body, [(0.340, 0.030), (0.280, 0.038), (0.130, 0.046),
                              (-0.020, 0.038), (-0.130, 0.030), (-0.340, 0.030)])
    tube(body, (0.0, 0.0, 0.340), (0.0, 0.0, 0.372), 0.030, 16, radius_end=0.034)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        planform = [(ux * 0.024, uy * 0.024, 0.140), (ux * 0.090, uy * 0.090, 0.230),
                    (ux * 0.090, uy * 0.090, 0.320), (ux * 0.024, uy * 0.024, 0.320)]
        outer = [(q[0] + uy * 0.004, q[1] - ux * 0.004, q[2]) for q in planform]
        inner = [(q[0] - uy * 0.004, q[1] + ux * 0.004, q[2]) for q in planform]
        body.quad(outer[0], outer[1], outer[2], outer[3])
        body.quad(inner[3], inner[2], inner[1], inner[0])
        for k in range(4):
            j = (k + 1) % 4
            body.quad(outer[k], inner[k], inner[j], outer[j])
    parts = [("body", "ds_p_hull", body)]
    plume = Builder()
    tube(plume, (0.0, 0.0, 0.372), (0.0, 0.0, 0.470), 0.030, 14, radius_end=0.010)
    parts.append(("plume", "ds_p_lamp", plume))
    return parts


# --------------------------------------------------------------------------
# Assembly. Rotors are separate nodes so the gameplay can spin them.
# --------------------------------------------------------------------------

def _rotor_parts(asset_id, parts):
    if asset_id in ("streak_chopper_gunner", "streak_gunship", "streak_attack_heli"):
        return parts + build_gunship_rotors()
    return parts


def _sentry_parts(asset_id, parts):
    if asset_id == "streak_sentry":
        # The traversing head is the `gun` pivot the streak system rotates.
        return build_sentry_base() + build_sentry_head()
    return parts


def build(asset_id):
    """Returns the part list for one prop asset, or `None` if it has no builder."""
    if asset_id == "streak_uav":
        return build_uav_hull()
    if asset_id == "streak_sentry":
        return _sentry_parts(asset_id, [])
    if asset_id == "streak_predator":
        return build_predator()
    if asset_id == "streak_rcxd":
        return build_rcxd()
    if asset_id == "streak_nuke":
        return build_nuke()
    if asset_id in ("streak_chopper_gunner", "streak_gunship", "streak_attack_heli"):
        return _rotor_parts(asset_id, build_gunship())
    # The ported `care_pickup` is the landed crate carrying the 9.7 m marker
    # beam; `care_crate` and the falling `streak_care_package` are the plain
    # crate body.
    if asset_id == "care_pickup":
        return build_care_crate(True)
    if asset_id in ("streak_care_package", "care_crate"):
        return build_care_crate(False)
    if asset_id == "strafe_jet":
        return build_strafe_jet()
    for prefix in ("equipment_",):
        if asset_id.startswith(prefix) and asset_id[len(prefix):] in EQUIPMENT:
            return EQUIPMENT[asset_id[len(prefix):]]()
    if asset_id in PLAIN:
        return PLAIN[asset_id]()
    return None


EQUIPMENT = {
    "frag": build_frag,
    "semtex": build_semtex,
    "throwing_knife": build_throwing_knife,
    "claymore": build_claymore,
    "c4": build_c4,
    "flashbang": build_flashbang,
    "stun": build_stun,
    "smoke": build_smoke,
    "molotov": build_molotov,
    "thermite": build_thermite,
    "snapshot": build_snapshot,
}

PLAIN = {
    "ammo_pickup": build_ammo_pickup,
    "weapon_drop": build_weapon_drop,
    "rocket": build_rocket,
}


def build_all(ids):
    """Returns `(models, geometries)` for the props that have builders."""
    models = {}
    geometries = {}
    counter = 0

    def geometry_for(mesh_builder):
        nonlocal counter
        if mesh_builder.count_triangles() == 0:
            return None
        key = "geometry_%d" % counter
        counter += 1
        geometries[key] = mesh_builder.record()
        return key

    for asset_id in ids:
        parts = build(asset_id)
        if not parts:
            continue
        nodes = []
        for index, (name, material_key, mesh_builder) in enumerate(parts):
            geometry_id = geometry_for(mesh_builder)
            if geometry_id is None:
                continue
            # The ported props had no empty root: the first mesh node *was* the
            # scene root and carried the asset's own name, which is what
            # `VisualFactory.part(root, "equipment_semtex")` resolves against.
            node_name = asset_id if index == 0 else name
            nodes.append({
                "name": node_name, "geometry": geometry_id, "material": material_key,
                "matrix": _translate(PIVOT_OFFSETS.get((asset_id, name), (0.0, 0.0, 0.0))),
                "visible": True, "castShadow": False,
                "parent": -1 if index == 0 else 0,
            })
        models[asset_id] = {"nodes": nodes}
    return models, geometries


# Pivots that sit above their parent's origin. The gameplay rotates these nodes
# in place, so the lift belongs in the node matrix rather than in the geometry.
PIVOT_OFFSETS = {
    ("streak_sentry", "gun"): (0.0, SENTRY_HEAD_Y, 0.0),
}


def _identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def _translate(position):
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, position[0], position[1], position[2], 1]
