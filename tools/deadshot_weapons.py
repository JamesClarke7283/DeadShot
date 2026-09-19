"""High-detail weapon models for DeadShot.

Each category is assembled from real firearm sub-assemblies — receiver, bolt
carrier, charging handle, handguard with M-LOK slots, gas block, barrel, muzzle
device, iron sights, magazine, trigger group, pistol grip, buffer tube and
stock — instead of the stacked boxes the ported models used.

Local space matches the ported viewmodel: metres, +Y up, muzzle forward along
-Z, origin at the receiver. `muzzle` stays an empty pivot at the bore exit and
`knife` an empty pivot at the origin; the factory and gameplay code address
those by name, so they are part of the contract.

Materials are declared here and merged into the manifest, so the Godot surface
system keeps choosing its profiles from `role` and `surface` exactly as before.
"""

from __future__ import annotations

from deadshot_detail import (
    Builder, basis_from_w, box, extrude, lerp3, profile_circle,
    profile_rounded_rect, profile_taper, rail, rounded_box, sweep, swept_tube,
    tube, vadd, vmul, vsub, vnorm,
)

# Material keys. `role` drives the factory's camo/team tinting; the Godot side
# reads `surface` to pick a roughness/metalness profile.
MATERIALS = {
    "ds_wbody": {
        "name": "ds_wbody", "color": [0.055, 0.058, 0.062], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "camo", "surface": "gun_metal",
    },
    "ds_wpolymer": {
        "name": "ds_wpolymer", "color": [0.032, 0.033, 0.036], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "camo", "surface": "polymer",
    },
    "ds_wsteel": {
        "name": "ds_wsteel", "color": [0.108, 0.112, 0.120], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "metal",
    },
    "ds_wblack": {
        "name": "ds_wblack", "color": [0.016, 0.017, 0.019], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "gun_metal",
    },
    "ds_wbright": {
        "name": "ds_wbright", "color": [0.72, 0.74, 0.78], "emissive": [0, 0, 0],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "metal",
    },
    "ds_wglass": {
        "name": "ds_wglass", "color": [0.30, 0.45, 0.55], "emissive": [0.02, 0.05, 0.07],
        "opacity": 0.40, "transparent": True, "doubleSide": True, "unlit": False,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "glass",
    },
    "ds_wreticle": {
        "name": "ds_wreticle", "color": [1.0, 0.08, 0.05], "emissive": [1.0, 0.06, 0.04],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "glazed",
    },
    "ds_wnight": {
        "name": "ds_wnight", "color": [0.35, 0.92, 0.45], "emissive": [0.12, 0.55, 0.20],
        "opacity": 1, "transparent": False, "doubleSide": False, "unlit": True,
        "outline": False, "thickness": 0, "depthTest": True, "role": "", "surface": "glazed",
    },
}

# --------------------------------------------------------------------------
# Common sub-assemblies. Every category shares these; only the dimensions and
# the presence of a few parts differ, which is also true of real firearms.
# --------------------------------------------------------------------------


def _picatinny(builder, z_front, z_back, y, half_width=0.0105, teeth=14):
    rail(builder, (0.0, y, z_front), (0.0, y, z_back), half_width * 2.0, 0.0068, teeth, 0.0055)


def _iron_sights(builder, z_front, z_rear, y):
    """Folding front and rear sights: base, upright and aperture/ring."""
    # Front sight: base block plus a protected post.
    rounded_box(builder, (0.0, y + 0.006, z_front), (0.020, 0.012, 0.030), 0.002)
    box(builder, (0.0, y + 0.021, z_front), (0.0016, 0.020, 0.0040))
    for side in (-1.0, 1.0):
        box(builder, (side * 0.0088, y + 0.019, z_front), (0.0016, 0.022, 0.0070))
    # Rear sight: base plus the aperture ring.
    rounded_box(builder, (0.0, y + 0.006, z_rear), (0.024, 0.012, 0.036), 0.002)
    box(builder, (0.0, y + 0.020, z_rear), (0.024, 0.020, 0.007))
    tube(builder, (0.0, y + 0.024, z_rear - 0.003), (0.0, y + 0.024, z_rear + 0.003), 0.0055, 12)
    tube(builder, (0.0, y + 0.024, z_rear - 0.004), (0.0, y + 0.024, z_rear + 0.004), 0.0022, 10)


def _trigger_group(builder, z_centre, y_top, depth=0.055):
    """Trigger guard as a closed loop plus the trigger blade and magazine release."""
    guard_outline = [
        (0.0, y_top, z_centre + depth),
        (0.0, y_top - 0.030, z_centre + depth + 0.006),
        (0.0, y_top - 0.042, z_centre),
        (0.0, y_top - 0.036, z_centre - depth),
        (0.0, y_top - 0.008, z_centre - depth - 0.008),
        (0.0, y_top + 0.004, z_centre - depth * 0.3),
    ]
    swept_tube(builder, guard_outline, 0.0032, 8, cap_start=True, cap_end=True)
    # Trigger blade raked back.
    extrude(builder, profile_rounded_rect(0.0034, 0.013, 0.0012, 2), 0.0, 0.007,
            origin=(0.0, y_top - 0.014, z_centre + 0.002), u=(0.0, 1.0, 0.0),
            v=(0.0, 0.0, 1.0), w=(1.0, 0.0, 0.0), cap_start=True, cap_end=True)
    # Magazine release button and safety selector on the left face.
    tube(builder, (-0.019, y_top - 0.006, z_centre + 0.030), (-0.025, y_top - 0.006, z_centre + 0.030), 0.005, 12)
    tube(builder, (0.019, y_top + 0.004, z_centre - 0.020), (0.026, y_top + 0.004, z_centre - 0.020), 0.0045, 12)
    tube(builder, (0.021, y_top + 0.004, z_centre - 0.032), (-0.021, y_top + 0.004, z_centre - 0.032), 0.0018, 8)


