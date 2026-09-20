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

import math

from deadshot_detail import (
    Builder, basis_from_w, box, extrude, lerp3, profile_circle,
    profile_rounded_rect, profile_taper, rail, rounded_box, sweep, swept_tube,
    tube, vadd, vcross, vdot, vmul, vsub, vnorm,
)

TAU = math.tau

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
# Small hardware. Every panel join, rail clamp and optic mount on a real
# firearm is held together by visible fasteners, and those catches of light are
# what separate an asset from a CAD block. These emit a screw head (a short
# proud tube plus a slot or hex recess), a pin (a tube spanning a gap with a
# proud head at each end), a hex bolt, an M-LOK slot and a knurled ring, so a
# caller can sprinkle believable detail along a seam without restating winding
# or axis frames.
# --------------------------------------------------------------------------

def _screw_head(builder, centre, axis, radius=0.0032, length=0.0034, hex_recess=False):
    """Short proud cylinder with a screwdriver slot or a hex recess in the face.

    The shank runs 3 mm back past the head's centre so the head always bites
    into whatever it is fastening. A head that only just reaches its host is a
    floating disc the moment the caller's centre is a fraction off the surface,
    which is exactly what happens all over a receiver with its panel lines.
    """
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    base = vsub(centre, vmul(w, length * 0.5 + 0.0030))
    face = vadd(centre, vmul(w, length * 0.5))
    tube(builder, base, face, radius, 12)
    if hex_recess:
        tube(builder, vsub(face, vmul(w, 0.0016)), vadd(face, vmul(w, 0.0004)),
             radius * 0.48, 6, cap_start=False)
    else:
        # A slot slab sunk into the head, lying in the face plane.
        extrude(builder, profile_rounded_rect(radius * 0.70, radius * 0.17, 0.0, 1),
                -0.0014, 0.0006, origin=face, u=u, v=v, w=w)


def _pin(builder, start, end, radius=0.0028, head=0.0018):
    """Pin spanning a gap between two parts, proud at both ends."""
    axis = vnorm(vsub(end, start))
    tube(builder, start, end, radius, 12)
    for point, sign in ((start, -1.0), (end, 1.0)):
        tube(builder, point, vadd(point, vmul(axis, head * sign)), radius * 1.45, 12)


def _hex_bolt(builder, centre, axis, radius=0.0042, length=0.0060):
    """Hex-head bolt, seated with a 3 mm bite into its host like `_screw_head`."""
    w = vnorm(axis)
    base = vsub(centre, vmul(w, length * 0.5 + 0.0030))
    tube(builder, base, vadd(centre, vmul(w, length * 0.5)), radius, 6)


def _knurl(builder, centre, axis, ring_radius, length, ribs=12):
    """Ring of radial knurling ribs, which is how turrets and rings read.

    Each rib is sunk 1 mm into the host before standing proud, so a caller whose
    `ring_radius` is a little larger than the host's actual radius still has the
    rib registered on the surface instead of hovering beside it.
    """
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    for index in range(ribs):
        angle = TAU * index / ribs
        radial = vnorm(vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle))))
        extrude(builder, profile_rounded_rect(length * 0.5, 0.0009, 0.0003, 1),
                -0.0016, 0.0015, origin=vadd(centre, vmul(radial, ring_radius)),
                u=w, v=vcross(w, radial), w=radial)


def _graduations(builder, centre, axis, ring_radius, count, span=1.9):
    """Radial tick marks: the witness detail on every optic turret.

    Sunk 1.6 mm into the host for the same reason as `_knurl`: a tick that does
    not reach its host is a floating fleck of geometry, which is worse than no
    tick at all.
    """
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    for index in range(count):
        angle = -span * 0.5 + span * index / max(1, count - 1)
        radial = vnorm(vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle))))
        half_len = 0.0026 if index % 5 == 0 else 0.0015
        extrude(builder, profile_rounded_rect(half_len, 0.00045, 0.0, 1), -0.0016, 0.0008,
                origin=vadd(centre, vmul(radial, ring_radius)), u=w,
                v=vcross(w, radial), w=radial)


def _mlok_slot(builder, centre, axis):
    """Recessed M-LOK slot with rounded ends plus the lip it clamps against.

    The cross-section is a rounded rectangle extruded along `axis`, so its first
    coordinate spans the slot's *width* and its second spans its *length*. The
    lips belong at the two rounded ends, i.e. offset along the length axis, so
    the length axis is built explicitly from the slot's own direction rather
    than taken from `basis_from_w`, whose `u` is an arbitrary reference-derived
    tangent (for a normal pointing up, `u` points straight up as well, which
    would displace the lip off the surface instead of along the slot).
    """
    w = vnorm(axis)
    # `u` spans the slot width, `v` runs along the slot. Picking the reference
    # from the world up-axis gives a stable, predictable pair for every slot
    # orientation we use (side, top and underside faces).
    reference = (0.0, 0.0, 1.0) if abs(vdot(w, (0.0, 0.0, 1.0))) < 0.9 else (1.0, 0.0, 0.0)
    u = vnorm(vcross(reference, w))
    v = vcross(w, u)
    # The slot is sunk 2.5 mm into the host: the recess reads as a pocket, and
    # the lip always reaches the surface even where the host is curved or the
    # caller's centre sits a fraction off it.
    extrude(builder, profile_rounded_rect(0.0034, 0.0106, 0.0033, 3), -0.0025, 0.0006,
            origin=centre, u=u, v=v, w=w)
    for sign in (-1.0, 1.0):
        extrude(builder, profile_rounded_rect(0.0008, 0.0114, 0.0007, 1), -0.0015, 0.0017,
                origin=vadd(centre, vmul(v, sign * 0.0043)), u=u, v=v, w=w)


def _sling_loop(builder, centre, axis=(0.0, 0.0, 1.0), radius=0.0058):
    """Closed sling loop: an open bracket with a swept ring through it.

    `radius` is the loop's *outer* extent from `centre`, so passing `centre` on
    the host's surface buries about a third of the ring in the host and leaves
    the rest standing proud, the way a real sling loop is welded on.
    """
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    points = [vadd(centre, vadd(vmul(u, radius * math.cos(TAU * i / 12.0)),
                                vmul(v, radius * math.sin(TAU * i / 12.0))))
              for i in range(12)]
    points.append(points[0])
    swept_tube(builder, points, 0.0016, 6, cap_start=False, cap_end=False)


def _latch(builder, centre, axis, length=0.024, width=0.011, height=0.007):
    """Spring latch: a bar with a pivot boss and a proud catch nib."""
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    rounded_box(builder, centre, (width, height, length), 0.0018, 2)
    for sign in (-1.0, 1.0):
        _pin(builder, vadd(centre, vmul(w, sign * length * 0.36)),
             vadd(vadd(centre, vmul(w, sign * length * 0.36)), vmul(u, width * 0.72)),
             0.0016, 0.0010)
    extrude(builder, profile_rounded_rect(height * 0.5, width * 0.42, 0.0008, 1), -0.0010,
            0.0026, origin=vadd(centre, vmul(v, height * 0.5)), u=v, v=u, w=w)


def _panel_recess(builder, centre, u_axis, v_axis, half_u, half_v, depth=0.0016, lip=0.0012):
    """Raised panel frame: the outline that separates two volumes of a shell.

    The two profile axes are supplied explicitly. Deriving them from
    `basis_from_w(surface_normal)` silently picks an arbitrary reference, so a
    caller that meant "25 mm along the receiver" could get 25 mm across it
    instead, which pushes the frame out through the flank it was meant to sit on.
    """
    u = vnorm(u_axis)
    v = vnorm(v_axis)
    w = vnorm(vcross(u, v))
    extrude(builder, profile_rounded_rect(half_u, half_v, min(half_u, half_v) * 0.35, 2),
            0.0, -depth, origin=centre, u=u, v=v, w=w)
    ring = profile_rounded_rect(half_u + lip, half_v + lip, min(half_u, half_v) * 0.32, 2)
    extrude(builder, ring, 0.0002, 0.0020, origin=centre, u=u, v=v, w=w)


def _edge_chamfer(builder, centre, u_axis, v_axis, half_u, half_v, radius, start, end):
    """Rounded chamfer band around a shell edge, so the silhouette breaks.

    Axes are explicit for the same reason as `_panel_recess`: the band's outline
    must run along the edge it is chamfering, and `basis_from_w` does not know
    which of the two edge directions the caller meant.
    """
    u = vnorm(u_axis)
    v = vnorm(v_axis)
    w = vnorm(vcross(u, v))
    extrude(builder, profile_rounded_rect(half_u, half_v, radius, 3), start, end,
            origin=centre, u=u, v=v, w=w)


def _stipple_panel(builder, centre, u_axis, v_axis, half_u, half_v, pitch=0.0032, bump=0.0009):
    """Field of small raised moulded pips across a panel, i.e. a stippled grip.

    Polymer furniture on a real weapon is stippled at a pitch of roughly three
    millimetres, which puts several hundred pips on a pistol grip alone. The
    grid is derived from the panel's real size and the pip pitch rather than a
    row/column count, so the density is a physical property of the part.
    """
    w = vnorm(vcross(u_axis, v_axis))
    u = vnorm(u_axis)
    v = vnorm(v_axis)
    columns = max(1, int((half_u * 2.0) / pitch))
    rows = max(1, int((half_v * 2.0) / pitch))
    pitch_u = (half_u * 2.0) / columns
    pitch_v = (half_v * 2.0) / rows
    profile = profile_rounded_rect(pitch_u * 0.32, pitch_v * 0.32, min(pitch_u, pitch_v) * 0.12, 1)
    for row in range(rows):
        offset_v = (row + 0.5) * pitch_v - half_v
        for column in range(columns):
            offset_u = (column + 0.5) * pitch_u - half_u
            point = vadd(centre, vadd(vmul(u, offset_u), vmul(v, offset_v)))
            extrude(builder, profile, 0.0, bump, origin=point, u=u, v=v, w=w)


def _end_plate(builder, z, y, half_w, sling_loop=True):
    """Receiver end plate and castle nut: the collar the buffer tube screws into.

    A real carbine has a stamped end plate with a QD sling loop, locked by a
    castle nut whose staking notches are visible from behind the receiver.
    """
    half_h = 0.020
    rounded_box(builder, (0.0, y, z), (half_w * 2.02, half_h * 2.0, 0.0075), 0.0030, 3)
    tube(builder, (0.0, y, z + 0.004), (0.0, y, z + 0.014), half_w * 0.94, 18, steps=2)
    for index in range(8):
        angle = TAU * index / 8.0
        box(builder, (half_w * 0.92 * math.cos(angle), y + half_w * 0.92 * math.sin(angle),
                      z + 0.009), (0.0060, 0.0060, 0.0090))
    for side in (-1.0, 1.0):
        _screw_head(builder, (side * half_w * 0.62, y - half_h * 0.55, z - 0.002), (0.0, 0.0, -1.0),
                    0.0028, 0.0024, True)
    # Staking notch punched into the nut and the plate's own index mark.
    box(builder, (0.0, y + half_w * 0.94, z + 0.010), (0.0050, 0.0050, 0.0060))
    if sling_loop:
        _sling_loop(builder, (0.0, y - half_h - 0.006, z - 0.004), (1.0, 0.0, 0.0), 0.0060)


def _rail_clamp(builder, z_centre, y_rail, half_len=0.030, throw_lever=True, lugs=2):
    """Rail interface clamp: every attachment bolts to the host rail with one.

    A real clamp is a machined body with a recoil lug engaging a rail slot, two
    cross bolts, a spring-loaded throw lever and a witness mark showing whether
    it is locked. Modelling it once and reusing it gives every accessory the
    same believable interface the host receiver already has.
    """
    rounded_box(builder, (0.0, y_rail + 0.0140, z_centre), (0.0300, 0.0250, half_len * 2.0), 0.0042, 3)
    rounded_box(builder, (0.0, y_rail + 0.0010, z_centre), (0.0250, 0.0075, half_len * 1.8), 0.0024, 2)
    # Recoil lugs dropping into the rail slots, plus the witness marks.
    for index in range(lugs):
        z = z_centre + (index - (lugs - 1) * 0.5) * half_len * 0.72
        box(builder, (0.0, y_rail - 0.0040, z), (0.0210, 0.0090, 0.0085))
        for side in (-1.0, 1.0):
            box(builder, (side * 0.0106, y_rail - 0.0080, z), (0.0020, 0.0030, 0.0060))
    # Cross bolts with their hex recesses, fore and aft.
    for sign in (-1.0, 1.0):
        _hex_bolt(builder, (0.0, y_rail + 0.0192, z_centre + sign * half_len * 0.62),
                  (0.0, 1.0, 0.0), 0.0032, 0.0046)
    if throw_lever:
        # Throw lever on the left with its pivot pin and its spring plunger.
        rounded_box(builder, (-0.0210, y_rail + 0.0120, z_centre + half_len * 0.50),
                    (0.0105, 0.0135, 0.0300), 0.0028, 3)
        for index in range(3):
            box(builder, (-0.0260, y_rail + 0.0120, z_centre + half_len * 0.50 - 0.008 + index * 0.008),
                (0.0022, 0.0110, 0.0040))
        _pin(builder, (-0.0262, y_rail + 0.0120, z_centre + half_len * 0.50 - 0.013),
             (-0.0170, y_rail + 0.0120, z_centre + half_len * 0.50 - 0.013), 0.0022, 0.0015)
        _screw_head(builder, (-0.0210, y_rail + 0.0188, z_centre + half_len * 0.50), (0.0, 1.0, 0.0),
                    0.0026, 0.0022, True)
    # Clamp screws either side of the body and the locked/unlocked witness dots.
    for sign in (-1.0, 1.0):
        for side in (-1.0, 1.0):
            _screw_head(builder, (side * 0.0148, y_rail + 0.0140, z_centre + sign * half_len * 0.34),
                        (side, 0.0, 0.0), 0.0026, 0.0022, True)
    for index in range(2):
        box(builder, (0.0, y_rail + 0.0270, z_centre + (index - 0.5) * 0.0060),
            (0.0060, 0.0016, 0.0030))


def _port_row(builder, z, bore_y, radius, angles, width=0.0030, height=0.0070, sub=3, screws=True):
    """One circumferential row of machined gas ports through a device's wall.

    A port is an aperture cut all the way through, so the bore shows through it,
    and its mouth is bevelled in two steps with sub-slots dividing it into
    discrete openings, exactly as a machined compensator is cut.
    """
    for angle in angles:
        radial = (math.cos(angle), math.sin(angle), 0.0)
        extrude(builder, profile_rounded_rect(width, height, width * 0.5, 3), radius * 0.84,
                radius * 1.20, origin=(0.0, bore_y, z), u=(0.0, 1.0, 0.0),
                v=(0.0, 0.0, 1.0), w=radial)
        # Beveled mouth, stepped in two rings on the outside of the wall.
        for scale in (1.02, 1.10):
            extrude(builder, profile_rounded_rect(width * 1.26 * scale, height * 1.10 * scale,
                                                  width * 0.66, 3),
                    radius * (scale - 0.02), radius * scale, origin=(0.0, bore_y, z),
                    u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=radial)
        # Sub-slots dividing the port into discrete apertures.
        for index in range(sub):
            offset = (index - (sub - 1) * 0.5) * (height * 1.8 / max(1, sub))
            box(builder, (0.0, bore_y + offset, z), (width * 2.0, height * 0.30, radius * 0.62))
    # Index marks and a witness notch either side of every row, plus the clamp
    # screws that time the device to the barrel.
    for sign in (-1.0, 1.0):
        box(builder, (sign * radius * 1.02, bore_y + radius * 0.86, z), (0.0030, 0.0040, height * 1.15))
        if screws:
            _screw_head(builder, (sign * (radius + 0.0016), bore_y - radius * 0.72, z),
                        (sign, 0.0, 0.0), 0.0026, 0.0022, True)


def _baffle_stack(builder, z_start, bore_y, span, baffles, outer, segments=16):
    """Conical baffle stack visible down the bore of a suppressor or brake.

    `z_start` is the muzzle-most baffle face and the stack runs back down `span`.
    Each baffle is a cone stepping down to a throat, with the spacer ring that
    stands the next baffle off it, which is what a suppressor's internals are.
    """
    for index in range(baffles):
        t0 = index / baffles
        t1 = (index + 1) / baffles
        z0 = z_start - span * t0
        z1 = z_start - span * t1
        throat = 0.0086 * (1.0 - 0.09 * index)
        throat_end = 0.0086 * (1.0 - 0.09 * (index + 1))
        # The cone face stepping down toward the bore. It is capped: a baffle is
        # a solid with a hole through it, and a tapered sweep left open does not
        # close, so its winding has no consistent inside.
        tube(builder, (0.0, bore_y, z0), (0.0, bore_y, z1), outer, segments,
             radius_end=throat, cap_start=True, cap_end=True)
        # Its throat, and the spacer ring standing it off the next baffle.
        tube(builder, (0.0, bore_y, z1), (0.0, bore_y, z1 + span * 0.14), throat, 12,
             radius_end=throat_end, cap_start=True, cap_end=True)
        tube(builder, (0.0, bore_y, z1 + span * 0.14), (0.0, bore_y, z1 + span * 0.22),
             outer * 0.94, segments, cap_start=True, cap_end=True)


def _ported_brake(builder, z_front, z_back, bore_y, radius, rows=3, per_row=4):
    """Ported brake/compensator: a machined body with real rows of gas ports.

    Each port is a machined aperture with a beveled mouth, and the body carries
    the ring grooves, index marks and thread relief a real device has. The ports
    are what a compensator is for, so they are the bulk of the geometry.
    """
    tube(builder, (0.0, bore_y, z_back), (0.0, bore_y, z_front), radius, 20, steps=4)
    span = z_front - z_back
    # Machined ring grooves around the body, plus its blast-chamber flange.
    for index in range(5):
        z = z_back + span * (index + 0.5) / 5.0
        tube(builder, (0.0, bore_y, z - 0.0018), (0.0, bore_y, z + 0.0018), radius * 0.94, 20)
    tube(builder, (0.0, bore_y, z_back), (0.0, bore_y, z_back + span * 0.10), radius * 1.06, 20)
    # Rows of ports: the top row expels muzzle rise, the side rows the lateral
    # gas. Each row is three machine-cut apertures with sub-slots and lips.
    angles = [0.0, math.pi * 0.5, -math.pi * 0.5]
    for row in range(rows):
        z = z_back + span * (row + 1) / (rows + 1)
        _port_row(builder, z, bore_y, radius, angles, 0.0030, 0.0070, per_row)
    # Crowned bore, baffle stack and the thread relief at the rear shoulder.
    _baffle_stack(builder, z_front - 0.004, bore_y, span * 0.48, max(3, rows), 0.0126, 16)
    tube(builder, (0.0, bore_y, z_front), (0.0, bore_y, z_front - 0.004), 0.0086, 16)
    tube(builder, (0.0, bore_y, z_back - 0.005), (0.0, bore_y, z_back), radius * 0.76, 16)
    tube(builder, (0.0, bore_y, z_back - 0.005), (0.0, bore_y, z_back + 0.001), radius * 0.90, 16)
    # Index marks around the rear shoulder so it can be timed to the barrel.
    _graduations(builder, (0.0, bore_y, z_back + 0.0022), (0.0, 0.0, 1.0), radius * 1.04, 9, 3.2)
    for index in range(6):
        angle = TAU * index / 6.0
        box(builder, (radius * 0.80 * math.cos(angle), bore_y + radius * 0.80 * math.sin(angle),
                      z_back - 0.0075), (0.0030, 0.0030, 0.0060))