def _pistol_grip(builder, z_top, y_top, rake=0.36, length=0.108, half_width=0.016):
    """Raked grip with a palm swell, finger grooves and a texture panel."""
    steps = 5
    frames = []
    for step in range(steps + 1):
        t = step / steps
        centre = (
            0.0,
            y_top - length * t,
            z_top + rake * length * t,
        )
        # Slight taper toward the base; thicker in the middle for a palm swell.
        swell = 1.0 + 0.10 * (1.0 - abs(t - 0.45) * 2.0)
        frames.append((centre,
                       vmul((1.0, 0.0, 0.0), half_width * (0.92 + 0.16 * t) * swell),
                       vmul((0.0, 0.0, 1.0), 0.024 * (0.94 + 0.14 * t)),
                       (0.0, -1.0, rake * 0.0)))
    # Re-derive frames with a proper tangent so the grip rakes smoothly.
    frames = []
    for step in range(steps + 1):
        t = step / steps
        centre = (0.0, y_top - length * t, z_top + rake * length * t)
        swell = 1.0 + 0.10 * (1.0 - abs(t - 0.45) * 2.0)
        tangent = vnorm((0.0, -1.0, rake))
        u, v, w = basis_from_w(tangent)
        frames.append((centre, vmul(u, half_width * (0.92 + 0.16 * t) * swell),
                       vmul(v, 0.024 * (0.94 + 0.14 * t)), w))
    sweep(builder, profile_rounded_rect(1.0, 1.0, 0.35, 3), frames, True, True)
    # Grip texture: shallow horizontal ribs.
    for index in range(5):
        t = 0.2 + index * 0.16
        centre = (0.0, y_top - length * t, z_top + rake * length * t)
        box(builder, centre, (half_width * 2.1, 0.0022, 0.0040))


def _buffer_tube_and_stock(builder, z_front, y_centre, length, style="collapsible"):
    """Buffer tube plus a stock. `collapsible` adds the adjustment notches."""
    tube(builder, (0.0, y_centre, z_front), (0.0, y_centre, z_front + length), 0.0155, 16, steps=3)
    if style == "collapsible":
        for index in range(5):
            offset = z_front + 0.052 + index * 0.016
            tube(builder, (0.0, y_centre - 0.015, offset), (0.0, y_centre - 0.024, offset), 0.0048, 8)
    # Stock body: cheek piece, butt plate and a hollow interior at the rear.
    body_z = z_front + length * 0.52
    rounded_box(builder, (0.0, y_centre - 0.004, body_z), (0.042, 0.062, length * 0.86), 0.010,
                corner_segments=3)
    box(builder, (0.0, y_centre + 0.030, body_z), (0.038, 0.012, length * 0.70))
    butt_z = z_front + length * 0.97
    rounded_box(builder, (0.0, y_centre - 0.012, butt_z), (0.046, 0.082, 0.016), 0.006)
    tube(builder, (0.0, y_centre - 0.012, butt_z + 0.008), (0.0, y_centre - 0.012, butt_z - 0.030), 0.017, 12)
    # Sling loop.
    swept_tube(builder, [(0.0, y_centre - 0.045, body_z + 0.03),
                         (0.0, y_centre - 0.058, body_z + 0.03),
                         (0.0, y_centre - 0.058, body_z - 0.01),
                         (0.0, y_centre - 0.045, body_z - 0.01)], 0.0030, 6)


def _handguard(builder, z_front, z_back, y_centre, half_width, half_height, slots=4, vent_rows=2):
    """Octagonal M-LOK handguard: shell, side slots and vent holes."""
    shell = profile_rounded_rect(half_width, half_height, 0.008, 2)
    sweep(builder, shell,
          [((0.0, y_centre, z_back), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
           ((0.0, y_centre, (z_front + z_back) * 0.5), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
           ((0.0, y_centre, z_front), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))],
          True, True)
    span = abs(z_front - z_back)
    for row in range(vent_rows):
        offset = 0.0 if vent_rows == 1 else (row - (vent_rows - 1) * 0.5) * span * 0.42
        for side in (-1.0, 1.0):
            for index in range(slots):
                along = z_back - (span * (index + 0.5) / slots) * (1.0 if z_front < z_back else -1.0)
                centre = (side * half_width, y_centre + offset, along)
                rounded_box(builder, centre, (0.008, 0.014, 0.026), 0.003)


def _magazine(builder, z_top, y_top, length, curve, half_width, half_depth, style="box"):
    """Curved box magazine with a floorplate and witness ribs."""
    steps = 6
    frames = []
    for step in range(steps + 1):
        t = step / steps
        y = y_top - length * t
        z = z_top + curve * (t ** 2)
        tangent = vnorm((0.0, -1.0, curve * 2.0 * max(t, 0.05)))
        u, v, w = basis_from_w(tangent)
        taper = 1.0 - 0.05 * t
        frames.append((((0.0, y, z)), vmul(u, half_depth * taper), vmul(v, half_width * taper), w))
    sweep(builder, profile_rounded_rect(1.0, 1.0, 0.22, 3), frames, True, True)
    base_y = y_top - length
    base_z = z_top + curve
    rounded_box(builder, (0.0, base_y - 0.004, base_z), (half_depth * 2.3, 0.010, half_width * 2.3), 0.003)
    # Witness ribs down the side.
    for index in range(4):
        t = 0.15 + index * 0.20
        box(builder, (0.0, y_top - length * t, z_top + curve * (t ** 2)), (0.0036, 0.020, 0.0060))
    if style == "drum":
        tube(builder, (0.0, base_y - 0.010, base_z), (0.0, base_y - 0.130, base_z), 0.072, 22, steps=3)
        tube(builder, (0.0, base_y - 0.140, base_z), (0.0, base_y - 0.150, base_z), 0.030, 14, steps=3)


def _bolt_and_handle(builder, z_centre, y_centre, travel=0.045):
    """Bolt carrier visible through the ejection port, plus the charging handle."""
    tube(builder, (0.0, y_centre, z_centre + travel), (0.0, y_centre, z_centre - 0.062), 0.0118, 16, steps=3)
    box(builder, (0.008, y_centre + 0.004, z_centre), (0.014, 0.018, 0.030))
    # Charging handle at the rear of the receiver.
    box(builder, (0.0, y_centre + 0.012, z_centre + 0.070), (0.030, 0.010, 0.036))
    rounded_box(builder, (0.0, y_centre + 0.012, z_centre + 0.092), (0.056, 0.008, 0.016), 0.003)


def _ejection_port(builder, z_centre, y_centre):
    """Raised port frame plus the closed dust cover."""
    for dz in (-0.028, 0.028):
        box(builder, (0.019, y_centre, z_centre + dz), (0.004, 0.026, 0.004))
    rounded_box(builder, (0.020, y_centre - 0.008, z_centre + 0.008), (0.007, 0.018, 0.058), 0.002)


def _gas_block(builder, z_centre, y_centre, height=0.030):
    rounded_box(builder, (0.0, y_centre + height * 0.5, z_centre), (0.026, height, 0.030), 0.004)
    tube(builder, (0.0, y_centre + height - 0.004, z_centre - 0.026), (0.0, y_centre + height - 0.004, z_centre + 0.026), 0.0075, 12)
    # Front sling swivel.
    swept_tube(builder, [(0.0, y_centre - 0.012, z_centre), (0.0, y_centre - 0.024, z_centre - 0.006),
                         (0.0, y_centre - 0.024, z_centre + 0.006)], 0.0026, 6)


def _muzzle_device(builder, z_front, z_back, bore_y, radius=0.0125, ports=4, style="flash"):
    """Flash hider, compensator or suppressor body."""
    tube(builder, (0.0, bore_y, z_back), (0.0, bore_y, z_front), radius, 16, steps=3)
    if style == "flash":
        for index in range(ports):
            along = z_back + (z_front - z_back) * (index + 1) / (ports + 1)
            for side in (-1.0, 1.0):
                tube(builder, (side * radius * 0.3, bore_y, along),
                     (side * radius * 1.15, bore_y, along), 0.0032, 8)
    elif style == "brake":
        for index in range(ports):
            along = z_back + (z_front - z_back) * (index + 1) / (ports + 1)
            box(builder, (0.0, bore_y, along), (radius * 2.3, 0.010, 0.0032))
    # Crowned bore.
    tube(builder, (0.0, bore_y, z_front), (0.0, bore_y, z_front - 0.004), 0.0082, 14)
    tube(builder, (0.0, bore_y, z_front - 0.004), (0.0, bore_y, z_front - 0.060), 0.0052, 14, cap_end=False)


def _rail_mounted_optic(builder, z_centre, y_base, kind):
    """Optic body shared by red dot, holographic and magnified sights."""
    if kind == "reddot":
        body_height = 0.040
        rounded_box(builder, (0.0, y_base + 0.030, z_centre), (0.030, body_height, 0.062), 0.005)
        tube(builder, (0.0, y_base + 0.034, z_centre - 0.030), (0.0, y_base + 0.034, z_centre + 0.030), 0.019, 18, cap_start=False, cap_end=False)
        tube(builder, (0.0, y_base + 0.034, z_centre - 0.031), (0.0, y_base + 0.034, z_centre - 0.028), 0.019, 18)
        tube(builder, (0.0, y_base + 0.034, z_centre + 0.028), (0.0, y_base + 0.034, z_centre + 0.031), 0.019, 18)
        _lens(builder, z_centre - 0.032, y_base + 0.034, 0.017, glass=True)
        _lens(builder, z_centre + 0.032, y_base + 0.034, 0.015, glass=True, flip=True)
        _reticle(builder, z_centre - 0.028, y_base + 0.034)
        # Adjustment turrets.
        tube(builder, (0.0, y_base + 0.054, z_centre), (0.0, y_base + 0.062, z_centre), 0.008, 12)
        tube(builder, (0.0, y_base + 0.034, z_centre + 0.0), (0.019, y_base + 0.034, z_centre), 0.0075, 12)
    elif kind == "holo":
        rounded_box(builder, (0.0, y_base + 0.032, z_centre), (0.034, 0.040, 0.056), 0.006)
        box(builder, (0.0, y_base + 0.056, z_centre + 0.006), (0.036, 0.014, 0.030))
        _lens(builder, z_centre - 0.028, y_base + 0.036, 0.018, glass=True)
        _reticle(builder, z_centre - 0.022, y_base + 0.036)
        tube(builder, (0.0, y_base + 0.032, z_centre + 0.028), (0.0, y_base + 0.032, z_centre + 0.034), 0.012, 14)
    else:  # acog
        rounded_box(builder, (0.0, y_base + 0.034, z_centre), (0.032, 0.044, 0.070), 0.006)
        tube(builder, (0.0, y_base + 0.040, z_centre - 0.045), (0.0, y_base + 0.040, z_centre + 0.045), 0.020, 18, steps=3)
        tube(builder, (0.0, y_base + 0.040, z_centre - 0.049), (0.0, y_base + 0.040, z_centre - 0.044), 0.023, 18)
        tube(builder, (0.0, y_base + 0.040, z_centre + 0.044), (0.0, y_base + 0.040, z_centre + 0.049), 0.022, 18)
        _lens(builder, z_centre - 0.050, y_base + 0.040, 0.020, glass=True)
        _lens(builder, z_centre + 0.050, y_base + 0.040, 0.018, glass=True, flip=True)
        _reticle(builder, z_centre - 0.046, y_base + 0.040)
        _picatinny(builder, z_centre - 0.034, z_centre + 0.034, y_base - 0.004, 0.0105, 7)
        # Fibre-optic light pipe along the top.
        tube(builder, (0.0, y_base + 0.062, z_centre - 0.030), (0.0, y_base + 0.062, z_centre + 0.030), 0.0028, 10)
    _picatinny(builder, z_centre - 0.030, z_centre + 0.030, y_base - 0.004, 0.0105, 6)


def _lens(builder, z, y, radius, glass=False, flip=False):
    """Optic lens: a shallow domed disc seated in the tube."""
    builder_circle = profile_circle(radius, 18)
    sign = -1.0 if flip else 1.0
    apex = z + sign * 0.004
    for index in range(len(builder_circle)):
        a = builder_circle[index]
        b = builder_circle[(index + 1) % len(builder_circle)]
        builder.triangle((a[0], y + a[1], z), (b[0], y + b[1], z), (0.0, y, apex))


def _reticle(builder, z, y):
    """Emissive dot with the surrounding ring, which is what reads as a sight."""
    tube(builder, (0.0, y, z - 0.0014), (0.0, y, z + 0.0014), 0.0034, 12)
    for index in range(4):
        import math as _math
        angle = index * _math.pi / 2.0
        dx = 0.0130 * _math.cos(angle)
        dy = 0.0130 * _math.sin(angle)
        rounded_box(builder, (dx, y + dy, z), (0.0022, 0.0022, 0.0022), 0.0006)


# --------------------------------------------------------------------------
# Pistol. A slide riding on a frame: the two assemblies, a rail, a real bore,
# the magazine inside the grip and the iron sights.
# --------------------------------------------------------------------------

def _build_pistol(spec, prefix, receiver_len, receiver_h, receiver_w, bore_y,
                  z_front, z_rear, half_w, z_muzzle_back):
    parts = []
    slide_top = receiver_h * 0.5

    # ---- Slide: chamfered body, serrations, ejection port, barrel hood -------
    slide = Builder()
    rounded_box(slide, (0.0, 0.006, 0.0), (receiver_w, receiver_h, receiver_len), 0.005,
                corner_segments=4)
    # Cocking serrations at the rear.
    for index in range(6):
        z = z_rear - 0.016 - index * 0.010
        box(slide, (0.0, 0.007, z), (receiver_w + 0.0016, receiver_h * 0.72, 0.0034))
    # Rear sight dovetail and front post.
    rounded_box(slide, (0.0, slide_top + 0.006, z_rear - 0.014), (0.022, 0.010, 0.012), 0.002)
    box(slide, (0.0, slide_top + 0.019, z_rear - 0.014), (0.020, 0.016, 0.005))
    rounded_box(slide, (0.0, slide_top + 0.005, z_front + 0.014), (0.012, 0.009, 0.010), 0.002)
    box(slide, (0.0, slide_top + 0.016, z_front + 0.014), (0.0016, 0.014, 0.0036))
    # Ejection port on the right, with the barrel hood visible through it.
    rounded_box(slide, (half_w + 0.001, slide_top - 0.006, z_front + 0.042),
                (0.006, 0.014, 0.040), 0.002)
    # Top serrations / lightening cuts.
    for index in range(3):
        box(slide, (0.0, slide_top + 0.0015, z_rear - 0.052 - index * 0.016),
            (receiver_w * 0.6, 0.0030, 0.0060))
    parts.append((prefix + "slide", "ds_wsteel", slide))

    # ---- Frame, dust cover, accessory rail -----------------------------------
    frame = Builder()
    rounded_box(frame, (0.0, -receiver_h * 0.5 - 0.004, z_front + 0.030),
                (receiver_w * 0.94, 0.020, receiver_len * 0.72), 0.004)
    _picatinny(frame, z_front - 0.004, z_front + 0.058, -receiver_h * 0.5 - 0.016,
               0.0090, 5)
    # Trigger guard, trigger and controls.
    _trigger_group(frame, z_front + 0.062, -receiver_h * 0.5 - 0.004, 0.042)
    rounded_box(frame, (-half_w - 0.003, -0.004, z_rear - 0.030), (0.008, 0.014, 0.024), 0.002)
    tube(frame, (half_w + 0.002, 0.000, z_rear - 0.024), (half_w + 0.008, 0.000, z_rear - 0.024),
         0.0052, 12)
    parts.append((prefix + "frame", "ds_wpolymer", frame))

    # ---- Grip: integrated with the frame, so a real pistol's grip angle ------
    grip = Builder()
    _pistol_grip(grip, z_rear - 0.020, -receiver_h * 0.5 - 0.012, 0.34,
                 spec["pistol_len"], half_w * 0.98)
    # Beavertail tang above the web of the hand.
    rounded_box(grip, (0.0, -0.004, z_rear - 0.006), (receiver_w * 0.8, 0.014, 0.034), 0.005)
    parts.append((prefix + "grip", "ds_wpolymer", grip))

    # ---- Magazine inside the grip -------------------------------------------
    mag_len, mag_curve = spec["magazine"]
    magazine = Builder()
    _magazine(magazine, z_rear - 0.020 - 0.020, -receiver_h * 0.5 - 0.040,
              mag_len, mag_curve, half_w * 0.90, 0.019, "box")
    parts.append((prefix + "magazine", "ds_wpolymer", magazine))

    # ---- Barrel and muzzle --------------------------------------------------
    barrel = Builder()
    tube(barrel, (0.0, bore_y, z_muzzle_back), (0.0, bore_y, z_front + 0.010), 0.0080, 16, steps=3)
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.004), (0.0, bore_y, z_front + 0.006),
         0.0052, 14, cap_start=False, cap_end=False)
    parts.append((prefix + "barrel", "ds_wsteel", barrel))

    device = Builder()
    _muzzle_device(device, z_muzzle_back - 0.030, z_muzzle_back - 0.006, bore_y, 0.0090, 3, "brake")
    parts.append((prefix + "muzzle_device", "ds_wsteel", device))

    # ---- Recoil spring guide and takedown lever -----------------------------
    internals = Builder()
    rounded_box(internals, (0.0, -receiver_h * 0.5 - 0.002, z_front + 0.052),
                (receiver_w * 0.7, 0.012, 0.030), 0.003)
    tube(internals, (-half_w - 0.002, -0.002, z_front + 0.028), (half_w + 0.002, -0.002, z_front + 0.028),
         0.0038, 10)
    parts.append((prefix + "internals", "ds_wblack", internals))
    return parts