def _picatinny(builder, z_front, z_back, y, half_width=0.0105, teeth=14):
    rail(builder, (0.0, y, z_front), (0.0, y, z_back), half_width * 2.0, 0.0068, teeth, 0.0055)
    span = z_back - z_front
    # Clamp screws down both flanks, at the pitch of the teeth. A real rail is
    # bolted to its host, and the heads are the brightest thing on a black
    # receiver under a directional light.
    if teeth >= 5:
        pitch = span / teeth
        for index in range(2, teeth - 1, 3):
            z = z_front + (index + 0.5) * pitch
            for side in (-1.0, 1.0):
                _screw_head(builder, (side * (half_width + 0.0016), y - 0.0010, z),
                            (side, 0.0, 0.0), 0.0028, 0.0024, True)
    # Proud lip where the rail base meets its host, so the two volumes read apart.
    box(builder, (0.0, y - 0.0039, (z_front + z_back) * 0.5),
        (half_width * 2.0 + 0.0022, 0.0018, abs(span) * 0.98))


def _iron_sights(builder, z_front, z_rear, y):
    """Folding front and rear sights: base, upright and aperture/ring."""
    # Front sight: base block plus a protected post.
    rounded_box(builder, (0.0, y + 0.006, z_front), (0.020, 0.012, 0.030), 0.002)
    box(builder, (0.0, y + 0.021, z_front), (0.0016, 0.020, 0.0040))
    for side in (-1.0, 1.0):
        box(builder, (side * 0.0088, y + 0.019, z_front), (0.0016, 0.022, 0.0070))
    # Base screws and the hinge the tower folds on.
    for side in (-1.0, 1.0):
        _screw_head(builder, (side * 0.0072, y + 0.0118, z_front), (0.0, 1.0, 0.0),
                    0.0030, 0.0024, True)
    _pin(builder, (-0.0105, y + 0.008, z_front - 0.012), (0.0105, y + 0.008, z_front - 0.012),
         0.0018, 0.0012)
    # Protected post: a detent ball at the top of the bayonet-style front post.
    tube(builder, (0.0, y + 0.031, z_front), (0.0, y + 0.0335, z_front), 0.0016, 10)
    # Rear sight: base plus the aperture ring.
    rounded_box(builder, (0.0, y + 0.006, z_rear), (0.024, 0.012, 0.036), 0.002)
    box(builder, (0.0, y + 0.020, z_rear), (0.024, 0.020, 0.007))
    tube(builder, (0.0, y + 0.024, z_rear - 0.003), (0.0, y + 0.024, z_rear + 0.003), 0.0055, 12)
    tube(builder, (0.0, y + 0.024, z_rear - 0.004), (0.0, y + 0.024, z_rear + 0.004), 0.0022, 10)
    # Windage adjustment knob with knurling and graduation ticks.
    tube(builder, (0.0128, y + 0.017, z_rear), (0.0195, y + 0.017, z_rear), 0.0052, 12)
    _knurl(builder, (0.0192, y + 0.017, z_rear), (1.0, 0.0, 0.0), 0.0052, 0.0050, 12)
    _graduations(builder, (0.0166, y + 0.017, z_rear), (1.0, 0.0, 0.0), 0.0050, 7, 2.6)
    # Elevation drum under the aperture plus its detent.
    tube(builder, (0.0, y + 0.004, z_rear + 0.006), (0.0, y + 0.012, z_rear + 0.006), 0.0048, 12)
    _knurl(builder, (0.0, y + 0.010, z_rear + 0.006), (0.0, 1.0, 0.0), 0.0048, 0.0044, 10)
    _screw_head(builder, (0.0, y + 0.0125, z_rear + 0.014), (0.0, 1.0, 0.0), 0.0026, 0.0022)
    # Fold-down spring and hinge pin at the rear of the base.
    _pin(builder, (-0.0118, y + 0.008, z_rear + 0.012), (0.0118, y + 0.008, z_rear + 0.012),
         0.0018, 0.0012)
    for side in (-1.0, 1.0):
        _screw_head(builder, (side * 0.0088, y + 0.0118, z_rear - 0.008), (0.0, 1.0, 0.0),
                    0.0030, 0.0024, True)


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
    # Trigger blade raked back, with a serrated face and a shoe. The blade hangs
    # from the guard's top rail, so it is rooted where that rail runs rather
    # than floating in the middle of the guard's opening.
    extrude(builder, profile_rounded_rect(0.0034, 0.013, 0.0012, 2), 0.0, 0.007,
            origin=(0.0, y_top - 0.0035, z_centre + 0.002), u=(0.0, 1.0, 0.0),
            v=(0.0, 0.0, 1.0), w=(1.0, 0.0, 0.0), cap_start=True, cap_end=True)
    for index in range(5):
        box(builder, (0.0, y_top - 0.0068 + index * 0.0016, z_centre + 0.0042),
            (0.0076, 0.0011, 0.0013))
    rounded_box(builder, (0.0, y_top - 0.0100, z_centre - 0.0028), (0.0072, 0.0090, 0.0060), 0.0014, 2)
    # Trigger pin through the blade housing, proud on both sides.
    _pin(builder, (-0.0125, y_top - 0.008, z_centre), (0.0125, y_top - 0.008, z_centre),
         0.0024, 0.0016)
    # Disconnect/anti-walk pins behind it.
    for offset, radius in ((0.012, 0.0018), (0.024, 0.0016)):
        _pin(builder, (-0.0125, y_top - 0.004, z_centre - offset),
             (0.0125, y_top - 0.004, z_centre - offset), radius, 0.0013)
    # Magazine release button and safety selector on the left face.
    tube(builder, (-0.019, y_top - 0.006, z_centre + 0.030), (-0.025, y_top - 0.006, z_centre + 0.030), 0.005, 12)
    _knurl(builder, (-0.0246, y_top - 0.006, z_centre + 0.030), (-1.0, 0.0, 0.0), 0.0050, 0.0034, 12)
    tube(builder, (0.019, y_top + 0.004, z_centre - 0.020), (0.026, y_top + 0.004, z_centre - 0.020), 0.0045, 12)
    tube(builder, (0.021, y_top + 0.004, z_centre - 0.032), (-0.021, y_top + 0.004, z_centre - 0.032), 0.0018, 8)
    # Safety lever with its detent boss and a selector throw.
    rounded_box(builder, (0.0, y_top + 0.004, z_centre - 0.0265), (0.008, 0.006, 0.013), 0.0016, 2)
    tube(builder, (0.0248, y_top + 0.010, z_centre - 0.020), (0.0248, y_top - 0.002, z_centre - 0.020),
         0.0034, 12)
    _knurl(builder, (0.0248, y_top + 0.009, z_centre - 0.020), (0.0, 1.0, 0.0), 0.0034, 0.0030, 8)
    _pin(builder, (-0.0235, y_top + 0.0125, z_centre - 0.0245), (0.0235, y_top + 0.0125, z_centre - 0.0245),
         0.0020, 0.0014)
    # Magazine well funnel: the bevelled throat the magazine slides into. The
    # guard loop's upper rail runs fore-aft at about y_top-0.002, so each side
    # wall is centred on that rail (containing it inside the wall's section) and
    # extruded from the receiver's centreline outward; the front wall closes the
    # throat across both walls' lower ends.
    for sign in (-1.0, 1.0):
        extrude(builder, profile_rounded_rect(0.0060, 0.0090, 0.0014, 2), 0.0, 0.0160,
                origin=(0.0, y_top - 0.0050, z_centre + 0.030), u=(0.0, 0.0, 1.0),
                v=(0.0, 1.0, 0.0), w=(sign, 0.0, 0.0))
    extrude(builder, profile_rounded_rect(0.0136, 0.0030, 0.0014, 2), 0.0, 0.0064,
            origin=(0.0, y_top - 0.0110, z_centre + 0.030), u=(1.0, 0.0, 0.0),
            v=(0.0, 0.0, 1.0), w=(0.0, -1.0, 0.0))
    # Guard retaining screws at the front and rear of the loop.
    for sign in (-1.0, 1.0):
        _screw_head(builder, (0.0, y_top - 0.026, z_centre + sign * (depth + 0.006)),
                    (0.0, -1.0, 0.0), 0.0026, 0.0022, True)


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
    # Finger swells on the front strap: three proud lobes a hand actually wraps.
    for index in range(3):
        t = 0.24 + index * 0.20
        centre = (0.0, y_top - length * t, z_top + rake * length * t + half_width * 0.62)
        tube(builder, centre, vadd(centre, (half_width * 2.05, 0.0, 0.0)), 0.0042, 10)
    # Grip texture: shallow horizontal ribs.
    for index in range(5):
        t = 0.2 + index * 0.16
        centre = (0.0, y_top - length * t, z_top + rake * length * t)
        box(builder, centre, (half_width * 2.1, 0.0022, 0.0040))
    # Stippled texture panels: rows of small raised bumps on both flats, which
    # is what reads as a polymer grip under a moving highlight.
    for side in (-1.0, 1.0):
        _stipple_panel(builder, (side * (half_width * 1.05 + 0.0007),
                                 y_top - length * 0.50, z_top + rake * length * 0.50),
                       (0.0, -1.0, rake), (0.0, 0.0, 1.0), length * 0.36, 0.0105)
    # Front-strap stippling between the finger swells.
    _stipple_panel(builder, (0.0, y_top - length * 0.52, z_top + rake * length * 0.52 + half_width * 1.02),
                   (0.0, -1.0, rake), (1.0, 0.0, 0.0), length * 0.32, 0.0105)
    # Backstrap tang and base plug: the butt of the grip is a separate part.
    base_y = y_top - length
    base_z = z_top + rake * length
    rounded_box(builder, (0.0, base_y - 0.0035, base_z), (half_width * 2.18, 0.0075, 0.0225), 0.0022, 2)
    rounded_box(builder, (0.0, base_y - 0.0105, base_z), (half_width * 1.30, 0.0075, 0.0140), 0.0020, 2)
    for sign in (-1.0, 1.0):
        _screw_head(builder, (sign * half_width * 0.70, base_y - 0.0140, base_z), (0.0, -1.0, 0.0),
                    0.0024, 0.0020, True)
    # Grip screw through the flat holding the panel on.
    _pin(builder, (-half_width * 1.06, y_top - length * 0.52, z_top + rake * length * 0.52),
         (half_width * 1.06, y_top - length * 0.52, z_top + rake * length * 0.52), 0.0022, 0.0015)


def _buffer_tube_and_stock(builder, z_front, y_centre, length, style="collapsible"):
    """Buffer tube plus a stock. `collapsible` adds the adjustment notches."""
    tube(builder, (0.0, y_centre, z_front), (0.0, y_centre, z_front + length), 0.0155, 16, steps=3)
    if style == "collapsible":
        for index in range(5):
            offset = z_front + 0.052 + index * 0.016
            tube(builder, (0.0, y_centre - 0.015, offset), (0.0, y_centre - 0.024, offset), 0.0048, 8)
        # Adjustment lever under the tube, with a spring and a pivot pin.
        rounded_box(builder, (0.0, y_centre - 0.029, z_front + length * 0.34),
                    (0.019, 0.011, 0.038), 0.0022, 2)
        _pin(builder, (-0.0098, y_centre - 0.029, z_front + length * 0.34 - 0.012),
             (0.0098, y_centre - 0.029, z_front + length * 0.34 - 0.012), 0.0018, 0.0012)
        _screw_head(builder, (0.0, y_centre - 0.0355, z_front + length * 0.34 + 0.010),
                    (0.0, -1.0, 0.0), 0.0026, 0.0022)
    else:
        # Fixed stock: a through-bolt at the receiver join.
        _hex_bolt(builder, (0.0, y_centre - 0.024, z_front + length * 0.08), (0.0, -1.0, 0.0),
                  0.0040, 0.0056)
    # Stock body: cheek piece, butt plate and a hollow interior at the rear.
    body_z = z_front + length * 0.52
    rounded_box(builder, (0.0, y_centre - 0.004, body_z), (0.042, 0.062, length * 0.86), 0.010,
                corner_segments=3)
    box(builder, (0.0, y_centre + 0.030, body_z), (0.038, 0.012, length * 0.70))
    # Cheek riser: a separate padded volume with a moulded seam and two screws.
    rounded_box(builder, (0.0, y_centre + 0.0355, body_z - 0.012), (0.036, 0.016, length * 0.46),
                0.0045, 3)
    for sign in (-1.0, 1.0):
        _screw_head(builder, (0.0, y_centre + 0.0415, body_z + sign * length * 0.19),
                    (0.0, 1.0, 0.0), 0.0026, 0.0022, True)
    # Panel lines separating the body from the comb and the butt. These are
    # sized from the body's own cross-section so they register on its surface
    # instead of hovering off it.
    for z in (body_z + length * 0.34, body_z - length * 0.36):
        box(builder, (0.0, y_centre - 0.004, z), (0.0434, 0.0634, 0.0022))
    butt_z = z_front + length * 0.97
    rounded_box(builder, (0.0, y_centre - 0.012, butt_z), (0.046, 0.082, 0.016), 0.006)
    tube(builder, (0.0, y_centre - 0.012, butt_z + 0.008), (0.0, y_centre - 0.012, butt_z - 0.030), 0.017, 12)
    # Adjustable buttplate: a padded plate on a slide with a latch and rails.
    pad_z = butt_z + 0.014
    rounded_box(builder, (0.0, y_centre - 0.016, pad_z), (0.044, 0.090, 0.012), 0.005, 3)
    for sign in (-1.0, 1.0):
        box(builder, (0.0, y_centre - 0.016 + sign * 0.030, pad_z - 0.012),
            (0.030, 0.004, 0.010))
        _screw_head(builder, (sign * 0.0170, y_centre - 0.016 + sign * 0.030, pad_z + 0.0065),
                    (0.0, 0.0, 1.0), 0.0026, 0.0022)
    _latch(builder, (0.0, y_centre - 0.052, butt_z - 0.006), (0.0, 0.0, -1.0), 0.028, 0.012, 0.007)
    # Sling loop plus a moulded QD socket on the other flank. The loop's legs
    # are rooted on the stock body's underside rather than hanging 8.7 mm below
    # it: the body's bottom face is at body_z-0.010, and the loop used to start
    # from a fixed offset that ignored the body's actual section.
    body_bottom = y_centre - 0.004 - 0.031
    swept_tube(builder, [(0.0, body_bottom + 0.002, body_z + 0.03),
                         (0.0, body_bottom - 0.012, body_z + 0.03),
                         (0.0, body_bottom - 0.012, body_z - 0.01),
                         (0.0, body_bottom + 0.002, body_z - 0.01)], 0.0030, 6)
    for sign in (-1.0, 1.0):
        socket_x = sign * 0.0215
        tube(builder, (socket_x, y_centre - 0.010, body_z), (socket_x + sign * 0.0035, y_centre - 0.010, body_z),
             0.0052, 12)
        tube(builder, (socket_x + sign * 0.0030, y_centre - 0.010, body_z),
             (socket_x + sign * 0.0010, y_centre - 0.010, body_z), 0.0028, 10)
        for index in range(4):
            angle = TAU * (index + 0.5) / 4.0
            box(builder, (socket_x + sign * 0.0036, y_centre - 0.010 + 0.0068 * math.sin(angle),
                          body_z + 0.0068 * math.cos(angle)), (0.0016, 0.0022, 0.0022))
    # Buffer tube detent pin and a witness strip on the comb.
    _pin(builder, (-0.0160, y_centre - 0.014, body_z + length * 0.30),
         (0.0160, y_centre - 0.014, body_z + length * 0.30), 0.0022, 0.0015)
    box(builder, (0.0, y_centre - 0.0355, body_z + length * 0.10), (0.030, 0.0016, 0.048))