SPECS = {
    "assault": dict(receiver=(0.150, 0.046, 0.038), handguard=(0.300, 0.024, 0.026),
                    barrel_len=0.170, stock_len=0.280, magazine=(0.190, 0.070),
                    optic="reddot", pistol_len=0.108, bore_y=0.006),
    "smg": dict(receiver=(0.135, 0.050, 0.036), handguard=(0.170, 0.022, 0.024),
                barrel_len=0.095, stock_len=0.215, magazine=(0.200, 0.085),
                optic="reddot", pistol_len=0.100, bore_y=0.005),
    "lmg": dict(receiver=(0.200, 0.060, 0.046), handguard=(0.240, 0.026, 0.030),
                barrel_len=0.230, stock_len=0.300, magazine=(0.150, 0.060),
                optic="holo", pistol_len=0.110, bore_y=0.008, drum=True, bipod=True),
    "marksman": dict(receiver=(0.180, 0.052, 0.040), handguard=(0.300, 0.026, 0.028),
                     barrel_len=0.230, stock_len=0.320, magazine=(0.170, 0.062),
                     optic="acog", pistol_len=0.110, bore_y=0.007),
    "sniper": dict(receiver=(0.190, 0.056, 0.042), handguard=(0.250, 0.026, 0.028),
                   barrel_len=0.400, stock_len=0.360, magazine=(0.120, 0.050),
                   optic="acog", pistol_len=0.112, bore_y=0.008, bipod=True),
    "shotgun": dict(receiver=(0.160, 0.056, 0.044), handguard=(0.150, 0.030, 0.032),
                    barrel_len=0.400, stock_len=0.300, magazine=(0.110, 0.045),
                    optic=None, pistol_len=0.104, bore_y=0.010, pump=True),
    "launcher": dict(receiver=(0.200, 0.062, 0.052), handguard=(0.240, 0.040, 0.040),
                     barrel_len=0.420, stock_len=0.300, magazine=(0.100, 0.040),
                     optic=None, pistol_len=0.104, bore_y=0.010, rocket=True),
    # Pistols reuse the receiver/handguard/slide pipeline with a short barrel and
    # no stock; `stock_len` is consumed by the slide cap instead.
    "pistol": dict(receiver=(0.170, 0.038, 0.030), handguard=(0.030, 0.017, 0.015),
                   barrel_len=0.020, stock_len=0.055, magazine=(0.110, 0.020),
                   optic=None, pistol_len=0.096, bore_y=0.006, pistol=True),
}


def build_rifle(category, prefix):
    """Returns a list of `(node_name, material_key, geometry_id, builder)` parts."""
    spec = SPECS[category]
    receiver_len, receiver_h, receiver_w = spec["receiver"]
    half_w = receiver_w * 0.5
    bore_y = spec["bore_y"]
    receiver_top = receiver_h * 0.5
    receiver_bottom = -receiver_h * 0.5

    z_rear = receiver_len * 0.5
    z_front = -receiver_len * 0.5
    handguard_len, hg_half_w, hg_half_h = spec["handguard"]
    z_hg_front = z_front - handguard_len
    barrel_len = spec["barrel_len"]
    z_muzzle_back = z_hg_front - barrel_len
    stock_len = spec["stock_len"]
    z_stock_back = z_rear + stock_len

    if spec.get("pistol"):
        return _build_pistol(spec, prefix, receiver_len, receiver_h, receiver_w, bore_y,
                             z_front, z_rear, half_w, z_muzzle_back)

    parts = []

    # ---- Receiver: lower with magazine well, upper with the rail -------------
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (receiver_w, receiver_h, receiver_len), 0.006,
                corner_segments=4)
    # Slight upper/lower split line.
    box(body, (0.0, 0.002, 0.0), (receiver_w + 0.0014, 0.0022, receiver_len * 0.98))
    # Magwell flare at the front of the lower.
    rounded_box(body, (0.0, receiver_bottom - 0.008, z_front + 0.020),
                (receiver_w * 1.08, 0.030, 0.058), 0.005)
    # Front pivot pin and rear takedown pin.
    for z in (z_front + 0.012, z_rear - 0.016):
        tube(body, (-half_w - 0.002, -0.004, z), (half_w + 0.002, -0.004, z), 0.0034, 10)
    # Bolt catch / selector paddles on the left face.
    rounded_box(body, (-half_w - 0.004, 0.004, z_front + 0.052), (0.008, 0.014, 0.030), 0.002)
    parts.append((prefix + "receiver", "ds_wbody", body))

    # ---- Handguard ----------------------------------------------------------
    guard = Builder()
    _handguard(guard, z_hg_front, z_front + 0.004, bore_y, hg_half_w, hg_half_h,
               slots=5, vent_rows=2)
    parts.append((prefix + "handguard", "ds_wbody", guard))

    # ---- Top rail spanning receiver and handguard ---------------------------
    rail_builder = Builder()
    _picatinny(rail_builder, z_front + 0.002, z_rear - 0.004, receiver_top + 0.0035,
               0.0105, 12)
    parts.append((prefix + "rail", "ds_wsteel", rail_builder))

    # ---- Barrel, gas block, muzzle -----------------------------------------
    barrel = Builder()
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.030), (0.0, bore_y, z_hg_front + 0.010),
         0.0092, 16, steps=4)
    tube(barrel, (0.0, bore_y, z_hg_front + 0.010), (0.0, bore_y, z_front), 0.0120, 16, steps=3)
    parts.append((prefix + "barrel", "ds_wsteel", barrel))

    gas = Builder()
    _gas_block(gas, bore_y + hg_half_h + 0.014, bore_y, 0.026)
    parts.append((prefix + "gas_block", "ds_wsteel", gas))

    device = Builder()
    _muzzle_device(device, z_muzzle_back - 0.062, z_muzzle_back - 0.020, bore_y,
                   0.0130, 4, "flash" if category != "shotgun" else "brake")
    parts.append((prefix + "muzzle_device", "ds_wsteel", device))

    # ---- Bolt carrier, charging handle, ejection port ----------------------
    bolt = Builder()
    _bolt_and_handle(bolt, z_rear - 0.048, bore_y + 0.004, 0.040)
    parts.append((prefix + "bolt", "ds_wsteel", bolt))

    port = Builder()
    _ejection_port(port, z_front + 0.058, bore_y + 0.002)
    parts.append((prefix + "port", "ds_wblack", port))

    # ---- Trigger group ------------------------------------------------------
    trigger = Builder()
    _trigger_group(trigger, z_front + 0.058, receiver_bottom + 0.002, 0.048)
    parts.append((prefix + "trigger", "ds_wsteel", trigger))

    # ---- Pistol grip --------------------------------------------------------
    grip = Builder()
    _pistol_grip(grip, z_rear - 0.028, receiver_bottom - 0.002, 0.34, spec["pistol_len"], half_w)
    parts.append((prefix + "grip", "ds_wpolymer", grip))

    # ---- Magazine -----------------------------------------------------------
    mag_len, mag_curve = spec["magazine"]
    magazine = Builder()
    _magazine(magazine, z_front + 0.028, receiver_bottom - 0.026, mag_len, mag_curve,
              half_w * 0.92, 0.030, "drum" if spec.get("drum") else "box")
    parts.append((prefix + "magazine", "ds_wpolymer", magazine))

    # ---- Stock --------------------------------------------------------------
    stock = Builder()
    _buffer_tube_and_stock(stock, z_rear - 0.006, bore_y + 0.006, stock_len * 0.94,
                           "collapsible" if category in ("assault", "smg") else "fixed")
    parts.append((prefix + "stock", "ds_wpolymer", stock))

    # ---- Sights and optic ---------------------------------------------------
    sights = Builder()
    _iron_sights(sights, z_front - 0.010, z_rear - 0.014, receiver_top + 0.004)
    parts.append((prefix + "sights", "ds_wsteel", sights))

    if spec.get("optic"):
        optic = Builder()
        _rail_mounted_optic(optic, z_front + 0.030, receiver_top + 0.007, spec["optic"])
        parts.append((prefix + "optic", "ds_wblack", optic))
        glass = Builder()
        glass_len = 0.070 if spec["optic"] == "acog" else 0.064
        _lens(glass, z_front + 0.030 - glass_len * 0.5, receiver_top + 0.041,
              0.019 if spec["optic"] == "acog" else 0.017, glass=True)
        parts.append((prefix + "lens", "ds_wglass", glass))
        dot = Builder()
        _reticle(dot, z_front + 0.030 - glass_len * 0.47, receiver_top + 0.041)
        parts.append((prefix + "reticle", "ds_wreticle", dot))

    # ---- Bipod (LMG / sniper) ----------------------------------------------
    if spec.get("bipod"):
        bipod = Builder()
        base = (0.0, -0.030, z_hg_front + 0.040)
        rounded_box(bipod, base, (0.020, 0.018, 0.030), 0.003)
        for side in (-1.0, 1.0):
            leg = [(0.0, -0.030, z_hg_front + 0.040),
                   (side * 0.030, -0.090, z_hg_front + 0.030),
                   (side * 0.042, -0.150, z_hg_front + 0.010)]
            swept_tube(bipod, leg, 0.0055, 10)
            box(bipod, (side * 0.046, -0.158, z_hg_front + 0.004), (0.012, 0.014, 0.020))
        parts.append((prefix + "bipod", "ds_wsteel", bipod))

    # ---- Pump / tube magazine (shotgun) ------------------------------------
    if spec.get("pump"):
        pump = Builder()
        tube(pump, (0.0, bore_y - 0.030, z_muzzle_back - 0.030), (0.0, bore_y - 0.030, z_hg_front + 0.030),
             0.0140, 16, steps=3)
        for index in range(6):
            along = z_hg_front + 0.030 + index * 0.032
            tube(pump, (0.0, bore_y - 0.030, along - 0.008), (0.0, bore_y - 0.030, along + 0.008),
                 0.0165, 14)
        parts.append((prefix + "pump", "ds_wpolymer", pump))

    # ---- Rocket (launcher) --------------------------------------------------
    if spec.get("rocket"):
        rocket = Builder()
        tube(rocket, (0.0, bore_y, z_hg_front - 0.230), (0.0, bore_y, z_hg_front + 0.020),
             0.038, 20, steps=3)
        cone_builder = Builder()
        tube(cone_builder, (0.0, bore_y, z_hg_front - 0.230), (0.0, bore_y, z_hg_front - 0.300),
             0.038, 20, radius_end=0.014, cap_end=True)
        parts.append((prefix + "tube", "ds_wbody", rocket))
        parts.append((prefix + "cone", "ds_wbody", cone_builder))

    return parts