def _handguard(builder, z_front, z_back, y_centre, half_width, half_height, slots=4, vent_rows=2):
    """Octagonal M-LOK handguard: shell, side slots and vent holes."""
    shell = profile_rounded_rect(half_width, half_height, 0.008, 2)
    sweep(builder, shell,
          [((0.0, y_centre, z_back), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
           ((0.0, y_centre, (z_front + z_back) * 0.5), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
           ((0.0, y_centre, z_front), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))],
          True, True)
    span = abs(z_front - z_back)
    direction = 1.0 if z_front < z_back else -1.0
    # Vent ribs on both flats, seated on the shell's cross-section. The row
    # offset is a fraction of the shell's *half height*, not of the guard's
    # length: deriving it from `span` threw the blocks 33 mm clear of the shell
    # (a long handguard has a large span and a small section), leaving them
    # floating in mid-air rather than proud of the flank.
    for row in range(vent_rows):
        offset = 0.0 if vent_rows == 1 else (row - (vent_rows - 1) * 0.5) * half_height * 0.72
        for side in (-1.0, 1.0):
            for index in range(slots):
                along = z_back - (span * (index + 0.5) / slots) * direction
                centre = (side * half_width, y_centre + offset, along)
                rounded_box(builder, centre, (0.008, 0.014, 0.026), 0.003)
    # Real M-LOK slot rows: recessed rounded slots between the vent blocks on
    # both flats and along the underside, each with the lip it clamps against.
    for side in (-1.0, 1.0):
        for index in range(slots + 1):
            along = z_back - (span * (index + 0.5) / (slots + 1)) * direction
            _mlok_slot(builder, (side * half_width, y_centre, along), (side, 0.0, 0.0))
    # Second and third rows fore and aft of the first, so a handguard carries
    # the grid of slots a real one does rather than a single line of them.
    for side in (-1.0, 1.0):
        for row, offset in ((0, half_height * 0.46), (1, -half_height * 0.46)):
            for index in range(slots):
                along = z_back - (span * (index + 0.62) / (slots + 0.4)) * direction
                _mlok_slot(builder, (side * half_width, y_centre + offset, along), (side, 0.0, 0.0))
    for index in range(slots):
        along = z_back - (span * (index + 0.5) / slots) * direction
        _mlok_slot(builder, (0.0, y_centre - half_height, along), (0.0, -1.0, 0.0))
    for index in range(slots + 1):
        along = z_back - (span * (index + 0.5) / (slots + 1)) * direction
        _mlok_slot(builder, (0.0, y_centre + half_height, along), (0.0, 1.0, 0.0))
    # Panel lines splitting the shell into upper and lower flanks.
    for y in (y_centre + half_height * 0.52, y_centre - half_height * 0.52):
        box(builder, (0.0, y, (z_front + z_back) * 0.5),
            (half_width * 2.06, 0.0018, span * 0.96))
    # Heat-shield lip where the guard meets the barrel nut, plus the nut flange.
    for sign in (-1.0, 1.0):
        rounded_box(builder, (0.0, y_centre + sign * (half_height - 0.0016), z_back + 0.004),
                    (half_width * 2.02, 0.0048, 0.012), 0.0018, 2)
    # QD sling socket on the left flank, with its anti-rotation boss.
    socket_x = -half_width
    tube(builder, (socket_x, y_centre - half_height * 0.55, z_back - span * 0.20),
         (socket_x - 0.0042, y_centre - half_height * 0.55, z_back - span * 0.20), 0.0056, 12)
    tube(builder, (socket_x - 0.0038, y_centre - half_height * 0.55, z_back - span * 0.20),
         (socket_x - 0.0012, y_centre - half_height * 0.55, z_back - span * 0.20), 0.0030, 10)
    for index in range(4):
        angle = TAU * (index + 0.5) / 4.0
        box(builder, (socket_x - 0.0044, y_centre - half_height * 0.55 + 0.0072 * math.sin(angle),
                      z_back - span * 0.20 + 0.0072 * math.cos(angle)),
            (0.0016, 0.0022, 0.0022))
    # Anti-rotation screws above and below the socket.
    for sign in (-1.0, 1.0):
        _screw_head(builder, (socket_x, y_centre - half_height * 0.55 + sign * 0.0105,
                              z_back - span * 0.20), (-1.0, 0.0, 0.0), 0.0026, 0.0022, True)
    # Cross-bolts through the shell at the barrel-nut join. They span the shell's
    # full section so each bolt is a through-bolt that bites the far wall,
    # rather than a stub hovering below the shell's underside.
    for sign in (-1.0, 1.0):
        _hex_bolt(builder, (0.0, y_centre - half_height * 0.5, z_back + sign * 0.008),
                  (0.0, -1.0, 0.0), 0.0036, half_height * 1.05)


def _front_sight_tower(builder, z, y_centre, half_height, half_width, bayonet_lug=False):
    """Front sight tower: a protected post on a gas-block base, plus a bayonet lug.

    Two vertical protective wings rise from the base and are capped by a cross
    bar; the post sits between them. Every part is rooted on the base block's top
    face, so the tower is one connected sub-assembly rather than a cluster of
    plates near each other.
    """
    base_y = y_centre + half_height - 0.004
    top_y = base_y + 0.032
    rounded_box(builder, (0.0, base_y + 0.008, z), (0.026, 0.016, 0.032), 0.0034, 3)
    # Protective wings: vertical plates standing on the base, capped by the bar.
    for side in (-1.0, 1.0):
        extrude(builder, profile_rounded_rect(0.0080, 0.0150, 0.0026, 2), 0.0, 0.0032,
                origin=(side * 0.0115, base_y + 0.0230, z), u=(0.0, 0.0, 1.0),
                v=(0.0, 1.0, 0.0), w=(side, 0.0, 0.0))
    # Cross bar joining the two wings' crowns.
    box(builder, (0.0, base_y + 0.0350, z), (0.0264, 0.0030, 0.0060))
    # The post itself, between the wings, with its detent ball on top.
    box(builder, (0.0, base_y + 0.0280, z), (0.0018, 0.0280, 0.0034))
    tube(builder, (0.0, base_y + 0.0380, z), (0.0, base_y + 0.0410, z), 0.0016, 10)
    # Base clamp screws and the sight-tower hinge pin.
    for side in (-1.0, 1.0):
        _screw_head(builder, (side * 0.0112, base_y + 0.008, z), (0.0, 1.0, 0.0),
                    0.0028, 0.0024, True)
    _pin(builder, (-0.0134, base_y + 0.014, z + 0.010),
         (0.0134, base_y + 0.014, z + 0.010), 0.0018, 0.0012)
    if bayonet_lug:
        rounded_box(builder, (0.0, base_y - 0.0160, z - 0.026), (0.020, 0.0240, 0.030), 0.0030, 3)
        box(builder, (0.0, base_y - 0.0220, z - 0.044), (0.014, 0.0100, 0.010))
        _pin(builder, (-0.0105, base_y - 0.0140, z - 0.020),
             (0.0105, base_y - 0.0140, z - 0.020), 0.0020, 0.0014)


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
    # Witness ribs down the flank. The body is a swept solid whose flank sits at
    # `half_depth`, so the ribs are placed on that flank rather than at x=0 in
    # the middle of the magazine, which left them buried where they could not
    # register.
    for side in (-1.0, 1.0):
        for index in range(4):
            t = 0.15 + index * 0.20
            box(builder, (side * half_depth * (1.0 - 0.05 * t),
                          y_top - length * t, z_top + curve * (t ** 2)),
                (0.0036, 0.020, 0.0060))
    # Witness holes: round round-count ports down both flanks, plus the spine
    # rib a stamped magazine carries along its back.
    for side in (-1.0, 1.0):
        for index in range(4):
            t = 0.18 + index * 0.20
            y = y_top - length * t
            z = z_top + curve * (t ** 2)
            _mlok_slot(builder, (side * (half_depth * (1.0 - 0.05 * t) + 0.0006), y, z),
                       (side, 0.0, 0.0))
    for index in range(4):
        t = 0.15 + index * 0.20
        box(builder, (0.0, y_top - length * t, z_top + curve * (t ** 2) + half_width + 0.0016),
            (half_depth * 1.5, 0.0060, 0.0022))
    # Follower, feed lips and a loaded-round witness at the top.
    extrude(builder, profile_rounded_rect(half_depth * 0.68, 0.0022, 0.0014, 2), 0.0, 0.0030,
            origin=(0.0, y_top + 0.0016, z_top), u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0),
            w=(0.0, 1.0, 0.0))
    for sign in (-1.0, 1.0):
        extrude(builder, profile_rounded_rect(0.0034, 0.0042, 0.0012, 2), 0.0, length * 0.10,
                origin=(sign * half_depth * 0.92, y_top - length * 0.05, z_top), u=(0.0, 1.0, 0.0),
                v=(0.0, 0.0, 1.0), w=(sign, 0.0, 0.0))
    # Baseplate with a pull tab and the floorplate insert.
    rounded_box(builder, (0.0, base_y - 0.010, base_z), (half_depth * 2.36, 0.0075, half_width * 2.36),
                0.0026, 2)
    tab_y = base_y - 0.016
    for sign in (-1.0, 1.0):
        rounded_box(builder, (sign * half_depth * 0.62, tab_y, base_z), (0.012, 0.008, 0.020),
                    0.0020, 2)
    extrude(builder, profile_rounded_rect(half_depth * 0.86, 0.0026, 0.0016, 2), 0.0, 0.0034,
            origin=(0.0, base_y - 0.0135, base_z), u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0),
            w=(0.0, -1.0, 0.0))
    for sign in (-1.0, 1.0):
        _screw_head(builder, (sign * half_depth * 0.54, base_y - 0.0140, base_z), (0.0, -1.0, 0.0),
                    0.0024, 0.0020)
    if style == "drum":
        # Drum body along the magazine's length, with its end hub. The hub is a
        # continuation of the drum's own spindle: it used to start 10 mm past
        # where the drum ended, leaving a detached collar floating behind it.
        drum_r = 0.072
        tube(builder, (0.0, base_y - 0.010, base_z), (0.0, base_y - 0.130, base_z), drum_r, 22, steps=3)
        tube(builder, (0.0, base_y - 0.130, base_z), (0.0, base_y - 0.152, base_z), 0.030, 14, steps=3)
        tube(builder, (0.0, base_y - 0.128, base_z), (0.0, base_y - 0.134, base_z), 0.050, 16)
        # The drum's face features sit on its curved outer surface, at the drum's
        # own radius. Placed in the (x, z) plane instead they fell along the
        # drum's *axis*, which buried them inside the drum body where they could
        # not be seen at all.
        for row in range(3):
            y = base_y - 0.030 - row * 0.036
            for index in range(8):
                angle = TAU * index / 8.0
                radial = (math.cos(angle), 0.0, math.sin(angle))
                point = (radial[0] * drum_r, y, base_z + radial[2] * drum_r)
                if (index + row) % 2 == 0:
                    _hex_bolt(builder, point, radial, 0.0030, 0.0044)
                else:
                    _screw_head(builder, point, radial, 0.0028, 0.0024, True)
            # Radial ribs stiffening the drum's shell.
            for index in range(8):
                angle = TAU * index / 8.0
                radial = (math.cos(angle), 0.0, math.sin(angle))
                extrude(builder, profile_rounded_rect(0.0028, 0.0130, 0.0013, 2), 0.0, 0.0055,
                        origin=(radial[0] * drum_r, y, base_z + radial[2] * drum_r),
                        u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=radial)
        # Wind-up key on the drum's end cap, plus its four lugs.
        tube(builder, (0.0, base_y - 0.152, base_z), (0.0, base_y - 0.166, base_z), 0.0120, 12)
        _knurl(builder, (0.0, base_y - 0.158, base_z), (0.0, -1.0, 0.0), 0.0120, 0.0060, 10)
        for index in range(3):
            angle = TAU * index / 3.0
            extrude(builder, profile_rounded_rect(0.0026, 0.0050, 0.0012, 2), 0.0, 0.0160,
                    origin=(0.0160 * math.cos(angle), base_y - 0.158, base_z + 0.0160 * math.sin(angle)),
                    u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), w=(0.0, -1.0, 0.0))


def _bolt_and_handle(builder, z_centre, y_centre, travel=0.045):
    """Bolt carrier visible through the ejection port, plus the charging handle."""
    tube(builder, (0.0, y_centre, z_centre + travel), (0.0, y_centre, z_centre - 0.062), 0.0118, 16, steps=3)
    box(builder, (0.008, y_centre + 0.004, z_centre), (0.014, 0.018, 0.030))
    # Bolt lugs, extractor and the cam pin: the carrier's face is not plain.
    for index in range(7):
        angle = TAU * index / 7.0
        box(builder, (0.0104 * math.cos(angle), y_centre + 0.0104 * math.sin(angle),
                      z_centre - 0.056), (0.0050, 0.0050, 0.0080))
    rounded_box(builder, (0.0120, y_centre, z_centre - 0.048), (0.0070, 0.0110, 0.0160), 0.0018, 2)
    _pin(builder, (-0.0118, y_centre, z_centre - 0.038), (0.0118, y_centre, z_centre - 0.038),
         0.0020, 0.0014)
    # Gas rings machined into the carrier.
    for index in range(4):
        tube(builder, (0.0, y_centre, z_centre + travel - 0.006 - index * 0.008),
             (0.0, y_centre, z_centre + travel - 0.009 - index * 0.008), 0.0126, 16)
    # Charging handle at the rear of the receiver, with a latch and its pivot pin.
    box(builder, (0.0, y_centre + 0.012, z_centre + 0.070), (0.030, 0.010, 0.036))
    rounded_box(builder, (0.0, y_centre + 0.012, z_centre + 0.092), (0.056, 0.008, 0.016), 0.003)
    rounded_box(builder, (0.0, y_centre + 0.019, z_centre + 0.086), (0.052, 0.005, 0.011), 0.0020, 2)
    for side in (-1.0, 1.0):
        box(builder, (side * 0.0230, y_centre + 0.017, z_centre + 0.086), (0.0070, 0.0080, 0.0140))
    _pin(builder, (-0.0250, y_centre + 0.012, z_centre + 0.082), (0.0250, y_centre + 0.012, z_centre + 0.082),
         0.0022, 0.0015)


def _ejection_port(builder, z_centre, y_centre):
    """Raised port frame plus the closed dust cover on its hinge pin."""
    for dz in (-0.028, 0.028):
        box(builder, (0.019, y_centre, z_centre + dz), (0.004, 0.026, 0.004))
    rounded_box(builder, (0.020, y_centre - 0.008, z_centre + 0.008), (0.007, 0.018, 0.058), 0.002)
    # Dust cover: a stamped lid with a stiffening rib, its hinge pin along the
    # top edge and a spring-loaded detent ball at the front.
    rounded_box(builder, (0.0225, y_centre - 0.0075, z_centre + 0.008), (0.0090, 0.0190, 0.0600),
                0.0028, 3)
    for sign in (-1.0, 1.0):
        box(builder, (0.0268, y_centre - 0.0075, z_centre + 0.008 + sign * 0.021),
            (0.0022, 0.0140, 0.0044))
    box(builder, (0.0252, y_centre - 0.0010, z_centre + 0.008), (0.0024, 0.0018, 0.052))
    _pin(builder, (0.0175, y_centre + 0.0015, z_centre - 0.022), (0.0175, y_centre + 0.0015, z_centre + 0.038),
         0.0022, 0.0016)
    _pin(builder, (0.0175, y_centre + 0.0015, z_centre - 0.026), (0.0262, y_centre + 0.0015, z_centre - 0.026),
         0.0014, 0.0010)
    rounded_box(builder, (0.0262, y_centre - 0.0015, z_centre + 0.034), (0.0022, 0.0052, 0.0060), 0.0014, 2)
    # Forward assist: the serrated plunger and its housing on the right rear.
    tube(builder, (0.0180, y_centre + 0.005, z_centre + 0.052), (0.0272, y_centre + 0.005, z_centre + 0.052),
         0.0068, 14)
    _knurl(builder, (0.0270, y_centre + 0.005, z_centre + 0.052), (1.0, 0.0, 0.0), 0.0068, 0.0050, 12)
    tube(builder, (0.0272, y_centre + 0.005, z_centre + 0.052), (0.0296, y_centre + 0.005, z_centre + 0.052),
         0.0040, 12)


def _gas_block(builder, z_centre, y_centre, height=0.030, gas_tube_to=None, half_w=0.0130):
    rounded_box(builder, (0.0, y_centre + height * 0.5, z_centre), (half_w * 2.0, height, 0.030), 0.004)
    tube(builder, (0.0, y_centre + height - 0.004, z_centre - 0.026), (0.0, y_centre + height - 0.004, z_centre + 0.026), 0.0075, 12)
    # Front sling swivel, looped off the block's underside. It hangs from the
    # block's own bottom face: the loop started 12 mm below the *bore* line,
    # which on a tall block is clear of the block altogether.
    bottom = y_centre
    swept_tube(builder, [(0.0, bottom - 0.002, z_centre), (0.0, bottom - 0.008, z_centre - 0.006),
                         (0.0, bottom - 0.008, z_centre + 0.006)], 0.0026, 6)
    # Clamp screws under the block and the gas-tube roll pin.
    for sign in (-1.0, 1.0):
        _screw_head(builder, (0.0, y_centre - 0.0055, z_centre + sign * 0.010), (0.0, -1.0, 0.0),
                    0.0030, 0.0024, True)
    for sign in (-1.0, 1.0):
        _pin(builder, (sign * (half_w + 0.0016), y_centre + height * 0.5, z_centre),
             (sign * (half_w + 0.0002), y_centre + height * 0.5, z_centre), 0.0022, 0.0014)
    if gas_tube_to is not None:
        # Gas tube running back from the block into the receiver's gas key.
        tube(builder, (0.0, y_centre + height - 0.004, z_centre + 0.020),
             (0.0, gas_tube_to[0], gas_tube_to[1]), 0.0044, 12, steps=3)
        tube(builder, (0.0, y_centre + height - 0.004, z_centre + 0.020),
             (0.0, y_centre + height - 0.004, z_centre + 0.034), 0.0060, 12)


def _barrel_nut(builder, z_front, z_back, y, half_width):
    """Barrel nut: the splined collar that clamps the barrel into the upper."""
    tube(builder, (0.0, y, z_back), (0.0, y, z_front), half_width * 0.96, 20, steps=3)
    for index in range(16):
        angle = TAU * index / 16.0
        tube(builder, (half_width * 0.94 * math.cos(angle), y + half_width * 0.94 * math.sin(angle), z_back),
             (half_width * 1.04 * math.cos(angle), y + half_width * 1.04 * math.sin(angle), z_back),
             0.0022, 8)
    for side in (-1.0, 1.0):
        _hex_bolt(builder, (side * half_width * 0.55, y - half_width * 0.80, z_front + 0.004),
                  (0.0, -1.0, 0.0), 0.0034, 0.0046)


def _muzzle_device(builder, z_front, z_back, bore_y, radius=0.0125, ports=4, style="flash"):
    """Ported brake, compensator or suppressor with a baffle stack in the bore."""
    if style == "brake":
        # A brake is defined by its port geometry, so it is built as one.
        _ported_brake(builder, z_front, z_back, bore_y, radius, max(3, ports - 1))
        return
    tube(builder, (0.0, bore_y, z_back), (0.0, bore_y, z_front), radius, 16, steps=3)
    span = z_front - z_back
    if style == "flash":
        # A birdcage hider is a ring of slots cut clean through the wall, each
        # with its own sub-slots and lips, and it is those slots that read.
        for index in range(ports):
            along = z_back + span * (index + 1) / (ports + 1)
            _port_row(builder, along, bore_y, radius,
                      (0.0, math.pi * 0.5, -math.pi * 0.5, math.pi, 0.25 * math.pi, -0.25 * math.pi),
                      0.0024, 0.0064, 3, screws=False)
            # The bore shows through the crown of each slot.
            extrude(builder, profile_rounded_rect(0.0026, 0.0070, 0.0014, 2), radius * 0.70,
                    radius * 1.20, origin=(0.0, bore_y, along), u=(1.0, 0.0, 0.0),
                    v=(0.0, 0.0, 1.0), w=(0.0, 1.0, 0.0))
        # Ring grooves and the front crown of a birdcage hider.
        for index in range(4):
            along = z_back + span * (index + 0.5) / 4.0
            tube(builder, (0.0, bore_y, along - 0.0016), (0.0, bore_y, along + 0.0016), radius * 0.94, 16)
    # Baffle stack visible through the bore: conical rings stepping down.
    _baffle_stack(builder, z_front - 0.004, bore_y, span * 0.54, max(3, ports), radius * 0.94, 14)
    # Crowned bore.
    tube(builder, (0.0, bore_y, z_front), (0.0, bore_y, z_front - 0.004), 0.0082, 14)
    tube(builder, (0.0, bore_y, z_front - 0.004), (0.0, bore_y, z_front - 0.060), 0.0052, 14, cap_end=False)
    # Thread relief at the rear shoulder where it screws onto the barrel.
    tube(builder, (0.0, bore_y, z_back - 0.004), (0.0, bore_y, z_back), radius * 0.78, 14)