# --------------------------------------------------------------------------
# Attachments. Each category gets its own geometry so an optic mounted on a
# pistol does not share an assault rifle's receiver-relative offset.
# --------------------------------------------------------------------------

def build_attachment(category, kind, prefix):
    spec = SPECS[category]
    receiver_len, receiver_h, receiver_w = spec["receiver"]
    receiver_top = receiver_h * 0.5
    z_centre = -receiver_len * 0.5 + receiver_len * 0.20
    rail_y = receiver_top + 0.007

    if kind in ("reddot", "holo", "acog"):
        body = Builder()
        _rail_mounted_optic(body, z_centre, rail_y, kind)
        glass_len = 0.070 if kind == "acog" else 0.064
        glass = Builder()
        _lens(glass, z_centre - glass_len * 0.5, rail_y + 0.034 +
              (0.006 if kind != "holo" else 0.002), 0.019 if kind == "acog" else 0.017, glass=True)
        dot = Builder()
        _reticle(dot, z_centre - glass_len * 0.47, rail_y + 0.034 +
                 (0.006 if kind != "holo" else 0.002))
        return [(prefix + "body", "ds_wblack", body),
                (prefix + "lens", "ds_wglass", glass),
                (prefix + "reticle", "ds_wreticle", dot)]

    if kind in ("compensator", "muzzlebrake", "suppressor", "longbarrel"):
        z_muzzle_back = -receiver_len * 0.5 - spec["handguard"][0] - spec["barrel_len"]
        barrel = Builder()
        if kind == "longbarrel":
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.140),
                 (0.0, spec["bore_y"], z_muzzle_back + 0.010), 0.0092, 16, steps=3)
        parts = [(prefix + "barrel", "ds_wsteel", barrel)]
        device = Builder()
        if kind == "suppressor":
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.180),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.010), 0.0205, 20, steps=4)
            for index in range(5):
                along = z_muzzle_back - 0.030 - index * 0.030
                tube(device, (0.0, spec["bore_y"], along - 0.006), (0.0, spec["bore_y"], along + 0.006),
                     0.0215, 18)
        else:
            _muzzle_device(device, z_muzzle_back - 0.062, z_muzzle_back - 0.016, spec["bore_y"],
                           0.0130, 4, "brake" if kind == "muzzlebrake" else "flash")
        parts.append((prefix + "device", "ds_wsteel", device))
        return parts

    if kind in ("extmag", "drum"):
        mag_len, mag_curve = spec["magazine"]
        length = mag_len * (1.45 if kind == "extmag" else 1.0)
        body = Builder()
        _magazine(body, z_centre, -receiver_h * 0.5 - 0.026, length, mag_curve,
                  receiver_w * 0.46, 0.030, "drum" if kind == "drum" else "box")
        return [(prefix + "magazine", "ds_wpolymer", body)]

    if kind in ("foregrip", "angledgrip"):
        grip = Builder()
        base_y = -receiver_h * 0.5 - spec["handguard"][2] - 0.004
        z_grip = -receiver_len * 0.5 - spec["handguard"][0] * 0.45
        if kind == "foregrip":
            _pistol_grip(grip, z_grip, base_y, 0.06, 0.088, 0.014)
        else:
            _pistol_grip(grip, z_grip, base_y, 0.62, 0.082, 0.014)
        return [(prefix + "grip", "ds_wpolymer", grip)]

    if kind == "heavystock":
        stock = Builder()
        _buffer_tube_and_stock(stock, receiver_len * 0.5 - 0.006, spec["bore_y"] + 0.006,
                               spec["stock_len"] * 1.02, "fixed")
        return [(prefix + "stock", "ds_wpolymer", stock)]

    if kind == "laser":
        body = Builder()
        z_laser = -receiver_len * 0.5 - spec["handguard"][0] * 0.70
        y_laser = -receiver_h * 0.5 - spec["handguard"][2] - 0.006
        rounded_box(body, (0.0, y_laser, z_laser), (0.022, 0.020, 0.056), 0.005)
        tube(body, (0.0, y_laser, z_laser - 0.028), (0.0, y_laser, z_laser - 0.036), 0.0085, 14)
        rounded_box(body, (0.0, y_laser - 0.004, z_laser + 0.020), (0.014, 0.010, 0.014), 0.002)
        emitter = Builder()
        tube(emitter, (0.0, y_laser, z_laser - 0.036), (0.0, y_laser, z_laser - 0.039), 0.0072, 12)
        return [(prefix + "body", "ds_wblack", body),
                (prefix + "emitter", "ds_wreticle", emitter)]

    return []


# --------------------------------------------------------------------------
# Knife. The viewmodel uses the same `gun`/`knife`/`muzzle` pivots.
# --------------------------------------------------------------------------

def build_knife(prefix):
    """Blade along +Y, which is the axis the melee pivot sweeps.

    `Combatant._update_viewmodel` rotates the knife pivot about Z through 2.4 rad
    to swipe, and the ported blade ran along local +Y. Building it the same way
    keeps the swipe animation identical while the blade itself becomes a real
    tapered flat with a ricasso, swedge, guard and sculpted handle.
    """
    blade = Builder()
    # (z offset from the pivot, half-thickness, spine height) from tip to ricasso.
    stations = [
        (0.235, 0.0006, 0.0000),
        (0.190, 0.0012, 0.0060),
        (0.130, 0.0018, 0.0110),
        (0.070, 0.0022, 0.0130),
        (0.020, 0.0024, 0.0126),
        (0.000, 0.0024, 0.0110),
    ]
    edge_offsets = [0.0, -0.050, -0.036, -0.026, -0.014, -0.004]
    for index in range(len(stations) - 1):
        z0, half0, spine0 = stations[index]
        z1, half1, spine1 = stations[index + 1]
        e0 = edge_offsets[index]
        e1 = edge_offsets[index + 1]
        for side in (-1.0, 1.0):
            # Four rails across the blade: spine, upper flat, lower flat, edge.
            spine_a = (side * half0 * 0.30, z0, e0 + spine0)
            spine_b = (side * half1 * 0.30, z1, e1 + spine1)
            flat_a = (side * half0, z0, e0 + spine0 * 0.55)
            flat_b = (side * half1, z1, e1 + spine1 * 0.55)
            root_a = (side * half0, z0, e0 + spine0 * 0.18)
            root_b = (side * half1, z1, e1 + spine1 * 0.18)
            edge_a = (side * half0 * 0.10, z0, e0)
            edge_b = (side * half1 * 0.10, z1, e1)
            if side > 0:
                blade.quad(spine_a, flat_a, flat_b, spine_b)
                blade.quad(flat_a, root_a, root_b, flat_b)
                blade.quad(root_a, edge_a, edge_b, root_b)
            else:
                blade.quad(spine_b, flat_b, flat_a, spine_a)
                blade.quad(flat_b, root_b, root_a, flat_a)
                blade.quad(root_b, edge_b, edge_a, root_a)
        # Spine and edge sheets close the solid.
        if index == 0:
            blade.quad((stations[0][1] * 0.30, z0, e0 + spine0),
                       (-stations[0][1] * 0.30, z0, e0 + spine0),
                       (-stations[0][1] * 0.10, z0, e0),
                       (stations[0][1] * 0.10, z0, e0))
    parts = [(prefix + "blade", "ds_wbright", blade)]

    guard = Builder()
    rounded_box(guard, (0.0, 0.020, -0.006), (0.014, 0.020, 0.016), 0.004)
    box(guard, (0.0, -0.006, 0.000), (0.008, 0.030, 0.010))
    parts.append((prefix + "guard", "ds_wblack", guard))

    handle = Builder()
    steps = 5
    frames = []
    for step in range(steps + 1):
        t = step / steps
        z = -0.034 - t * 0.118
        swell = 1.0 + 0.14 * (1.0 - abs(t - 0.4) * 2.0)
        frames.append(((0.0, 0.0, z), vmul((1.0, 0.0, 0.0), 0.0135 * swell),
                       vmul((0.0, 1.0, 0.0), 0.0180 * swell), (0.0, 0.0, -1.0)))
    sweep(handle, profile_rounded_rect(1.0, 1.0, 0.45, 3), frames, True, True)
    for index in range(4):
        t = 0.22 + index * 0.18
        box(handle, (0.0, 0.0, -0.034 - t * 0.118), (0.0290, 0.0024, 0.0070))
    tube(handle, (0.0, 0.0, -0.156), (0.0, 0.0, -0.162), 0.0035, 10)
    parts.append((prefix + "handle", "ds_wpolymer", handle))

    pommel = Builder()
    rounded_box(pommel, (0.0, 0.0, -0.166), (0.020, 0.026, 0.014), 0.004)
    parts.append((prefix + "pommel", "ds_wsteel", pommel))
    return parts