def _optic_mount(builder, z_centre, y_base, half_len=0.032, ring_radius=0.019):
    """Throw-lever mount with two ring caps, each held by a pair of screws."""
    rounded_box(builder, (0.0, y_base + 0.012, z_centre), (0.036, 0.024, half_len * 2.0), 0.0045, 3)
    # Throw lever on the left flank with its pivot and a latch nib.
    rounded_box(builder, (-0.0225, y_base + 0.012, z_centre + half_len * 0.55),
                (0.0110, 0.0140, 0.0300), 0.0030, 2)
    _pin(builder, (-0.0275, y_base + 0.012, z_centre + half_len * 0.55 - 0.012),
         (-0.0240, y_base + 0.012, z_centre + half_len * 0.55 - 0.012), 0.0022, 0.0015)
    extrude(builder, profile_rounded_rect(0.0034, 0.0030, 0.0012, 2), 0.0, 0.0100,
            origin=(-0.0280, y_base + 0.012, z_centre + half_len * 0.55 + 0.008),
            u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(-1.0, 0.0, 0.0))
    # Ring caps: a clamp ring at each end of the body, split with cap screws.
    for sign in (-1.0, 1.0):
        z = z_centre + sign * half_len * 0.78
        tube(builder, (0.0, y_base + 0.032, z - 0.0055), (0.0, y_base + 0.032, z + 0.0055),
             ring_radius, 18)
        tube(builder, (0.0, y_base + 0.032, z - 0.0060), (0.0, y_base + 0.032, z + 0.0060),
             ring_radius + 0.0022, 18)
        for side in (-1.0, 1.0):
            _screw_head(builder, (side * ring_radius * 0.62, y_base + 0.032 + ring_radius * 0.78, z),
                        (0.0, 1.0, 0.0), 0.0026, 0.0024, True)
        for side in (-1.0, 1.0):
            _hex_bolt(builder, (side * ring_radius * 0.72, y_base + 0.022, z), (side, 0.0, 0.0),
                      0.0028, 0.0040)
    # Rail clamp screws under the mount and the recoil lug.
    for sign in (-1.0, 1.0):
        _screw_head(builder, (0.0, y_base - 0.0005, z_centre + sign * half_len * 0.62),
                    (0.0, 1.0, 0.0), 0.0030, 0.0026, True)
    box(builder, (0.0, y_base + 0.001, z_centre - half_len * 0.30), (0.030, 0.0040, 0.0090))


def _turret(builder, base_centre, axis, radius=0.0080, travel=0.0100, marks=9):
    """W&E turret: a knurled drum with graduation ticks and a slotted cap screw."""
    w = vnorm(axis)
    tube(builder, base_centre, vadd(base_centre, vmul(w, travel * 0.62)), radius, 12)
    _knurl(builder, vadd(base_centre, vmul(w, travel * 0.42)), w, radius, 0.0042, 12)
    _graduations(builder, vadd(base_centre, vmul(w, travel * 0.18)), w, radius, marks, 2.4)
    cap = vadd(base_centre, vmul(w, travel * 0.62))
    tube(builder, cap, vadd(cap, vmul(w, travel * 0.38)), radius * 0.86, 12)
    _screw_head(builder, vadd(cap, vmul(w, travel * 0.55)), w, radius * 0.54, 0.0026)
    # Detent boss and the zero-reset collar at the base.
    tube(builder, base_centre, vadd(base_centre, vmul(w, travel * 0.10)), radius * 1.22, 12)


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
        # Recessed lens bezel plus the rubber eyepiece cuff at the rear.
        tube(builder, (0.0, y_base + 0.034, z_centre - 0.031), (0.0, y_base + 0.034, z_centre - 0.0355), 0.0212, 18)
        tube(builder, (0.0, y_base + 0.034, z_centre - 0.026), (0.0, y_base + 0.034, z_centre - 0.0295), 0.0182, 18)
        tube(builder, (0.0, y_base + 0.034, z_centre + 0.031), (0.0, y_base + 0.034, z_centre + 0.0360), 0.0215, 18)
        # Battery cap on the right with a knurled rim.
        tube(builder, (0.0150, y_base + 0.030, z_centre + 0.014), (0.0215, y_base + 0.030, z_centre + 0.014), 0.0072, 12)
        _knurl(builder, (0.0212, y_base + 0.030, z_centre + 0.014), (1.0, 0.0, 0.0), 0.0072, 0.0050, 10)
        # Body hinge and the mount under the housing.
        for side in (-1.0, 1.0):
            _screw_head(builder, (side * 0.0132, y_base + 0.030, z_centre - 0.014), (side, 0.0, 0.0),
                        0.0026, 0.0024, True)
        # Adjustment turrets.
        tube(builder, (0.0, y_base + 0.054, z_centre), (0.0, y_base + 0.062, z_centre), 0.008, 12)
        tube(builder, (0.0, y_base + 0.034, z_centre + 0.0), (0.019, y_base + 0.034, z_centre), 0.0075, 12)
        _turret(builder, (0.0, y_base + 0.062, z_centre), (0.0, 1.0, 0.0), 0.0080, 0.0110, 9)
        _turret(builder, (0.019, y_base + 0.034, z_centre), (1.0, 0.0, 0.0), 0.0075, 0.0100, 9)
        _optic_mount(builder, z_centre, y_base, 0.030, 0.021)
    elif kind == "holo":
        rounded_box(builder, (0.0, y_base + 0.032, z_centre), (0.034, 0.040, 0.056), 0.006)
        box(builder, (0.0, y_base + 0.056, z_centre + 0.006), (0.036, 0.014, 0.030))
        _lens(builder, z_centre - 0.028, y_base + 0.036, 0.018, glass=True)
        _reticle(builder, z_centre - 0.022, y_base + 0.036)
        tube(builder, (0.0, y_base + 0.032, z_centre + 0.028), (0.0, y_base + 0.032, z_centre + 0.034), 0.012, 14)
        # Hood, window bezel and the laser housing under the hood.
        rounded_box(builder, (0.0, y_base + 0.056, z_centre - 0.020), (0.030, 0.012, 0.036), 0.0030, 2)
        tube(builder, (0.0, y_base + 0.036, z_centre - 0.028), (0.0, y_base + 0.036, z_centre - 0.0325), 0.0202, 18)
        tube(builder, (0.0, y_base + 0.020, z_centre + 0.010), (0.0, y_base + 0.026, z_centre + 0.010), 0.0075, 12)
        _screw_head(builder, (0.0, y_base + 0.0265, z_centre + 0.010), (0.0, 1.0, 0.0), 0.0026, 0.0022, True)
        for side in (-1.0, 1.0):
            _hex_bolt(builder, (side * 0.0175, y_base + 0.032, z_centre + 0.006), (side, 0.0, 0.0),
                      0.0028, 0.0040)
        _turret(builder, (0.0178, y_base + 0.036, z_centre + 0.014), (1.0, 0.0, 0.0), 0.0070, 0.0092, 7)
        _optic_mount(builder, z_centre, y_base, 0.028, 0.019)
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
        # Knurled magnification ring under the eyepiece, on its own collar.
        tube(builder, (0.0, y_base + 0.040, z_centre + 0.032), (0.0, y_base + 0.040, z_centre + 0.044), 0.0235, 18)
        _knurl(builder, (0.0, y_base + 0.040, z_centre + 0.038), (0.0, 0.0, 1.0), 0.0235, 0.0100, 16)
        _graduations(builder, (0.0, y_base + 0.040, z_centre + 0.030), (0.0, 0.0, 1.0), 0.0250, 11, 1.4)
        box(builder, (0.0, y_base + 0.0625, z_centre + 0.038), (0.0030, 0.0022, 0.0060))
        # Recessed objective bezel and the anti-reflective shoulder.
        tube(builder, (0.0, y_base + 0.040, z_centre - 0.049), (0.0, y_base + 0.040, z_centre - 0.0535), 0.0242, 18)
        tube(builder, (0.0, y_base + 0.040, z_centre - 0.044), (0.0, y_base + 0.040, z_centre - 0.0475), 0.0212, 18)
        # Body ribs and the mount's ring caps.
        for index in range(4):
            tube(builder, (0.0, y_base + 0.040, z_centre - 0.030 + index * 0.020),
                 (0.0, y_base + 0.040, z_centre - 0.026 + index * 0.020), 0.0212, 18)
        _turret(builder, (0.0, y_base + 0.058, z_centre), (0.0, 1.0, 0.0), 0.0082, 0.0110, 9)
        _turret(builder, (0.0205, y_base + 0.040, z_centre + 0.002), (1.0, 0.0, 0.0), 0.0078, 0.0100, 9)
        _optic_mount(builder, z_centre, y_base, 0.034, 0.022)
    _picatinny(builder, z_centre - 0.030, z_centre + 0.030, y_base - 0.004, 0.0105, 6)


def _lens(builder, z, y, radius, glass=False, flip=False):
    """Optic lens: a shallow domed disc seated in a recessed bezel ring."""
    builder_circle = profile_circle(radius, 18)
    sign = -1.0 if flip else 1.0
    apex = z + sign * 0.004
    for index in range(len(builder_circle)):
        a = builder_circle[index]
        b = builder_circle[(index + 1) % len(builder_circle)]
        builder.triangle((a[0], y + a[1], z), (b[0], y + b[1], z), (0.0, y, apex))
    # Bezel: a proud seating ring and the retaining lip over the glass edge.
    tube(builder, (0.0, y, z), (0.0, y, z + sign * 0.0034), radius * 1.16, 18)
    tube(builder, (0.0, y, z + sign * 0.0034), (0.0, y, z + sign * 0.0050), radius * 1.02, 18)
    # Retaining screws around the bezel.
    for index in range(4):
        angle = TAU * (index + 0.5) / 4.0
        _screw_head(builder, (radius * 1.16 * math.cos(angle), y + radius * 1.16 * math.sin(angle),
                              z + sign * 0.0017), (0.0, 0.0, sign), 0.0022, 0.0020)