def build_all(categories, attachment_kinds):
    """Returns `(models, geometries)` keyed by asset id.

    Node hierarchy keeps the contract the ported assets established: a root, an
    empty `gun` pivot owning every solid part, an empty `muzzle` pivot at the
    bore exit, and an empty, initially hidden `knife` pivot holding the melee
    blade. `VisualFactory.part()` and the gameplay code address those by name,
    and `Combatant._update_viewmodel` drives the melee purely through the knife
    pivot's local transform.
    """
    models = {}
    geometries = {}
    counter = 0

    def geometry_for(builder):
        nonlocal counter
        if builder.count_triangles() == 0:
            return None
        geometry_id = "geometry_%d" % counter
        counter += 1
        geometries[geometry_id] = builder.record()
        return geometry_id

    def assembly(asset_id, prefix, parts, muzzle, knife=None):
        nodes = [_empty(asset_id, -1), _empty("gun", 0)]
        for name, material_key, builder in parts:
            geometry_id = geometry_for(builder)
            if geometry_id is not None:
                nodes.append(_mesh(prefix + name, geometry_id, material_key, parent=1))
        nodes.append(_empty("muzzle", 1, muzzle))
        nodes.append(_empty("knife", 0, visible=False))
        knife_index = len(nodes) - 1
        for name, material_key, builder in (knife or build_knife(prefix)):
            geometry_id = geometry_for(builder)
            if geometry_id is not None:
                nodes.append(_mesh(prefix + name, geometry_id, material_key,
                                   parent=knife_index))
        models[asset_id] = {"nodes": nodes}

    # The held knife is a rifle-shaped asset whose `gun` pivot carries the blade,
    # so the factory, camo tinting and muzzle pivot all keep working.
    for category in categories:
        spec = SPECS[category]
        muzzle = (0.0, spec["bore_y"],
                  -(spec["receiver"][0] * 0.5 + spec["handguard"][0] + spec["barrel_len"] + 0.060))
        assembly("weapon_" + category, category + "__", build_rifle(category, category + "__"), muzzle)

    knife_parts = build_knife("knife__")
    # The held knife shows its blade through the always-visible `gun` pivot, and
    # carries a second copy under the hidden `knife` pivot so a rifle's melee
    # swing can reveal it. That mirrors the ported asset, which also built the
    # blade twice.
    assembly("weapon_knife", "knife__", knife_parts, (0.0, 0.02, -0.30),
             knife=knife_parts)

    for category in categories:
        for kind in attachment_kinds.get(category, []):
            parts = build_attachment(category, kind, category + "_" + kind + "__")
            if not parts:
                continue
            nodes = [{"name": "attachment_" + category + "_" + kind, "geometry": None,
                      "matrix": _identity(), "visible": True, "castShadow": False,
                      "parent": -1}]
            for name, material_key, builder in parts:
                geometry_id = geometry_for(builder)
                if geometry_id is None:
                    continue
                nodes.append(_mesh(category + "_" + kind + "__" + name, geometry_id,
                                   material_key, parent=-1))
            models["attachment_" + category + "_" + kind] = {"nodes": nodes}
    return models, geometries


def _identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def _empty(name, parent, position=(0.0, 0.0, 0.0), visible=True):
    # `material` is omitted rather than nulled: the Blender manifest step keeps
    # whichever keys a node actually has, and the factory treats a present-but-
    # null material as a lookup key.
    return {
        "name": name, "geometry": None,
        "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, position[0], position[1], position[2], 1],
        "visible": visible, "castShadow": False, "parent": parent,
    }


def _mesh(name, geometry_id, material_key, parent=-1):
    return {
        "name": name, "geometry": geometry_id, "material": material_key,
        "matrix": _identity(), "visible": True, "castShadow": False, "parent": parent,
    }