def _reticle(builder, z, y):
    """Emissive dot with the surrounding cross hair, which reads as a sight."""
    tube(builder, (0.0, y, z - 0.0014), (0.0, y, z + 0.0014), 0.0034, 12)
    # Cross hair: four posts, each rooted on the dot's rim and growing outward,
    # so the reticle reads as one lit shape rather than a dot plus detached
    # specks. Each post spans from inside the dot to its outer tip.
    for index in range(4):
        angle = index * math.pi / 2.0
        dx = math.cos(angle)
        dy = math.sin(angle)
        rounded_box(builder, (dx * 0.0086, y + dy * 0.0086, z), (0.0080, 0.0080, 0.0022), 0.0008)
    # Graduation ticks on the lower post.
    for index in range(3):
        t = 0.0060 + index * 0.0028
        rounded_box(builder, (0.0, y - t, z), (0.0034, 0.0016, 0.0012), 0.0004)


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
    # Chamfered bevels top and bottom, which are what make the slide silhouette.
    # The band runs fore-aft and across the slide, and extrudes off the face it
    # chamfers; swapping the two profile axes flips which way the band protrudes
    # without ever changing its outline.
    for sign in (-1.0, 1.0):
        _edge_chamfer(slide, (0.0, 0.006 + sign * (receiver_h * 0.5 - 0.004), 0.0),
                      (1.0, 0.0, 0.0) if sign < 0 else (0.0, 0.0, 1.0),
                      (0.0, 0.0, 1.0) if sign < 0 else (1.0, 0.0, 0.0),
                      receiver_len * 0.5 - 0.004, half_w - 0.0022, 0.0022, 0.0, 0.0026)
    # Cocking serrations at the rear.
    for index in range(6):
        z = z_rear - 0.016 - index * 0.010
        box(slide, (0.0, 0.007, z), (receiver_w + 0.0016, receiver_h * 0.72, 0.0034))
    # Forward serrations at the front of the slide.
    for index in range(4):
        box(slide, (0.0, 0.007, z_front + 0.030 + index * 0.009),
            (receiver_w + 0.0016, receiver_h * 0.60, 0.0030))
    # Rear sight dovetail and front post.
    rounded_box(slide, (0.0, slide_top + 0.006, z_rear - 0.014), (0.022, 0.010, 0.012), 0.002)
    box(slide, (0.0, slide_top + 0.019, z_rear - 0.014), (0.020, 0.016, 0.005))
    tube(slide, (0.0, slide_top + 0.026, z_rear - 0.014), (0.0, slide_top + 0.026, z_rear - 0.008),
         0.0030, 10)
    _screw_head(slide, (0.0, slide_top + 0.010, z_rear - 0.008), (0.0, 0.0, 1.0), 0.0022, 0.0020, True)
    rounded_box(slide, (0.0, slide_top + 0.005, z_front + 0.014), (0.012, 0.009, 0.010), 0.002)
    box(slide, (0.0, slide_top + 0.016, z_front + 0.014), (0.0016, 0.014, 0.0036))
    # Ejection port on the right, with the barrel hood visible through it.
    rounded_box(slide, (half_w + 0.001, slide_top - 0.006, z_front + 0.042),
                (0.006, 0.014, 0.040), 0.002)
    for sign in (-1.0, 1.0):
        box(slide, (half_w + 0.0012, slide_top - 0.006, z_front + 0.042 + sign * 0.020),
            (0.0052, 0.016, 0.0030))
    # Extractor on the right rear of the slide, with its pivot pin.
    extrude(slide, profile_rounded_rect(0.0038, 0.0060, 0.0016, 2), 0.0, 0.034,
            origin=(half_w + 0.0004, 0.008, z_rear - 0.040), u=(0.0, 1.0, 0.0),
            v=(0.0, 0.0, 1.0), w=(1.0, 0.0, 0.0))
    _pin(slide, (half_w - 0.0020, 0.004, z_rear - 0.028), (half_w + 0.0016, 0.004, z_rear - 0.028),
         0.0020, 0.0014)
    # Striker/firing-pin plate at the rear face, held by a screw.
    rounded_box(slide, (0.0, 0.006, z_rear + 0.0025), (0.014, 0.016, 0.0022), 0.0016, 2)
    _screw_head(slide, (0.0, 0.006, z_rear + 0.0040), (0.0, 0.0, 1.0), 0.0026, 0.0022, True)
    # Slide stop notch on the left flank plus the takedown-lever recess.
    rounded_box(slide, (-half_w - 0.0016, 0.002, z_rear - 0.026), (0.0034, 0.0110, 0.0140),
                0.0016, 2)
    for side in (-1.0, 1.0):
        _screw_head(slide, (side * (half_w + 0.0010), -0.002, z_front + 0.020), (side, 0.0, 0.0),
                    0.0026, 0.0022, True)
    # Top serrations / lightening cuts.
    for index in range(3):
        box(slide, (0.0, slide_top + 0.0015, z_rear - 0.052 - index * 0.016),
            (receiver_w * 0.6, 0.0030, 0.0060))
    # Optic cut: a machined flat deck with its two mounting screws, which is
    # how a modern slide mounts a red dot.
    box(slide, (0.0, slide_top + 0.0050, z_front + 0.030), (receiver_w * 0.72, 0.0022, 0.0480))
    for sign in (-1.0, 1.0):
        _screw_head(slide, (0.0, slide_top + 0.0062, z_front + 0.030 + sign * 0.0190),
                    (0.0, 1.0, 0.0), 0.0026, 0.0022, True)
    # Lightening windows: the milled apertures a modern slide carries, ringed by
    # their bevels and separated by the slide's remaining webs.
    for side in (-1.0, 1.0):
        for index in range(3):
            z = z_front + 0.052 + index * 0.021
            extrude(slide, profile_rounded_rect(0.0074, 0.0126, 0.0034, 3), 0.0, 0.0034,
                    origin=(side * (half_w - 0.0022), 0.008, z), u=(0.0, 1.0, 0.0),
                    v=(0.0, 0.0, 1.0), w=(side, 0.0, 0.0))
            for sign_v in (-1.0, 1.0):
                box(slide, (side * (half_w - 0.0008), 0.008,
                            z + sign_v * 0.0152), (0.0018, 0.0272, 0.0026))
    # Slide side stippling ahead of the forward serrations, which is how a
    # textured slide reads as a machined forging and not a smooth extrusion.
    for side in (-1.0, 1.0):
        _stipple_panel(slide, (side * (half_w + 0.0012), 0.004, z_front + 0.030),
                       (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.0120, 0.0090, 0.0036, 0.0009)
    # Muzzle-end bushing and the recoil-plug recess.
    tube(slide, (0.0, bore_y, z_front + 0.006), (0.0, bore_y, z_front - 0.002), 0.0118, 16)
    tube(slide, (0.0, 0.006, z_front + 0.002), (0.0, 0.006, z_front - 0.001), 0.0092, 14)
    # Iron sights on the slide, complete with their adjustment hardware.
    _iron_sights(slide, z_front + 0.016, z_rear - 0.016, slide_top + 0.002)
    parts.append((prefix + "slide", "ds_wsteel", slide))

    # ---- Slide controls: stop, safety, decocker and the LCI ----------------
    controls = Builder()
    # Slide stop lever on the left, with its inboard root reaching the frame.
    # The lever used to be a plate floating just outside the frame's flank; each
    # control now has a root that crosses the frame's surface so it is attached.
    rounded_box(controls, (-half_w - 0.0055, 0.000, z_front + 0.050), (0.0075, 0.0110, 0.0330),
                0.0022, 3)
    for index in range(4):
        box(controls, (-half_w - 0.0092, 0.000, z_front + 0.038 + index * 0.0072),
            (0.0020, 0.0098, 0.0034))
    # Root plate spanning from inside the frame to the lever.
    box(controls, (-half_w - 0.0030, 0.000, z_front + 0.050), (0.0090, 0.0100, 0.0300))
    _pin(controls, (-half_w - 0.0080, 0.000, z_front + 0.038), (-half_w + 0.0050, 0.000, z_front + 0.038),
         0.0022, 0.0015)
    _pin(controls, (-half_w - 0.0080, -0.0080, z_front + 0.050), (-half_w + 0.0050, -0.0080, z_front + 0.050),
         0.0018, 0.0012)
    # Frame-mounted thumb safety with its detent plunger and both positions.
    rounded_box(controls, (-half_w - 0.0050, -0.006, z_rear - 0.046), (0.0070, 0.0105, 0.0260),
                0.0022, 3)
    for index in range(3):
        box(controls, (-half_w - 0.0086, -0.006, z_rear - 0.056 + index * 0.0072),
            (0.0018, 0.0092, 0.0030))
    box(controls, (-half_w - 0.0030, -0.006, z_rear - 0.046), (0.0090, 0.0096, 0.0240))
    _pin(controls, (-half_w - 0.0075, -0.006, z_rear - 0.036), (-half_w + 0.0050, -0.006, z_rear - 0.036),
         0.0020, 0.0014)
    _screw_head(controls, (-half_w - 0.0040, -0.0080, z_rear - 0.046), (0.0, -1.0, 0.0), 0.0022, 0.0020)
    # Decocker/safety lever on the right, rooted into the frame the same way.
    rounded_box(controls, (half_w + 0.0048, -0.004, z_rear - 0.044), (0.0066, 0.0100, 0.0240), 0.0020, 2)
    box(controls, (half_w + 0.0030, -0.004, z_rear - 0.044), (0.0090, 0.0092, 0.0220))
    _pin(controls, (half_w + 0.0070, -0.004, z_rear - 0.034), (half_w - 0.0050, -0.004, z_rear - 0.034),
         0.0018, 0.0012)
    # Loaded-chamber indicator on the slide's top rear plus the striker status pin.
    tube(controls, (0.0, slide_top - 0.0030, z_rear - 0.030), (0.0, slide_top + 0.0038, z_rear - 0.030),
         0.0030, 10)
    tube(controls, (half_w - 0.0030, 0.004, z_rear - 0.006), (half_w + 0.0040, 0.004, z_rear - 0.006),
         0.0026, 10)
    parts.append((prefix + "controls", "ds_wblack", controls))

    # ---- Frame, dust cover, accessory rail -----------------------------------
    frame = Builder()
    rounded_box(frame, (0.0, -receiver_h * 0.5 - 0.004, z_front + 0.030),
                (receiver_w * 0.94, 0.020, receiver_len * 0.72), 0.004)
    # Dust cover side rails, panel line and the accessory rail underneath.
    for side in (-1.0, 1.0):
        box(frame, (side * (half_w * 0.94 + 0.0010), -receiver_h * 0.5 - 0.004, z_front + 0.030),
            (0.0016, 0.0170, receiver_len * 0.68))
        _screw_head(frame, (side * (half_w * 0.94 + 0.0014), -receiver_h * 0.5 - 0.010,
                            z_front + 0.058), (side, 0.0, 0.0), 0.0024, 0.0020, True)
    _picatinny(frame, z_front - 0.004, z_front + 0.058, -receiver_h * 0.5 - 0.016,
               0.0090, 5)
    # Trigger guard, trigger and controls.
    _trigger_group(frame, z_front + 0.062, -receiver_h * 0.5 - 0.004, 0.042)
    rounded_box(frame, (-half_w - 0.003, -0.004, z_rear - 0.030), (0.008, 0.014, 0.024), 0.002)
    tube(frame, (half_w + 0.002, 0.000, z_rear - 0.024), (half_w + 0.008, 0.000, z_rear - 0.024),
         0.0052, 12)
    _knurl(frame, (half_w + 0.0074, 0.000, z_rear - 0.024), (1.0, 0.0, 0.0), 0.0052, 0.0040, 10)
    # Slide stop lever on the left, on its own pin.
    rounded_box(frame, (-half_w - 0.0050, -0.002, z_front + 0.048), (0.0075, 0.0100, 0.0280),
                0.0022, 2)
    _pin(frame, (-half_w - 0.0075, -0.002, z_front + 0.034), (-half_w + 0.0005, -0.002, z_front + 0.034),
         0.0020, 0.0014)
    # Takedown lever and its detent on the right.
    rounded_box(frame, (half_w + 0.0040, -0.004, z_front + 0.040), (0.0070, 0.0090, 0.0200),
                0.0020, 2)
    _screw_head(frame, (half_w + 0.0076, -0.004, z_front + 0.040), (1.0, 0.0, 0.0), 0.0026, 0.0022)
    # Frame panel lines down both flanks and the dust-cover front bevel.
    for side in (-1.0, 1.0):
        box(frame, (side * (half_w * 0.94 + 0.0018), -receiver_h * 0.5 + 0.002, z_rear - 0.040),
            (0.0014, 0.0120, 0.0480))
    for side in (-1.0, 1.0):
        _hex_bolt(frame, (side * half_w * 0.40, -receiver_h * 0.5 - 0.0145, z_front + 0.008),
                  (0.0, -1.0, 0.0), 0.0032, 0.0044)
    # Thumb rest / gas pedal on the left, with its stippled face and screws.
    rounded_box(frame, (-half_w - 0.0068, -0.004, z_front + 0.026), (0.0090, 0.0120, 0.0340),
                0.0028, 3)
    _stipple_panel(frame, (-half_w - 0.0112, -0.004, z_front + 0.026), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   0.0130, 0.0044, 0.0034, 0.0009)
    for sign in (-1.0, 1.0):
        _screw_head(frame, (-half_w - 0.0068, -0.004 + sign * 0.0040, z_front + 0.010),
                    (0.0, 0.0, -1.0), 0.0022, 0.0020, True)
    # Dust-cover underside ribs and the frame's own front block bevel.
    for index in range(5):
        box(frame, (0.0, -receiver_h * 0.5 - 0.0128, z_front + 0.014 + index * 0.0110),
            (receiver_w * 0.72, 0.0026, 0.0060))
    rounded_box(frame, (0.0, -receiver_h * 0.5 - 0.004, z_front + 0.002), (receiver_w * 0.88, 0.0180, 0.0140),
                0.0034, 3)
    # Backstrap stippling behind the grip safety.
    _stipple_panel(frame, (0.0, -receiver_h * 0.5 - 0.020, z_rear - 0.014),
                   (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), 0.0100, 0.0090, 0.0034, 0.0009)
    parts.append((prefix + "frame", "ds_wpolymer", frame))

    # ---- Grip: integrated with the frame, so a real pistol's grip angle ------
    grip = Builder()
    _pistol_grip(grip, z_rear - 0.020, -receiver_h * 0.5 - 0.012, 0.34,
                 spec["pistol_len"], half_w * 0.98)
    # Beavertail tang above the web of the hand.
    rounded_box(grip, (0.0, -0.004, z_rear - 0.006), (receiver_w * 0.8, 0.014, 0.034), 0.005)
    # Backstrap grip safety with its pivot pin and a checkered face.
    rounded_box(grip, (0.0, -0.008, z_rear - 0.014), (receiver_w * 0.62, 0.018, 0.016), 0.0030, 2)
    for index in range(4):
        box(grip, (0.0, -0.016 + index * 0.0036, z_rear - 0.014), (receiver_w * 0.52, 0.0013, 0.0120))
    _pin(grip, (-receiver_w * 0.30, -0.004, z_rear - 0.016), (receiver_w * 0.30, -0.004, z_rear - 0.016),
         0.0022, 0.0015)
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
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.002), (0.0, bore_y, z_muzzle_back + 0.002),
         0.0090, 16)
    # Locking block and feed ramp at the chamber. The block spans down from the
    # barrel's axis so it bites the barrel's underside, and the hood extrusion
    # starts inside the barrel's radius: placed clear of it they floated.
    rounded_box(barrel, (0.0, bore_y - 0.0040, z_front + 0.024), (0.0156, 0.0180, 0.0240), 0.0022, 2)
    extend = profile_rounded_rect(0.0086, 0.0058, 0.0018, 2)
    extrude(barrel, extend, 0.0, 0.0100, origin=(0.0, bore_y + 0.0030, z_front + 0.020),
            u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), w=(0.0, 1.0, 0.0))
    # Chamber witness ring and the crown.
    tube(barrel, (0.0, bore_y, z_front + 0.008), (0.0, bore_y, z_front + 0.012), 0.0096, 16)
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
    _pin(internals, (-half_w - 0.0035, -0.002, z_front + 0.028), (half_w + 0.0035, -0.002, z_front + 0.028),
         0.0022, 0.0015)
    # Recoil spring on its guide rod, with the flat spring face at the rear. The
    # face starts *inside* the rod's span so the two overlap; butted end to end
    # with a 4 mm gap between them the face was a detached disc.
    tube(internals, (0.0, -receiver_h * 0.5 - 0.008, z_front + 0.072),
         (0.0, -receiver_h * 0.5 - 0.008, z_front + 0.010), 0.0044, 12, steps=3)
    tube(internals, (0.0, -receiver_h * 0.5 - 0.008, z_front + 0.016),
         (0.0, -receiver_h * 0.5 - 0.008, z_front + 0.002), 0.0068, 12)
    for index in range(9):
        z = z_front + 0.010 + index * 0.0068
        tube(internals, (0.0, -receiver_h * 0.5 - 0.008, z - 0.0016),
             (0.0, -receiver_h * 0.5 - 0.008, z + 0.0016), 0.0054, 10)
    # Striker channel and the ejector at the rear of the frame.
    rounded_box(internals, (0.0, -0.002, z_rear - 0.048), (receiver_w * 0.5, 0.010, 0.026), 0.0022, 2)
    extrude(internals, profile_rounded_rect(0.0030, 0.0060, 0.0014, 2), 0.0, 0.020,
            origin=(half_w * 0.42, 0.000, z_rear - 0.040), u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0),
            w=(1.0, 0.0, 0.0))
    parts.append((prefix + "internals", "ds_wblack", internals))

    # ---- Frame slide rails, locking block and magazine well -----------------
    rails = Builder()
    # The frame's slide rails: bearing strips inset into the frame's flanks. They
    # are extruded from the frame's own centreline outwards, so each strip passes
    # through the frame's material instead of sitting just proud of it.
    for side in (-1.0, 1.0):
        for sign in (-1.0, 1.0):
            extrude(rails, profile_rounded_rect(0.0018, 0.0018, 0.0010, 2), 0.0, half_w * 1.08,
                    origin=(0.0, -receiver_h * 0.5 + 0.0120 * sign + 0.0120, z_rear - 0.012),
                    u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(side, 0.0, 0.0),
                    cap_start=False, cap_end=False)
        # Dust-cover underside rail with cooling vents.
        _mlok_slot(rails, (side * half_w * 0.62, -receiver_h * 0.5 - 0.0080, z_front + 0.052),
                   (0.0, -1.0, 0.0))
        _screw_head(rails, (side * half_w * 0.62, -receiver_h * 0.5 - 0.0080, z_front + 0.030),
                    (0.0, -1.0, 0.0), 0.0026, 0.0022, True)
    # Locking block under the barrel with its two cross pins.
    rounded_box(rails, (0.0, -receiver_h * 0.5 + 0.0080, z_front + 0.030),
                (receiver_w * 0.80, 0.0200, 0.0320), 0.0028, 3)
    _pin(rails, (-half_w * 0.62, -receiver_h * 0.5 + 0.0080, z_front + 0.020),
         (half_w * 0.62, -receiver_h * 0.5 + 0.0080, z_front + 0.020), 0.0024, 0.0016)
    _pin(rails, (-half_w * 0.62, -receiver_h * 0.5 + 0.0080, z_front + 0.042),
         (half_w * 0.62, -receiver_h * 0.5 + 0.0080, z_front + 0.042), 0.0024, 0.0016)
    # Magazine well: a flared funnel hung off the well's inner walls, extruded
    # from the centreline outward so each wall crosses its host.
    for sign in (-1.0, 1.0):
        extrude(rails, profile_rounded_rect(0.0014, 0.0100, 0.0012, 2), 0.0, half_w * 1.10,
                origin=(0.0, -receiver_h * 0.5 - 0.030, z_rear - 0.028),
                u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(sign, 0.0, 0.0))
    extrude(rails, profile_rounded_rect(half_w * 0.98, 0.0026, 0.0014, 2), 0.0, 0.0090,
            origin=(0.0, -receiver_h * 0.5 - 0.036, z_rear - 0.028), u=(1.0, 0.0, 0.0),
            v=(0.0, 0.0, 1.0), w=(0.0, -1.0, 0.0))
    # Grip-to-frame retention screws and the frame's own lightening cuts.
    for side in (-1.0, 1.0):
        _screw_head(rails, (side * half_w * 0.94, -receiver_h * 0.5 - 0.012, z_rear - 0.048),
                    (side, 0.0, 0.0), 0.0026, 0.0022, True)
        extrude(rails, profile_rounded_rect(0.0040, 0.0030, 0.0016, 2), 0.0, 0.0020,
                origin=(side * half_w * 0.94, -receiver_h * 0.5 - 0.002, z_front + 0.010),
                u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(side, 0.0, 0.0))
    # ---- Hammer, sear and the fire-control housing --------------------------
    parts.append((prefix + "rails", "ds_wblack", rails))
    hammer = Builder()
    # The fire-control group lives inside the frame's rear, so every part is
    # sized and placed from the frame's own box: the spur crosses the backstrap,
    # the mainspring housing sits in it, and the sear block spans the frame's
    # width. Sized as free-standing blocks they floated clear of the frame.
    backstrap = z_rear - 0.0100
    rounded_box(hammer, (0.0, -0.004, backstrap), (receiver_w, 0.0260, 0.0220), 0.0028, 3)
    for index in range(6):
        box(hammer, (0.0, 0.0064, backstrap + 0.0075 - index * 0.0030),
            (receiver_w * 0.86, 0.0032, 0.0012))
    _pin(hammer, (-half_w * 0.55, -0.004, backstrap + 0.0060),
         (half_w * 0.55, -0.004, backstrap + 0.0060), 0.0022, 0.0015)
    # Hammer strut reaching down into the mainspring housing.
    tube(hammer, (0.0, -0.008, backstrap - 0.0060), (0.0, -0.022, backstrap - 0.0200), 0.0030, 10)
    # Mainspring housing in the backstrap, serrated, with its own pin.
    housing_z = backstrap - 0.0300
    rounded_box(hammer, (0.0, -0.014, housing_z), (receiver_w * 0.94, 0.0300, 0.0240), 0.0030, 3)
    for index in range(7):
        box(hammer, (0.0, -0.0270, housing_z + 0.0090 - index * 0.0030),
            (receiver_w * 0.78, 0.0022, 0.0016))
    _pin(hammer, (-half_w * 0.58, -0.014, housing_z + 0.0120),
         (half_w * 0.58, -0.014, housing_z + 0.0120), 0.0020, 0.0014)
    # Sear and disconnector block spanning the frame's width behind the trigger.
    sear_z = backstrap - 0.0460
    rounded_box(hammer, (0.0, -0.004, sear_z), (receiver_w * 0.92, 0.0250, 0.0200), 0.0024, 2)
    _pin(hammer, (-half_w * 0.52, -0.004, sear_z + 0.0060),
         (half_w * 0.52, -0.004, sear_z + 0.0060), 0.0018, 0.0012)
    _pin(hammer, (-half_w * 0.52, -0.010, sear_z - 0.0050),
         (half_w * 0.52, -0.010, sear_z - 0.0050), 0.0016, 0.0011)
    tube(hammer, (-0.0040, -0.012, sear_z + 0.0160), (0.0040, -0.012, sear_z + 0.0160), 0.0030, 10)
    # Panel lines separating the fire-control housing from the dust cover.
    for side in (-1.0, 1.0):
        box(hammer, (side * (half_w + 0.0010), -0.006, sear_z),
            (0.0020, 0.0220, 0.0400))
    parts.append((prefix + "hammer", "ds_wsteel", hammer))
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
    # The upper and lower are separate forgings on a real rifle, so they are
    # separate volumes here with a seam line, a proud mating lip and the pins
    # and paddles that hold and operate them.
    seam_y = 0.002
    upper_h = (receiver_h * 0.5 + seam_y) * 0.5
    lower_h = (receiver_h * 0.5 - seam_y) * 0.5
    upper = Builder()
    rounded_box(upper, (0.0, seam_y + upper_h, 0.0), (receiver_w, receiver_h * 0.5 - seam_y,
                receiver_len), 0.005, corner_segments=4)
    # Chamfered bevel running the whole way around the upper's edge.
    for sign in (-1.0, 1.0):
        _edge_chamfer(upper, (0.0, seam_y + upper_h + sign * (receiver_h * 0.25 - seam_y * 0.5), 0.0),
                      (1.0, 0.0, 0.0) if sign < 0 else (0.0, 0.0, 1.0),
                      (0.0, 0.0, 1.0) if sign < 0 else (1.0, 0.0, 0.0),
                      receiver_len * 0.5 - 0.004, 0.0028, 0.0022, 0.0, 0.0026)
    # Upper's own panel lines: a flat top deck and ribbed flanks.
    for index in range(3):
        box(upper, (0.0, seam_y + upper_h + receiver_h * 0.25 - 0.0018,
                    -receiver_len * 0.24 + index * receiver_len * 0.24),
            (receiver_w * 0.72, 0.0022, receiver_len * 0.13))
    for side in (-1.0, 1.0):
        box(upper, (side * (half_w + 0.0011), seam_y + upper_h + receiver_h * 0.06, 0.0),
            (0.0016, receiver_h * 0.16, receiver_len * 0.80))
    # Picatinny flat cut into the top deck, ahead of the rail.
    box(upper, (0.0, seam_y + upper_h + receiver_h * 0.25 - 0.0010, z_front + 0.010),
        (receiver_w * 0.86, 0.0014, 0.020))
    # Serial-plate recess: a flat proud plate with engraved-looking ribs and the
    # two rivets that hold it on.
    serial_y = seam_y + lower_h + 0.0012
    rounded_box(upper, (-half_w, serial_y, z_rear - 0.030), (0.0028, 0.0140, 0.0320), 0.0018, 2)
    for index in range(3):
        box(upper, (-half_w - 0.0022, serial_y + 0.0042 - index * 0.0042, z_rear - 0.030),
            (0.0016, 0.0014, 0.0240))
    for sign in (-1.0, 1.0):
        _screw_head(upper, (-half_w - 0.0018, serial_y, z_rear - 0.030 + sign * 0.0128),
                    (-1.0, 0.0, 0.0), 0.0020, 0.0018, True)
    parts.append((prefix + "upper_receiver", "ds_wbody", upper))

    body = Builder()
    rounded_box(body, (0.0, seam_y - lower_h, 0.0), (receiver_w * 0.995, receiver_h * 0.5 + seam_y,
                receiver_len), 0.005, corner_segments=4)
    # Seam line plus the proud mating lip between the two forgings.
    box(body, (0.0, seam_y - 0.0014, 0.0), (receiver_w + 0.0018, 0.0028, receiver_len * 0.99))
    box(body, (0.0, seam_y - 0.0042, 0.0), (receiver_w + 0.0030, 0.0016, receiver_len * 0.97))
    # Chamfered bevel around the lower's edge.
    _edge_chamfer(body, (0.0, seam_y - lower_h - receiver_h * 0.25 + seam_y * 0.5, 0.0),
                  (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                  receiver_len * 0.5 - 0.004, 0.0026, 0.0020, 0.0, 0.0024)
    # Magwell flare at the front of the lower, with its funnel bevel.
    rounded_box(body, (0.0, receiver_bottom - 0.008, z_front + 0.020),
                (receiver_w * 1.08, 0.030, 0.058), 0.005)
    rounded_box(body, (0.0, receiver_bottom - 0.014, z_front + 0.020),
                (receiver_w * 1.12, 0.010, 0.064), 0.0022, 2)
    # Pivot pin and rear takedown pin, with their detents.
    for z in (z_front + 0.012, z_rear - 0.016):
        _pin(body, (-half_w - 0.0030, -0.004, z), (half_w + 0.0030, -0.004, z), 0.0028, 0.0018)
    _screw_head(body, (0.0, receiver_bottom - 0.014, z_rear - 0.016), (0.0, -1.0, 0.0), 0.0028, 0.0024)
    # Bolt catch on the left face: paddle, plunger and roll pin.
    rounded_box(body, (-half_w - 0.004, 0.004, z_front + 0.052), (0.008, 0.014, 0.030), 0.002)
    rounded_box(body, (-half_w - 0.0055, 0.004, z_front + 0.066), (0.0060, 0.0110, 0.0090), 0.0018, 2)
    _pin(body, (-half_w - 0.0070, 0.004, z_front + 0.044), (-half_w - 0.0005, 0.004, z_front + 0.044),
         0.0018, 0.0012)
    # Magazine-release paddle right behind the well, on its own pivot.
    rounded_box(body, (0.0, receiver_bottom + 0.006, z_front + 0.048), (0.019, 0.011, 0.014), 0.0018, 2)
    _pin(body, (-0.0200, receiver_bottom + 0.006, z_front + 0.048),
         (0.0200, receiver_bottom + 0.006, z_front + 0.048), 0.0020, 0.0014)
    # Panel line splitting the lower's flank into a well panel and a trigger
    # housing panel, each with the proud frame that separates the two volumes.
    for side in (-1.0, 1.0):
        # The panel's two profile axes are its two in-plane directions on the
        # flank: fore-aft along the receiver, and the height of the lower.
        _panel_recess(body, (side * (half_w + 0.0016), seam_y - lower_h * 1.05,
                             z_front + 0.040), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                      receiver_len * 0.17, lower_h * 0.62, 0.0014, 0.0010)
        _screw_head(body, (side * (half_w + 0.0016), seam_y - lower_h * 1.30, z_front + 0.076),
                    (side, 0.0, 0.0), 0.0026, 0.0022, True)
    parts.append((prefix + "lower_receiver", "ds_wbody", body))

    # ---- Handguard ----------------------------------------------------------
    guard = Builder()
    _handguard(guard, z_hg_front, z_front + 0.004, bore_y, hg_half_w, hg_half_h,
               slots=5, vent_rows=2)
    # Front sight tower sits on the guard's muzzle end, with a bayonet lug on
    # the categories that actually mount one.
    _front_sight_tower(guard, z_hg_front + 0.020, bore_y, hg_half_h, hg_half_w,
                       bayonet_lug=category in ("assault", "shotgun", "marksman"))
    parts.append((prefix + "handguard", "ds_wbody", guard))

    # ---- Top rail spanning receiver and handguard ---------------------------
    rail_builder = Builder()
    _picatinny(rail_builder, z_front + 0.002, z_rear - 0.004, receiver_top + 0.0035,
               0.0105, 12)
    # Second rail segment on the handguard's flat, so the two volumes read apart.
    _picatinny(rail_builder, z_hg_front + 0.026, z_front - 0.006, receiver_top + 0.0035,
               0.0105, 8)
    parts.append((prefix + "rail", "ds_wsteel", rail_builder))

    # ---- Barrel, barrel nut, gas block, gas tube, muzzle -------------------
    barrel = Builder()
    _barrel_nut(barrel, z_front + 0.006, z_front + 0.030, bore_y, hg_half_w)
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.030), (0.0, bore_y, z_hg_front + 0.010),
         0.0092, 16, steps=4)
    tube(barrel, (0.0, bore_y, z_hg_front + 0.010), (0.0, bore_y, z_front), 0.0120, 16, steps=3)
    # Taper steps and machining shoulders where the profile changes: a gas-block
    # journal, a chamber shoulder and the muzzle shoulder.
    tube(barrel, (0.0, bore_y, z_hg_front + 0.010), (0.0, bore_y, z_hg_front + 0.014),
         0.0126, 16)
    tube(barrel, (0.0, bore_y, z_muzzle_back + 0.030), (0.0, bore_y, z_muzzle_back + 0.036),
         0.0100, 16)
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.030), (0.0, bore_y, z_muzzle_back - 0.024),
         0.0098, 16)
    tube(barrel, (0.0, bore_y, z_front + 0.004), (0.0, bore_y, z_front), 0.0130, 16)
    # Gas block journal: a flat machined onto the barrel under the block.
    box(barrel, (0.0, bore_y + 0.0102, z_hg_front + 0.070), (0.0170, 0.0040, 0.0340))
    # Fluting: six milled grooves down the exposed barrel length, in three
    # bands so the grooves read as long channels rather than short dashes.
    for index in range(6):
        angle = TAU * index / 6.0
        radial = (math.cos(angle), math.sin(angle), 0.0)
        for band in range(3):
            extrude(barrel, profile_rounded_rect(0.0024, 0.0070, 0.0012, 2), 0.0, 0.0016,
                    origin=(0.0092 * radial[0], bore_y + 0.0092 * radial[1],
                            z_muzzle_back + 0.028 + band * 0.038),
                    u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=radial)
    # Chamber and muzzle crowns, plus the bore running the whole length.
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.006), (0.0, bore_y, z_muzzle_back - 0.002),
         0.0086, 16, cap_start=False)
    tube(barrel, (0.0, bore_y, z_muzzle_back - 0.030), (0.0, bore_y, z_front),
         0.0052, 14, cap_start=False, cap_end=False)
    parts.append((prefix + "barrel", "ds_wsteel", barrel))

    gas = Builder()
    _gas_block(gas, bore_y + hg_half_h + 0.014, bore_y, 0.026,
               gas_tube_to=(bore_y + hg_half_h + 0.004, z_front - 0.004), half_w=hg_half_w * 0.92)
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
    _end_plate(stock, z_rear - 0.004, bore_y + 0.006, half_w,
               sling_loop=category not in ("launcher",))
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
        # Bipod hub: the bracket that clamps the mount, with its pivot pin.
        rounded_box(bipod, (0.0, -0.040, z_hg_front + 0.040), (0.026, 0.024, 0.038), 0.0040, 3)
        _pin(bipod, (-0.0140, -0.040, z_hg_front + 0.040), (0.0140, -0.040, z_hg_front + 0.040),
             0.0024, 0.0016)
        for sign in (-1.0, 1.0):
            _screw_head(bipod, (sign * 0.0100, -0.052, z_hg_front + 0.040), (0.0, -1.0, 0.0),
                        0.0028, 0.0024, True)
        for side in (-1.0, 1.0):
            # Legs: an outer tube with a telescoping inner leg, adjustment
            # notches, a foot and a spring-loaded detent at each joint.
            leg = [(0.0, -0.030, z_hg_front + 0.040),
                   (side * 0.030, -0.090, z_hg_front + 0.030),
                   (side * 0.042, -0.150, z_hg_front + 0.010)]
            swept_tube(bipod, leg, 0.0055, 10)
            for index in range(3):
                t = 0.30 + index * 0.22
                px = side * (0.030 * t + 0.042 * (1.0 - t) * 0.0) * 1.0
                py = -0.030 - 0.120 * t
                pz = z_hg_front + 0.040 - 0.030 * t
                tube(bipod, (px, py, pz), (px, py - 0.004, pz), 0.0072, 10)
                _screw_head(bipod, (px, py - 0.0055, pz), (0.0, -1.0, 0.0), 0.0024, 0.0020)
            rounded_box(bipod, (side * 0.046, -0.158, z_hg_front + 0.004), (0.012, 0.014, 0.020), 0.0030, 2)
            # Foot spike and the rubber pad around it.
            tube(bipod, (side * 0.046, -0.165, z_hg_front + 0.004),
                 (side * 0.046, -0.176, z_hg_front + 0.004), 0.0040, 10)
            tube(bipod, (side * 0.046, -0.158, z_hg_front + 0.004),
                 (side * 0.046, -0.170, z_hg_front + 0.004), 0.0082, 12)
            for index in range(3):
                box(bipod, (side * 0.046, -0.158 + index * 0.0040, z_hg_front + 0.004),
                    (0.0164, 0.0014, 0.0164))
        parts.append((prefix + "bipod", "ds_wsteel", bipod))

    # ---- Pump / tube magazine (shotgun) ------------------------------------
    if spec.get("pump"):
        pump = Builder()
        tube(pump, (0.0, bore_y - 0.030, z_muzzle_back - 0.030), (0.0, bore_y - 0.030, z_hg_front + 0.030),
             0.0140, 16, steps=3)
        # Magazine tube end cap, its detent and the barrel clamp.
        tube(pump, (0.0, bore_y - 0.030, z_muzzle_back - 0.030), (0.0, bore_y - 0.030, z_muzzle_back - 0.044),
             0.0162, 16)
        _knurl(pump, (0.0, bore_y - 0.030, z_muzzle_back - 0.038), (0.0, 0.0, 1.0), 0.0162, 0.0070, 14)
        _screw_head(pump, (0.0, bore_y - 0.030, z_muzzle_back - 0.047), (0.0, 0.0, -1.0), 0.0040, 0.0030, True)
        rounded_box(pump, (0.0, bore_y - 0.008, z_hg_front + 0.078), (0.026, 0.030, 0.014), 0.0030, 2)
        # Forend: a ribbed shell with finger grooves and its action-bar slot.
        forend_y = bore_y - 0.044
        forend_half_h = 0.020
        rounded_box(pump, (0.0, forend_y, z_hg_front + 0.006), (0.040, 0.040, 0.108), 0.0100, 3)
        for index in range(6):
            along = z_hg_front + 0.030 + index * 0.032
            tube(pump, (0.0, bore_y - 0.030, along - 0.008), (0.0, bore_y - 0.030, along + 0.008),
                 0.0165, 14)
            # Ribs on the forend's flanks: they are centred on the flank plane
            # (x = 20 mm) so half of each rib lies inside the shell. Centred at
            # 21.2 mm with a 3 mm section they missed the shell entirely.
            for side in (-1.0, 1.0):
                box(pump, (side * 0.0188, forend_y, along), (0.0060, 0.0340, 0.0080))
        # Finger grooves on the forend's underside.
        for index in range(5):
            box(pump, (0.0, forend_y - forend_half_h + 0.0020, z_hg_front + 0.028 + index * 0.018),
                (0.030, 0.0060, 0.0100))
        # Stippled grip field on both flanks.
        for index in range(7):
            for column in range(3):
                box(pump, ((column - 1.0) * 0.0100, forend_y - 0.0015,
                           z_hg_front + 0.032 + index * 0.016), (0.0060, 0.0040, 0.0060))
        # Action bars, running back into the receiver's mortise.
        for side in (-1.0, 1.0):
            box(pump, (side * 0.0188, forend_y - 0.0160, z_hg_front + 0.006),
                (0.0040, 0.0190, 0.1160))
        # Heat shield with vent slots over the barrel.
        rounded_box(pump, (0.0, bore_y + 0.010, z_muzzle_back + 0.060), (0.030, 0.012, 0.120), 0.0030, 2)
        for index in range(5):
            _mlok_slot(pump, (0.0, bore_y + 0.0155, z_muzzle_back + 0.020 + index * 0.020), (0.0, 1.0, 0.0))
        # Shell carrier and the elevator slot at the receiver join.
        rounded_box(pump, (0.0, bore_y - 0.062, z_hg_front + 0.078), (0.026, 0.010, 0.030), 0.0024, 2)
        parts.append((prefix + "pump", "ds_wpolymer", pump))

    # ---- Rocket (launcher) --------------------------------------------------
    if spec.get("rocket"):
        rocket = Builder()
        tube(rocket, (0.0, bore_y, z_hg_front - 0.230), (0.0, bore_y, z_hg_front + 0.020),
             0.038, 20, steps=3)
        # Reinforcing rings around the tube and the internal rocket nose.
        for index in range(4):
            tube(rocket, (0.0, bore_y, z_hg_front - 0.190 + index * 0.056),
                 (0.0, bore_y, z_hg_front - 0.184 + index * 0.056), 0.0405, 20)
            _hex_bolt(rocket, (0.0, bore_y + 0.0405, z_hg_front - 0.187 + index * 0.056), (0.0, 1.0, 0.0),
                      0.0028, 0.0040)
        # Sight mount and the top rail over the tube.
        rounded_box(rocket, (0.0, bore_y + 0.046, z_hg_front - 0.130), (0.022, 0.016, 0.090), 0.0030, 2)
        _picatinny(rocket, z_hg_front - 0.170, z_hg_front - 0.090, bore_y + 0.055, 0.0105, 8)
        # Blast shield and the front clamp.
        rounded_box(rocket, (0.0, bore_y, z_hg_front + 0.014), (0.060, 0.060, 0.014), 0.0080, 3)
        extrude(rocket, profile_circle(0.042, 18), 0.0, 0.014,
                origin=(0.0, bore_y, z_hg_front + 0.006), u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0),
                w=(0.0, 0.0, -1.0), cap_start=True, cap_end=True)
        for index in range(6):
            angle = TAU * index / 6.0
            _hex_bolt(rocket, (0.0315 * math.cos(angle), bore_y + 0.0315 * math.sin(angle),
                               z_hg_front + 0.006), (0.0, 0.0, -1.0), 0.0030, 0.0044)
        cone_builder = Builder()
        tube(cone_builder, (0.0, bore_y, z_hg_front - 0.230), (0.0, bore_y, z_hg_front - 0.300),
             0.038, 20, radius_end=0.014, cap_end=True)
        # The cone's own rear skirt and the four fins moulded onto it. The cone
        # tapers linearly from r=0.038 at its base to r=0.014 at its tip, so each
        # fin's radius is evaluated from that taper at the fin's own z, and the
        # fin is extruded symmetrically about the surface so it bites the cone.
        cone_base_z, cone_tip_z = z_hg_front - 0.230, z_hg_front - 0.300
        cone_r_base, cone_r_tip = 0.038, 0.014
        tube(cone_builder, (0.0, bore_y, z_hg_front - 0.222), (0.0, bore_y, z_hg_front - 0.230),
             0.0405, 20)
        for index in range(4):
            angle = TAU * index / 4.0
            radial = (math.cos(angle), math.sin(angle), 0.0)
            for along in (z_hg_front - 0.238, z_hg_front - 0.258):
                t = (along - cone_base_z) / (cone_tip_z - cone_base_z)
                local_r = cone_r_base + (cone_r_tip - cone_r_base) * t
                extrude(cone_builder, profile_rounded_rect(0.0022, 0.0140, 0.0012, 2),
                        -0.0060, 0.0060,
                        origin=(local_r * radial[0], bore_y + local_r * radial[1], along),
                        u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), w=radial)
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
        # A real optic: rail interface, mount with throw lever and ring caps,
        # body, turrets, bezels. `_rail_mounted_optic` builds all of it.
        _rail_mounted_optic(body, z_centre, rail_y, kind)
        glass_len = 0.070 if kind == "acog" else 0.064
        glass = Builder()
        _lens(glass, z_centre - glass_len * 0.5, rail_y + 0.034 +
              (0.006 if kind != "holo" else 0.002), 0.019 if kind == "acog" else 0.017, glass=True)
        dot = Builder()
        _reticle(dot, z_centre - glass_len * 0.47, rail_y + 0.034 +
                 (0.006 if kind != "holo" else 0.002))
        # The mount itself, on its own geometry so its screws read separately.
        mount = Builder()
        y_lens = rail_y + 0.034 + (0.006 if kind != "holo" else 0.002)
        _rail_clamp(mount, z_centre, rail_y - 0.0040, 0.030 if kind == "acog" else 0.026,
                    True, 3 if kind == "acog" else 2)
        for side in (-1.0, 1.0):
            _hex_bolt(mount, (side * 0.0160, rail_y + 0.005, z_centre + side * 0.024),
                      (side, 0.0, 0.0), 0.0030, 0.0042)
        # Ring cap bolts: each cap is split and pulled down by two screws.
        for sign in (-1.0, 1.0):
            for side in (-1.0, 1.0):
                _screw_head(mount, (side * 0.0160, y_lens + 0.0132,
                                    z_centre + sign * (0.030 if kind == "acog" else 0.026) * 0.80),
                            (0.0, 1.0, 0.0), 0.0026, 0.0024, True)
        # Elevation/windage detent bosses and the mount's own level bubble.
        for side in (-1.0, 1.0):
            _hex_bolt(mount, (side * 0.0188, y_lens, z_centre), (side, 0.0, 0.0), 0.0026, 0.0036)
        tube(mount, (0.0, rail_y + 0.0240, z_centre - 0.010), (0.0, rail_y + 0.0270, z_centre - 0.010),
             0.0034, 10)
        # Eyepiece dioptre marks and the zeroing witness strip on the tube.
        _graduations(mount, (0.0, y_lens, z_centre + glass_len * 0.45), (0.0, 0.0, 1.0), 0.0225, 9, 1.6)
        return [(prefix + "body", "ds_wblack", body),
                (prefix + "mount", "ds_wblack", mount),
                (prefix + "lens", "ds_wglass", glass),
                (prefix + "reticle", "ds_wreticle", dot)]

    if kind in ("compensator", "muzzlebrake", "suppressor", "longbarrel"):
        z_muzzle_back = -receiver_len * 0.5 - spec["handguard"][0] - spec["barrel_len"]
        barrel = Builder()
        if kind == "longbarrel":
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.140),
                 (0.0, spec["bore_y"], z_muzzle_back + 0.010), 0.0092, 16, steps=3)
            # Extended barrel gains a taper step, fluting and a muzzle crown.
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.030),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.024), 0.0112, 16)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.140),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.134), 0.0104, 16)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.070),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.064), 0.0100, 16)
            # Six flats milled along the length, in two bands.
            for index in range(6):
                angle = TAU * index / 6.0
                radial = (math.cos(angle), math.sin(angle), 0.0)
                for band in range(3):
                    extrude(barrel, profile_rounded_rect(0.0024, 0.0074, 0.0012, 2), 0.0, 0.0016,
                            origin=(0.0092 * radial[0], spec["bore_y"] + 0.0092 * radial[1],
                                    z_muzzle_back - 0.118 + band * 0.036),
                            u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=radial)
            # Bore down the whole extension and the crown at its muzzle.
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.140),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.136), 0.0086, 16, cap_start=False)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.136),
                 (0.0, spec["bore_y"], z_muzzle_back + 0.010), 0.0052, 14,
                 cap_start=False, cap_end=False)
            # Muzzle-thread relief where a device would screw on.
            for index in range(6):
                angle = TAU * index / 6.0
                box(barrel, (0.0092 * math.cos(angle), spec["bore_y"] + 0.0092 * math.sin(angle),
                             z_muzzle_back - 0.028 + index * 0.0), (0.0024, 0.0024, 0.0120))
        else:
            # A compensator or brake still fits a barrel; model the stub it
            # screws onto, with its thread relief, shoulder and a bore.
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.020),
                 (0.0, spec["bore_y"], z_muzzle_back + 0.014), 0.0102, 16, steps=3)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.020),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.014), 0.0114, 16)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.008),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.004), 0.0108, 16)
            tube(barrel, (0.0, spec["bore_y"], z_muzzle_back - 0.020),
                 (0.0, spec["bore_y"], z_muzzle_back + 0.014), 0.0052, 14,
                 cap_start=False, cap_end=False)
            # Machined thread reliefs around the stub.
            for index in range(7):
                angle = TAU * index / 7.0
                box(barrel, (0.0102 * math.cos(angle), spec["bore_y"] + 0.0102 * math.sin(angle),
                             z_muzzle_back - 0.002), (0.0024, 0.0024, 0.0210))
        parts = [(prefix + "barrel", "ds_wsteel", barrel)]
        device = Builder()
        if kind == "suppressor":
            # Suppressor: tube, knurled mount collar with its clamp screws, end
            # cap, ring grooves and the full baffle stack in the bore.
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.180),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.010), 0.0205, 20, steps=4)
            _knurl(device, (0.0, spec["bore_y"], z_muzzle_back - 0.026), (0.0, 0.0, 1.0), 0.0205, 0.0100, 16)
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.014),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.008), 0.0225, 20)
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.186),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.178), 0.0218, 20)
            # Longitudinal ring grooves down the tube, and its machined seam.
            for index in range(7):
                along = z_muzzle_back - 0.040 - index * 0.021
                tube(device, (0.0, spec["bore_y"], along - 0.0016),
                     (0.0, spec["bore_y"], along + 0.0016), 0.0212, 20)
            # Six flutes milled down the tube's flanks, each with its own lip.
            for index in range(6):
                angle = TAU * index / 6.0
                radial = (math.cos(angle), math.sin(angle), 0.0)
                extrude(device, profile_rounded_rect(0.0026, 0.0540, 0.0013, 2), 0.0206, 0.0230,
                        origin=(0.0, spec["bore_y"], z_muzzle_back - 0.100),
                        u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), w=radial)
            # Serial boss and the roll-pin that pins the core to the tube.
            rounded_box(device, (0.0, spec["bore_y"] + 0.0180, z_muzzle_back - 0.100),
                        (0.0140, 0.0060, 0.0400), 0.0024, 2)
            for index in range(3):
                box(device, (0.0, spec["bore_y"] + 0.0208, z_muzzle_back - 0.088 - index * 0.0110),
                    (0.0090, 0.0016, 0.0060))
            _pin(device, (-0.0200, spec["bore_y"], z_muzzle_back - 0.060),
                 (0.0200, spec["bore_y"], z_muzzle_back - 0.060), 0.0022, 0.0015)
            _pin(device, (-0.0200, spec["bore_y"], z_muzzle_back - 0.140),
                 (0.0200, spec["bore_y"], z_muzzle_back - 0.140), 0.0022, 0.0015)
            # Baffle stack: five baffles, each a ring with a conical face.
            for index in range(6):
                along = z_muzzle_back - 0.030 - index * 0.026
                tube(device, (0.0, spec["bore_y"], along - 0.006), (0.0, spec["bore_y"], along + 0.006),
                     0.0215, 18)
                # Each baffle's spacer ring and the port that vents it.
                tube(device, (0.0, spec["bore_y"], along + 0.006),
                     (0.0, spec["bore_y"], along + 0.010), 0.0196, 18, cap_start=False, cap_end=False)
                for side in (-1.0, 1.0):
                    extrude(device, profile_rounded_rect(0.0022, 0.0050, 0.0012, 2), 0.0175, 0.0206,
                            origin=(0.0, spec["bore_y"], along + 0.002), u=(1.0, 0.0, 0.0),
                            v=(0.0, 0.0, 1.0), w=(side, 0.0, 0.0))
                _screw_head(device, (0.0, spec["bore_y"] + 0.0208, along), (0.0, 1.0, 0.0),
                            0.0026, 0.0022, True)
            _baffle_stack(device, z_muzzle_back - 0.026, spec["bore_y"], 0.150, 5, 0.0172, 16)
            # Bore through the whole stack, and the mount collar's clamp screws.
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.180),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.012), 0.0090, 14, cap_start=False, cap_end=False)
            for index in range(6):
                angle = TAU * index / 6.0
                _screw_head(device, (0.0180 * math.cos(angle), spec["bore_y"] + 0.0180 * math.sin(angle),
                                     z_muzzle_back - 0.020), (0.0, 0.0, 1.0), 0.0026, 0.0022, True)
            # Crush washer between the collar and the barrel shoulder.
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.009),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.004), 0.0162, 16)
        else:
            # Compensator/brake: the port geometry is the device.
            _ported_brake(device, z_muzzle_back - 0.062, z_muzzle_back - 0.014, spec["bore_y"],
                          0.0134, 5, 4)
            # Crush washer at the shoulder of every screw-on device.
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.014),
                 (0.0, spec["bore_y"], z_muzzle_back - 0.009), 0.0146, 16)
            for index in range(8):
                angle = TAU * index / 8.0
                box(device, (0.0142 * math.cos(angle), spec["bore_y"] + 0.0142 * math.sin(angle),
                             z_muzzle_back - 0.0115), (0.0026, 0.0026, 0.0034))
            # Thread relief at the rear shoulder where it screws onto the barrel.
            tube(device, (0.0, spec["bore_y"], z_muzzle_back - 0.005),
                 (0.0, spec["bore_y"], z_muzzle_back), 0.0104, 16)
        parts.append((prefix + "device", "ds_wsteel", device))
        return parts

    if kind in ("extmag", "drum"):
        mag_len, mag_curve = spec["magazine"]
        length = mag_len * (1.45 if kind == "extmag" else 1.0)
        body = Builder()
        _magazine(body, z_centre, -receiver_h * 0.5 - 0.026, length, mag_curve,
                  receiver_w * 0.46, 0.030, "drum" if kind == "drum" else "box")
        mag_y = -receiver_h * 0.5 - 0.026
        if kind == "extmag":
            # An extended magazine is a coupled pair: the extra length is the
            # second body, so model the clamp, its screws and the spacer.
            rounded_box(body, (0.0, mag_y - mag_len * 0.72, z_centre + mag_curve * 0.5),
                        (receiver_w * 0.98, 0.016, 0.030), 0.0030, 2)
            for side in (-1.0, 1.0):
                _screw_head(body, (side * receiver_w * 0.50, mag_y - mag_len * 0.72,
                                   z_centre + mag_curve * 0.5), (side, 0.0, 0.0), 0.0028, 0.0024, True)
            _pin(body, (-receiver_w * 0.52, mag_y - mag_len * 0.40, z_centre + mag_curve * 0.25),
                 (receiver_w * 0.52, mag_y - mag_len * 0.40, z_centre + mag_curve * 0.25),
                 0.0024, 0.0016)
            _pin(body, (-receiver_w * 0.52, mag_y - mag_len * 1.10, z_centre + mag_curve * 0.80),
                 (receiver_w * 0.52, mag_y - mag_len * 1.10, z_centre + mag_curve * 0.80),
                 0.0024, 0.0016)
            # Coupling rails down both flanks joining the two bodies, with
            # their clamps and the round-count window between them.
            for side in (-1.0, 1.0):
                box(body, (side * (receiver_w * 0.47), mag_y - length * 0.62,
                           z_centre + mag_curve * 0.42), (0.0030, 0.0180, length * 0.90))
                for index in range(4):
                    _screw_head(body, (side * (receiver_w * 0.49), mag_y - length * 0.20 - index * 0.058,
                                       z_centre + mag_curve * 0.30), (side, 0.0, 0.0), 0.0026, 0.0022, True)
                for index in range(5):
                    box(body, (side * (receiver_w * 0.50), mag_y - length * 0.14 - index * 0.058,
                               z_centre + mag_curve * 0.26), (0.0024, 0.0100, 0.0140))
            # Extended floorplate with its pull tab and witness markings.
            rounded_box(body, (0.0, mag_y - length - 0.014, z_centre + mag_curve),
                        (receiver_w * 0.94, 0.010, 0.032), 0.0028, 2)
            for index in range(3):
                box(body, (0.0, mag_y - length - 0.020, z_centre + mag_curve - 0.008 + index * 0.008),
                    (receiver_w * 0.72, 0.0018, 0.0050))
            extrude(body, profile_rounded_rect(receiver_w * 0.34, 0.0034, 0.0018, 2), 0.0, 0.0080,
                    origin=(0.0, mag_y - length - 0.020, z_centre + mag_curve),
                    u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), w=(0.0, -1.0, 0.0))
            # Witness holes down the whole coupled length, one per round, with
            # the spine ribs and the round-count numerals beside them.
            rounds = 18
            for side in (-1.0, 1.0):
                for index in range(rounds):
                    t = (index + 0.5) / rounds
                    _mlok_slot(body, (side * (receiver_w * 0.47 + 0.0006),
                                      mag_y - length * t, z_centre + mag_curve * (t ** 2)),
                               (side, 0.0, 0.0))
                for index in range(rounds - 1):
                    t = (index + 1.0) / rounds
                    box(body, (side * (receiver_w * 0.50), mag_y - length * t,
                               z_centre + mag_curve * (t ** 2)), (0.0018, 0.0040, 0.0074))
            for index in range(rounds):
                t = (index + 0.5) / rounds
                box(body, (0.0, mag_y - length * t,
                           z_centre + mag_curve * (t ** 2) + receiver_w * 0.47 + 0.0014),
                    (receiver_w * 0.72, 0.0052, 0.0022))
            # Follower and feed lips at the top of the coupled pair.
            for side in (-1.0, 1.0):
                _screw_head(body, (side * receiver_w * 0.50, mag_y - 0.004,
                                   z_centre + 0.002), (side, 0.0, 0.0), 0.0026, 0.0022, True)
            _pin(body, (-receiver_w * 0.52, mag_y - 0.006, z_centre + 0.004),
                 (receiver_w * 0.52, mag_y - 0.006, z_centre + 0.004), 0.0022, 0.0015)
        else:
            # Drum: the drum face carries its own plate, wind-up key, bolts and
            # the spring housing; the tower is the box magazine feeding it.
            drum_centre = (0.0, mag_y - mag_len * 0.62, z_centre + mag_curve * 0.40)
            tube(body, drum_centre, vadd(drum_centre, (0.0, 0.0, 0.0840)), 0.0740, 22, steps=3)
            for side in (-1.0, 1.0):
                tube(body, vadd(drum_centre, (0.0, 0.0, side * 0.0780)),
                     vadd(drum_centre, (0.0, 0.0, side * 0.0860)), 0.0700, 22)
                # Face plate, its concentric rim and the sixteen bolt circle.
                tube(body, vadd(drum_centre, (0.0, 0.0, side * 0.0860)),
                     vadd(drum_centre, (0.0, 0.0, side * 0.0900)), 0.0560, 22)
                for index in range(16):
                    angle = TAU * index / 16.0
                    radial = (math.cos(angle), math.sin(angle), 0.0)
                    point = vadd(drum_centre, vadd(vmul(radial, 0.0600), (0.0, 0.0, side * 0.0902)))
                    if index % 2 == 0:
                        _hex_bolt(body, point, (0.0, 0.0, side), 0.0030, 0.0044)
                    else:
                        _screw_head(body, point, (0.0, 0.0, side), 0.0028, 0.0024, True)
                    # Radial ribs stiffening each drum face.
                    extrude(body, profile_rounded_rect(0.0028, 0.0140, 0.0013, 2), 0.0, 0.0055,
                            origin=vadd(drum_centre, vadd(vmul(radial, 0.0710),
                                                         (0.0, 0.0, side * 0.0862))),
                            u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), w=(radial[0], radial[1], 0.0))
                _knurl(body, vadd(drum_centre, (0.0, 0.0, side * 0.0840)), (0.0, 0.0, side),
                       0.0700, 0.0050, 22)
            # Wind-up key, its spindle and the release catch on the tower.
            tube(body, vadd(drum_centre, (0.0, 0.0, 0.0860)), vadd(drum_centre, (0.0, 0.0, 0.0940)),
                 0.0120, 12)
            _knurl(body, vadd(drum_centre, (0.0, 0.0, 0.0900)), (0.0, 0.0, 1.0), 0.0120, 0.0060, 10)
            for index in range(3):
                angle = TAU * index / 3.0
                extrude(body, profile_rounded_rect(0.0026, 0.0050, 0.0012, 2), 0.0, 0.0160,
                        origin=vadd(drum_centre, (0.0160 * math.cos(angle), 0.0160 * math.sin(angle), 0.0880)),
                        u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0))
            _latch(body, (0.0, mag_y - mag_len * 0.18, z_centre + mag_curve * 0.10),
                   (0.0, 0.0, -1.0), 0.026, 0.012, 0.007)
            for side in (-1.0, 1.0):
                _screw_head(body, (side * receiver_w * 0.50, mag_y - mag_len * 0.24,
                                   z_centre + mag_curve * 0.14), (side, 0.0, 0.0), 0.0028, 0.0024, True)
            # Tower ribs: the feed column joining the drum to the receiver.
            for side in (-1.0, 1.0):
                for index in range(6):
                    box(body, (side * (receiver_w * 0.48), mag_y - 0.014 - index * 0.020,
                               z_centre + mag_curve * 0.04), (0.0024, 0.0074, 0.0056))
                _mlok_slot(body, (side * (receiver_w * 0.47 + 0.0006), mag_y - mag_len * 0.30,
                                  z_centre + mag_curve * 0.16), (side, 0.0, 0.0))
            for index in range(6):
                box(body, (0.0, mag_y - 0.014 - index * 0.020,
                           z_centre + mag_curve * 0.04 + receiver_w * 0.47 + 0.0014),
                    (receiver_w * 0.72, 0.0052, 0.0022))
        return [(prefix + "magazine", "ds_wpolymer", body)]

    if kind in ("foregrip", "angledgrip"):
        grip = Builder()
        base_y = -receiver_h * 0.5 - spec["handguard"][2] - 0.004
        z_grip = -receiver_len * 0.5 - spec["handguard"][0] * 0.45
        rake = 0.06 if kind == "foregrip" else 0.62
        length = 0.088 if kind == "foregrip" else 0.082
        half_w = 0.014
        _pistol_grip(grip, z_grip, base_y, rake, length, half_w)
        # Mounting clamp: the rail interface at the top of the grip, with two
        # clamp screws, its throw lever and a recoil lug.
        _rail_clamp(grip, z_grip, base_y + 0.006, 0.024, True, 2)
        # Rear-strap and side stippling on the grip proper, plus a QD socket
        # and the finger-groove pair a vertical foregrip carries.
        for side in (-1.0, 1.0):
            _stipple_panel(grip, (side * (half_w + 0.0012),
                                  base_y - length * 0.55, z_grip + rake * length * 0.55),
                           (0.0, -1.0, rake), (0.0, 0.0, 1.0),
                           length * 0.34, 0.0095, 0.0034, 0.0009)
        _stipple_panel(grip, (0.0, base_y - length * 0.55, z_grip + rake * length * 0.55 + half_w * 1.05),
                       (0.0, -1.0, rake), (1.0, 0.0, 0.0), length * 0.34, 0.0095, 0.0034, 0.0009)
        for index in range(2):
            t = 0.30 + index * 0.30
            centre = (0.0, base_y - length * t, z_grip + rake * length * t + half_w * 0.62)
            tube(grip, centre, vadd(centre, (half_w * 2.02, 0.0, 0.0)), 0.0040, 10)
        _sling_loop(grip, (0.0, base_y - length - 0.004, z_grip + rake * length), (1.0, 0.0, 0.0), 0.0052)
        # Base plug and its retaining screws.
        rounded_box(grip, (0.0, base_y - length - 0.0035, z_grip + rake * length),
                    (half_w * 2.16, 0.0075, 0.0210), 0.0022, 2)
        for sign in (-1.0, 1.0):
            _screw_head(grip, (sign * half_w * 0.68, base_y - length - 0.0080,
                               z_grip + rake * length), (0.0, -1.0, 0.0), 0.0024, 0.0020, True)
        _pin(grip, (-half_w * 1.05, base_y - length * 0.48, z_grip + rake * length * 0.48),
             (half_w * 1.05, base_y - length * 0.48, z_grip + rake * length * 0.48), 0.0022, 0.0015)
        return [(prefix + "grip", "ds_wpolymer", grip)]

    if kind == "heavystock":
        stock = Builder()
        _buffer_tube_and_stock(stock, receiver_len * 0.5 - 0.006, spec["bore_y"] + 0.006,
                               spec["stock_len"] * 1.02, "fixed")
        _end_plate(stock, receiver_len * 0.5 - 0.004, spec["bore_y"] + 0.006, receiver_w * 0.5, True)
        # The heavy stock's extra mass is a weighted cheek block and a recoil
        # pad bolted to the butt, plus its own sling swivel.
        body_z = receiver_len * 0.5 - 0.006 + spec["stock_len"] * 1.02 * 0.52
        y_centre = spec["bore_y"] + 0.006
        rounded_box(stock, (0.0, y_centre + 0.0480, body_z), (0.030, 0.018, spec["stock_len"] * 0.44),
                    0.0040, 3)
        for sign in (-1.0, 1.0):
            _screw_head(stock, (0.0, y_centre + 0.0565, body_z + sign * spec["stock_len"] * 0.16),
                        (0.0, 1.0, 0.0), 0.0028, 0.0024, True)
        # Cheek block stippling and its adjustment rails.
        _stipple_panel(stock, (0.0, y_centre + 0.0570, body_z), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                       spec["stock_len"] * 0.20, 0.0130, 0.0034, 0.0009)
        for side in (-1.0, 1.0):
            for offset in (-0.012, 0.012):
                box(stock, (side * 0.0300, y_centre + 0.020, body_z + offset),
                    (0.0018, 0.0480, 0.0060))
        rounded_box(stock, (0.0, y_centre - 0.020, body_z + spec["stock_len"] * 0.50),
                    (0.052, 0.100, 0.020), 0.0060, 3)
        for sign in (-1.0, 1.0):
            box(stock, (0.0, y_centre - 0.020 + sign * 0.034, body_z + spec["stock_len"] * 0.44),
                (0.040, 0.0040, 0.0140))
        for sign in (-1.0, 1.0):
            _screw_head(stock, (sign * 0.0200, y_centre - 0.020, body_z + spec["stock_len"] * 0.53),
                        (0.0, 0.0, 1.0), 0.0030, 0.0026)
        # Recoil-pad ribs and the buttplate's two adjustment screws.
        for index in range(4):
            box(stock, (0.0, y_centre - 0.020, body_z + spec["stock_len"] * 0.56 - index * 0.0060),
                (0.0460, 0.0900, 0.0022))
        for sign in (-1.0, 1.0):
            _hex_bolt(stock, (sign * 0.0230, y_centre - 0.062, body_z + spec["stock_len"] * 0.50),
                      (0.0, -1.0, 0.0), 0.0030, 0.0042)
        # Weighted body: the extra mass is a solid billet under the comb, held
        # by a row of bolts, with its own drain holes and a second sling loop.
        billet_len = 0.150
        for side in (-1.0, 1.0):
            rounded_box(stock, (side * 0.0160, y_centre + 0.010, body_z - spec["stock_len"] * 0.10),
                        (0.0160, 0.0380, billet_len), 0.0034, 3)
            for index in range(4):
                _hex_bolt(stock, (side * 0.0230, y_centre + 0.010,
                                  body_z - spec["stock_len"] * 0.10 - billet_len * 0.34
                                  + index * billet_len * 0.22),
                          (side, 0.0, 0.0), 0.0030, 0.0042)
            for index in range(5):
                _mlok_slot(stock, (side * 0.0238, y_centre - 0.006,
                                   body_z - spec["stock_len"] * 0.10 + billet_len * 0.36
                                   - index * billet_len * 0.18),
                           (side, 0.0, 0.0))
        # Second sling loop, rooted on the stock body's underside so it hangs
        # off the stock rather than floating beside it: the body's bottom face is
        # at y_centre-0.035, and the loop's ring is centred 6 mm below that.
        _sling_loop(stock, (0.0, y_centre - 0.041, body_z - spec["stock_len"] * 0.42),
                    (1.0, 0.0, 0.0), 0.0058)
        for side in (-1.0, 1.0):
            _screw_head(stock, (side * 0.0210, y_centre - 0.036,
                                body_z - spec["stock_len"] * 0.42), (side, 0.0, 0.0), 0.0026, 0.0022, True)
        _pin(stock, (-0.0170, y_centre - 0.052, body_z + spec["stock_len"] * 0.30),
             (0.0170, y_centre - 0.052, body_z + spec["stock_len"] * 0.30), 0.0026, 0.0018)
        # Swivel on the comb, rooted on the body's underside like the one above.
        _sling_loop(stock, (0.0, y_centre - 0.041, body_z + spec["stock_len"] * 0.20),
                    (1.0, 0.0, 0.0), 0.0062)
        # Panel lines separating the comb from the body and the butt.
        for sign in (-1.0, 1.0):
            box(stock, (0.0, y_centre - 0.004, body_z + sign * spec["stock_len"] * 0.35),
                (0.0480, 0.0700, 0.0022))
        return [(prefix + "stock", "ds_wpolymer", stock)]

    if kind == "laser":
        body = Builder()
        z_laser = -receiver_len * 0.5 - spec["handguard"][0] * 0.70
        y_laser = -receiver_h * 0.5 - spec["handguard"][2] - 0.006
        # Housing: the main body, its lower battery tube and the front ring.
        rounded_box(body, (0.0, y_laser, z_laser), (0.022, 0.020, 0.056), 0.005)
        tube(body, (0.0, y_laser - 0.0130, z_laser), (0.0, y_laser - 0.0130, z_laser + 0.030),
             0.0098, 14, steps=2)
        for index in range(5):
            box(body, (0.0, y_laser + 0.0104, z_laser - 0.020 + index * 0.010),
                (0.0170, 0.0018, 0.0050))
        for side in (-1.0, 1.0):
            for sign in (-1.0, 1.0):
                _screw_head(body, (side * 0.0112, y_laser + sign * 0.0072, z_laser + 0.022),
                            (side, 0.0, 0.0), 0.0026, 0.0022, True)
        tube(body, (0.0, y_laser, z_laser - 0.028), (0.0, y_laser, z_laser - 0.036), 0.0085, 14)
        rounded_box(body, (0.0, y_laser - 0.004, z_laser + 0.020), (0.014, 0.010, 0.014), 0.002)
        # Body: battery cap, mode dial, windage/elevation screws, mount clamp
        # and a rubber switch pad on a short cable, which is what a laser
        # module actually looks like once it is fitted.
        tube(body, (0.0, y_laser, z_laser + 0.028), (0.0, y_laser, z_laser + 0.034), 0.0092, 14)
        _knurl(body, (0.0, y_laser, z_laser + 0.032), (0.0, 0.0, 1.0), 0.0092, 0.0060, 12)
        tube(body, (0.0120, y_laser, z_laser + 0.014), (0.0175, y_laser, z_laser + 0.014), 0.0058, 12)
        _knurl(body, (0.0172, y_laser, z_laser + 0.014), (1.0, 0.0, 0.0), 0.0058, 0.0044, 10)
        _graduations(body, (0.0150, y_laser, z_laser + 0.014), (1.0, 0.0, 0.0), 0.0058, 7, 2.6)
        for axis, centre in (((0.0, 1.0, 0.0), (0.0, y_laser + 0.0115, z_laser - 0.008)),
                             ((1.0, 0.0, 0.0), (0.0115, y_laser, z_laser - 0.008))):
            _turret(body, centre, axis, 0.0058, 0.0080, 7)
        # Rail clamp, shared with every other accessory.
        _rail_clamp(body, z_laser + 0.004, y_laser + 0.0145, 0.022, True, 2)
        # Body flanks: lightening grooves and a stippled activation zone.
        for side in (-1.0, 1.0):
            for index in range(4):
                box(body, (side * 0.0114, y_laser, z_laser - 0.018 + index * 0.012),
                    (0.0016, 0.0140, 0.0050))
            _stipple_panel(body, (side * 0.0116, y_laser - 0.006, z_laser + 0.006),
                           (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.0105, 0.0042, 0.0032, 0.0009)
            # Housing ribs top and bottom, and the side rails a laser clamps on.
            for index in range(3):
                box(body, (side * 0.0118, y_laser + 0.0110, z_laser - 0.012 + index * 0.014),
                    (0.0020, 0.0020, 0.0090))
        # Front aperture: the bezel ring, its inner shoulder and retaining screws.
        tube(body, (0.0, y_laser, z_laser - 0.036), (0.0, y_laser, z_laser - 0.040), 0.0102, 14)
        tube(body, (0.0, y_laser, z_laser - 0.036), (0.0, y_laser, z_laser - 0.0392), 0.0076, 14)
        for index in range(4):
            angle = TAU * (index + 0.5) / 4.0
            _screw_head(body, (0.0102 * math.cos(angle), y_laser + 0.0102 * math.sin(angle),
                               z_laser - 0.037), (0.0, 0.0, -1.0), 0.0022, 0.0020)
        # Windage/elevation detent bosses and the housing's index marks.
        for sign in (-1.0, 1.0):
            _hex_bolt(body, (0.0, y_laser + 0.0104, z_laser - 0.004 + sign * 0.020),
                      (0.0, 1.0, 0.0), 0.0024, 0.0034)
        _graduations(body, (0.0, y_laser, z_laser + 0.026), (0.0, 0.0, 1.0), 0.0106, 9, 2.8)
        # Switch pad on a cable running from the rear of the body.
        rounded_box(body, (0.0075, y_laser + 0.001, z_laser + 0.042), (0.020, 0.010, 0.018), 0.0030, 2)
        for index in range(6):
            box(body, (0.0075, y_laser + 0.001, z_laser + 0.033 + index * 0.0036),
                (0.0170, 0.0070, 0.0016))
        # Pad texture: a moulded pip field on the rubber switch itself.
        _stipple_panel(body, (0.0075, y_laser + 0.0062, z_laser + 0.042),
                       (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), 0.0090, 0.0040, 0.0030, 0.0008)
        # Housing ribs across the top deck and the underside cable channel.
        for index in range(5):
            box(body, (0.0, y_laser + 0.0106, z_laser - 0.022 + index * 0.011),
                (0.0196, 0.0022, 0.0040))
            box(body, (0.0, y_laser - 0.0106, z_laser - 0.020 + index * 0.011),
                (0.0196, 0.0022, 0.0040))
        for index in range(3):
            _screw_head(body, (0.0, y_laser - 0.0106, z_laser - 0.024 + index * 0.024),
                        (0.0, -1.0, 0.0), 0.0024, 0.0020, True)
        # Rear cap: its index collar, battery spring boss and the lanyard eye.
        tube(body, (0.0, y_laser, z_laser + 0.034), (0.0, y_laser, z_laser + 0.038), 0.0086, 14)
        tube(body, (0.0, y_laser, z_laser + 0.038), (0.0, y_laser, z_laser + 0.040), 0.0052, 12)
        _screw_head(body, (0.0, y_laser, z_laser + 0.0405), (0.0, 0.0, 1.0), 0.0030, 0.0024, True)
        _sling_loop(body, (0.0, y_laser - 0.0100, z_laser + 0.040), (1.0, 0.0, 0.0), 0.0044)
        _pin(body, (-0.0112, y_laser - 0.0130, z_laser + 0.012),
             (0.0112, y_laser - 0.0130, z_laser + 0.012), 0.0022, 0.0015)
        cable = [(0.0, y_laser, z_laser + 0.034), (0.0045, y_laser + 0.002, z_laser + 0.044),
                 (0.0075, y_laser, z_laser + 0.034)]
        swept_tube(body, cable, 0.0018, 6)
        _pin(body, (-0.0100, y_laser, z_laser + 0.030), (0.0100, y_laser, z_laser + 0.030),
             0.0022, 0.0015)
        emitter = Builder()
        tube(emitter, (0.0, y_laser, z_laser - 0.036), (0.0, y_laser, z_laser - 0.039), 0.0072, 12)
        tube(emitter, (0.0, y_laser, z_laser - 0.036), (0.0, y_laser, z_laser - 0.0335), 0.0090, 14)
        # Emitter housing: its collar, the aperture's inner shoulder and the
        # adjustment detents, so the aperture is a mechanism and not a hole.
        tube(emitter, (0.0, y_laser, z_laser - 0.0335), (0.0, y_laser, z_laser - 0.030), 0.0104, 14)
        tube(emitter, (0.0, y_laser, z_laser - 0.039), (0.0, y_laser, z_laser - 0.0415), 0.0106, 14)
        tube(emitter, (0.0, y_laser, z_laser - 0.0415), (0.0, y_laser, z_laser - 0.0425), 0.0068, 12)
        for index in range(4):
            angle = TAU * (index + 0.5) / 4.0
            _hex_bolt(emitter, (0.0110 * math.cos(angle), y_laser + 0.0110 * math.sin(angle),
                                z_laser - 0.0375), (0.0, 0.0, -1.0), 0.0024, 0.0034)
            _screw_head(emitter, (0.0086 * math.cos(angle), y_laser + 0.0086 * math.sin(angle),
                                  z_laser - 0.0325), (0.0, 0.0, 1.0), 0.0022, 0.0020, True)
        _screw_head(emitter, (0.0, y_laser + 0.0072, z_laser - 0.0345), (0.0, 1.0, 0.0), 0.0022, 0.0020)
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
    # (y offset from the pivot, half-thickness, spine height) from tip to ricasso.
    stations = [
        (0.235, 0.0006, 0.0000),
        (0.212, 0.0009, 0.0034),
        (0.190, 0.0012, 0.0060),
        (0.160, 0.0015, 0.0088),
        (0.130, 0.0018, 0.0110),
        (0.100, 0.0020, 0.0122),
        (0.070, 0.0022, 0.0130),
        (0.020, 0.0024, 0.0126),
        (0.000, 0.0024, 0.0110),
    ]
    # The cutting edge sweeps back from the tip toward the ricasso, and the
    # primary bevel is a narrow band inboard of it, which is what reads as a
    # ground blade rather than a flat plate.
    edge_offsets = [0.0, -0.020, -0.050, -0.043, -0.036, -0.030, -0.026, -0.014, -0.004]
    swedge_scale = [0.0, 0.55, 0.80, 0.92, 1.0, 1.0, 1.0, 0.96, 0.90]
    for index in range(len(stations) - 1):
        y0, half0, spine0 = stations[index]
        y1, half1, spine1 = stations[index + 1]
        e0 = edge_offsets[index]
        e1 = edge_offsets[index + 1]
        top0 = e0 + spine0 * swedge_scale[index]
        top1 = e1 + spine1 * swedge_scale[index + 1]
        bevel0 = e0 + (top0 - e0) * 0.30
        bevel1 = e1 + (top1 - e1) * 0.30
        for side in (-1.0, 1.0):
            # Five rails across the blade: spine, upper flat, fuller wall, lower
            # flat, edge bevel. The fuller is the recessed wall between the two
            # flats and is what gives the blade a highlight down its middle.
            spine_a = (side * half0 * 0.30, y0, top0)
            spine_b = (side * half1 * 0.30, y1, top1)
            flat_a = (side * half0, y0, e0 + (top0 - e0) * 0.62)
            flat_b = (side * half1, y1, e1 + (top1 - e1) * 0.62)
            wall_a = (side * half0 * 0.62, y0, e0 + (top0 - e0) * 0.58)
            wall_b = (side * half1 * 0.62, y1, e1 + (top1 - e1) * 0.58)
            root_a = (side * half0, y0, bevel0)
            root_b = (side * half1, y1, bevel1)
            edge_a = (side * half0 * 0.10, y0, e0)
            edge_b = (side * half1 * 0.10, y1, e1)
            if side > 0:
                blade.quad(spine_a, flat_a, flat_b, spine_b)
                blade.quad(flat_a, wall_a, wall_b, flat_b)
                blade.quad(wall_a, root_a, root_b, wall_b)
                blade.quad(root_a, edge_a, edge_b, root_b)
            else:
                blade.quad(spine_b, flat_b, flat_a, spine_a)
                blade.quad(flat_b, wall_b, wall_a, flat_a)
                blade.quad(wall_b, root_b, root_a, wall_a)
                blade.quad(root_b, edge_b, edge_a, root_a)
        # Spine and edge sheets close the solid.
        if index == 0:
            blade.quad((stations[0][1] * 0.30, y0, top0),
                       (-stations[0][1] * 0.30, y0, top0),
                       (-stations[0][1] * 0.10, y0, e0),
                       (stations[0][1] * 0.10, y0, e0))
    # The fuller is the recessed wall between the upper flat and the edge bevel:
    # the cross-section steps out to full thickness at `flat`, back in to 0.62 of
    # it at `wall`, then out again at `root`, which leaves a machined channel
    # down each flat that catches a long highlight, exactly as a ground fuller
    # does. It is part of the section, so it needs no separate geometry.
    # Blade decorations. The section's z-extent is *not* a spine height: the
    # stations carry an edge offset (`e`) plus a `spine` value that is a
    # fraction of the blade's height above the edge, and on this blade the whole
    # section lives essentially between z=0 (edge) and z=0.005 (spine) in the
    # middle third. Decorations placed against a literal "spine height" therefore
    # floated 12 mm clear of the steel, so they are all placed against a section
    # interpolated from the same stations the blade is built from.
    def section(y):
        """(half thickness, edge z, spine z, flat z) at a distance `y` from the tip."""
        ys = [s[0] for s in stations]
        if y >= ys[0]:
            i = 0; t = 0.0
        elif y <= ys[-1]:
            i = len(stations) - 2; t = 1.0
        else:
            i = max(j for j in range(len(stations) - 1) if y <= ys[j])
            t = (ys[i] - y) / (ys[i] - ys[i + 1])
        y0, h0, s0 = stations[i]; y1, h1, s1 = stations[i + 1]
        h = h0 + (h1 - h0) * t
        e = edge_offsets[i] + (edge_offsets[i + 1] - edge_offsets[i]) * t
        sc = swedge_scale[i] + (swedge_scale[i + 1] - swedge_scale[i]) * t
        top = e + (s0 + (s1 - s0) * t) * sc
        return h, e, top, e + (top - e) * 0.62

    # Jimping: thumb notches cut into the spine above the ricasso. Each notch is
    # centred on the spine's material and sunk well past the blade's thickness,
    # so it bites both rails of the spine.
    for index in range(16):
        y = 0.012 + index * 0.0068
        _h, _e, top, _f = section(y)
        box(blade, (0.0, y, top - 0.0020), (0.0052, 0.0030, 0.0070))
    # Choil notch and the plunge line at the ricasso, on the blade's flank.
    h0, e0, top0, flat0 = section(0.004)
    rounded_box(blade, (0.0, 0.004, e0 + (top0 - e0) * 0.45), (0.0040, 0.0090, 0.0040), 0.0014, 2)
    h1, e1, top1, flat1 = section(0.010)
    box(blade, (0.0, 0.010, top1), (0.0056, 0.0018, 0.0022))
    # Laser-etched maker mark on both flats, sitting on the ground surface.
    h2, e2, top2, flat2 = section(0.062)
    for side in (-1.0, 1.0):
        box(blade, (side * (h2 * 0.90), 0.062, flat2), (0.0016, 0.0180, 0.0018))
    parts = [(prefix + "blade", "ds_wbright", blade)]

    guard = Builder()
    rounded_box(guard, (0.0, 0.020, -0.006), (0.014, 0.020, 0.016), 0.004)
    box(guard, (0.0, -0.006, 0.000), (0.008, 0.030, 0.010))
    # Lower guard lobe and the finger ring behind it.
    rounded_box(guard, (0.0, -0.014, -0.002), (0.011, 0.016, 0.014), 0.0034, 2)
    ring_y = -0.030
    ring_z = -0.004
    points = [(0.0, ring_y + 0.0034 * math.cos(TAU * i / 14.0), ring_z + 0.0050 * math.sin(TAU * i / 14.0))
              for i in range(14)]
    points.append(points[0])
    swept_tube(guard, points, 0.0030, 8)
    # Guard screws through the tang and the blade's own retaining pin.
    for sign in (-1.0, 1.0):
        _screw_head(guard, (sign * 0.0074, 0.014, -0.006), (sign, 0.0, 0.0), 0.0026, 0.0022, True)
        _screw_head(guard, (sign * 0.0074, 0.002, -0.004), (sign, 0.0, 0.0), 0.0024, 0.0020, True)
    _pin(guard, (-0.0064, 0.019, -0.0015), (0.0064, 0.019, -0.0015), 0.0020, 0.0014)
    box(guard, (0.0, 0.020, -0.0045), (0.0150, 0.0050, 0.0026))
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
    # Scales: a separate moulded plate on each flank with a raised rim, its own
    # panel line and a stippled grip field.
    for side in (-1.0, 1.0):
        rounded_box(handle, (side * 0.0128, 0.0, -0.092), (0.0044, 0.0320, 0.1120), 0.0038, 3)
        box(handle, (side * 0.0150, 0.0, -0.092), (0.0020, 0.0340, 0.1160))
        for row in range(12):
            z = -0.044 - row * 0.0086
            for column in range(4):
                y = (column - 1.5) * 0.0076
                box(handle, (side * 0.0154, y, z), (0.0018, 0.0044, 0.0044))
        # Scale retaining screws at the top and bottom of each plate.
        for offset in (-0.040, -0.144):
            _screw_head(handle, (side * 0.0152, 0.0, offset), (side, 0.0, 0.0), 0.0026, 0.0022, True)
    # Three rivets through the tang, proud on both sides.
    for z in (-0.052, -0.094, -0.136):
        _pin(handle, (-0.0160, 0.0, z), (0.0160, 0.0, z), 0.0032, 0.0020)
        for side in (-1.0, 1.0):
            tube(handle, (side * 0.0156, 0.0, z), (side * 0.0174, 0.0, z), 0.0044, 12)
            _knurl(handle, (side * 0.0172, 0.0, z), (side, 0.0, 0.0), 0.0044, 0.0028, 8)
    # Lanyard hole through the butt of the tang, with its steel liner.
    _pin(handle, (-0.0140, 0.0, -0.152), (0.0140, 0.0, -0.152), 0.0030, 0.0018)
    for side in (-1.0, 1.0):
        tube(handle, (side * 0.0136, 0.0, -0.152), (side * 0.0152, 0.0, -0.152), 0.0042, 12)
    parts.append((prefix + "handle", "ds_wpolymer", handle))

    pommel = Builder()
    rounded_box(pommel, (0.0, 0.0, -0.166), (0.020, 0.026, 0.014), 0.004)
    # Pommel cap with a skull-crusher bevel, a lanyard loop and its two screws.
    rounded_box(pommel, (0.0, 0.0, -0.175), (0.022, 0.027, 0.009), 0.0034, 2)
    extrude(pommel, profile_rounded_rect(0.0044, 0.0052, 0.0018, 2), 0.0, 0.0080,
            origin=(0.0, 0.0, -0.180), u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, -1.0))
    loop = [(0.0, 0.0090, -0.180), (0.0, 0.0140, -0.188), (0.0, 0.0090, -0.196),
            (0.0, -0.0090, -0.196), (0.0, -0.0140, -0.188), (0.0, -0.0090, -0.180)]
    swept_tube(pommel, loop, 0.0022, 8, cap_start=False, cap_end=False)
    for sign in (-1.0, 1.0):
        _screw_head(pommel, (sign * 0.0076, 0.0, -0.171), (sign, 0.0, 0.0), 0.0026, 0.0022, True)
        _pin(pommel, (-0.0090, sign * 0.0105, -0.166), (0.0090, sign * 0.0105, -0.166), 0.0020, 0.0014)
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
