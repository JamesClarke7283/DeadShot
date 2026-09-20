"""High-detail soldier models for DeadShot.

The ported characters were 2728 triangles of boxes and spheres: a 40 cm cube for
a head, capsule limbs, no kit. This builds a properly proportioned 1.86 m
soldier: a sculpted torso, a plate carrier with plates, cummerbund, webbing and
pouches, a helmet with a mount shroud, side rails and chin strap routing, sealed
goggles, gloved hands with separated fingers, knee pads and laced boots with a
lugged sole.

The soldier faces +Z, which is the convention the exported source models and
`VisualFactory.animate_human` share: the shoot pose swings both arms forward
along +Z, so the plate carrier hangs off the front and the pack off the back.
The paired limbs are authored for the right side and mirrored for the left, so
outboard kit such as the shoulder patch and the thigh pocket lands outboard on
both sides.

Pivot contract is preserved exactly, because gameplay code animates it:

  hips        (0, 0.9, 0)        child of root
  head        (0, 0.88, 0)       child of hips
  face        (0, 0, 0)          child of head
  headband    (0, 0.04, 0)       child of face   - team-coloured helmet band
  left_arm    (-0.255, 0.5, 0)   child of hips
  right_arm   (0.255, 0.5, 0)    child of hips
  left_leg    (-0.13, 0, 0)      child of hips
  right_leg   (0.13, 0, 0)       child of hips

`VisualFactory.animate_human` rotates the four limb pivots about X and Z and
translates `hips` on Y, so each limb is one rigid group hanging from its pivot.
"""

from __future__ import annotations

import math

from deadshot_detail import (
    Builder, basis_from_w, box, cone, extrude, lerp3, profile_circle,
    profile_rounded_rect, rounded_box, slab, sweep, tube, vadd, vcross, vdot,
    vlen, vmul, vnorm, vsub,
)

TAU = math.tau
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
# Local geometry vocabulary. `deadshot_detail` supplies the profiles, sweeping
# and chamfered solids; these are the shapes a soldier needs on top of them: an
# elliptical stack (the DSL has no sphere), an analytic ring for rims, bands and
# eyelets, routed webbing, and the ridges that read as seams, folds and stitches.
# --------------------------------------------------------------------------

def _stacked(builder, stations, segments=24, cap_start=True, cap_end=True, smooth=True):
    """Elliptical rings with an optional rake, stacked along Y.

    `stations` entries are `(y, half_x, half_z)`, optionally extended with
    `z_offset`, `tilt` and `x_offset`. `tilt` rotates the ring's +Z axis up out
    of the ring plane, which is how a helmet's brow sits higher than its nape;
    `z_offset` rakes the ring forward or back; `x_offset` slides it sideways,
    which is what gives a limb an asymmetric section - a thigh's inner face is
    nearly flat where its outer face is round.

    Stations may run either way along Y, because a body part is naturally listed
    whatever way reads: the neck is upward and the hand downward. Each frame's
    `w` is therefore the direction of travel rather than `+Y`, since `sweep`
    normalises winding against `u x v` versus `w` and a frame whose `w`
    contradicts the travel direction inverts the whole stack.
    """
    centres = []
    axes = []
    for station in stations:
        y, half_x, half_z = station[0], station[1], station[2]
        offset = station[3] if len(station) > 3 else 0.0
        tilt = station[4] if len(station) > 4 else 0.0
        x_offset = station[5] if len(station) > 5 else 0.0
        centres.append((x_offset, y, offset))
        axes.append(((1.0, 0.0, 0.0), (0.0, math.sin(tilt), math.cos(tilt))))
    count = len(centres)
    if count < 2:
        return
    frames = []
    for index, (centre, (u, v)) in enumerate(zip(centres, axes)):
        if index == count - 1:
            w = vnorm(vsub(centres[index], centres[index - 1]))
        else:
            w = vnorm(vsub(centres[index + 1], centres[index]))
        frames.append((centre, vmul(u, stations[index][1]), vmul(v, stations[index][2]), w))
    profile = profile_circle(1.0, segments)
    normals = [(p[0], p[1], 0.0) for p in profile] if smooth else None
    sweep(builder, profile, frames, cap_start, cap_end, smooth_normals=normals)


def _ring(builder, centre, half_u, half_v, thickness, depth, segments=28,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8, corner_segments=2):
    """A closed band or tube around an ellipse in the plane spanned by `u`, `v`.

    `thickness` is the half-extent along the plane normal - a webbing band's
    width - and `depth` the half-extent radially, its thickness. Frames are
    analytic rather than derived from the tangent, so a flat band cannot twist
    where the tangent crosses `basis_from_w`'s reference axis.
    """
    u = vnorm(u)
    v = vnorm(v)
    normal = vnorm(vcross(u, v))
    if profile_segments and abs(thickness - depth) < 1e-9:
        profile = profile_circle(1.0, profile_segments)
    else:
        profile = profile_rounded_rect(1.0, 1.0, 0.30, corner_segments)
    frames = []
    for index in range(segments):
        angle = TAU * index / segments
        cosine, sine = math.cos(angle), math.sin(angle)
        origin = vadd(centre, vadd(vmul(u, half_u * cosine), vmul(v, half_v * sine)))
        tangent = vsub(vmul(v, half_v * cosine), vmul(u, half_u * sine))
        w = vnorm(tangent)
        radial = vnorm(vcross(w, normal))
        frames.append((origin, vmul(normal, thickness), vmul(radial, depth), w))
    frames.append(frames[0])
    sweep(builder, profile, frames, False, False)


def _rotated(point, axis, angle):
    cosine, sine = math.cos(angle), math.sin(angle)
    return vadd(vadd(vmul(point, cosine), vmul(vcross(axis, point), sine)),
                vmul(axis, vdot(axis, point) * (1.0 - cosine)))


def _path_frames(points, width_axis=None):
    """Twist-free frames along a polyline, parallel transported from the first."""
    frames = []
    previous = None
    count = len(points)
    for index, point in enumerate(points):
        if index == 0:
            tangent = vsub(points[1], points[0])
        elif index == count - 1:
            tangent = vsub(points[-1], points[-2])
        else:
            tangent = vsub(points[index + 1], points[index - 1])
        w = vnorm(tangent)
        if previous is None:
            projected = None
            if width_axis is not None:
                projected = vsub(width_axis, vmul(w, vdot(width_axis, w)))
            if projected is None or vlen(projected) < 1e-6:
                u, v, _ = basis_from_w(w)
            else:
                u = vnorm(projected)
                v = vcross(w, u)
        else:
            u, v = previous[0], previous[1]
            axis = vcross(previous[2], w)
            sine = vlen(axis)
            cosine = vdot(previous[2], w)
            if sine > 1e-9:
                axis = vmul(axis, 1.0 / sine)
                angle = math.atan2(sine, cosine)
                u = _rotated(u, axis, angle)
                v = _rotated(v, axis, angle)
        previous = (u, v, w)
        frames.append((point, u, v, w))
    return frames


def _route(builder, points, radius, segments=10, cap_start=True, cap_end=True):
    """Round cord or hose through a polyline: cables, tubes, bungees."""
    frames = _path_frames(points)
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(points)
    profile = profile_circle(1.0, segments)
    frames = [(frame[0], vmul(frame[1], r), vmul(frame[2], r), frame[3])
              for frame, r in zip(frames, radii)]
    sweep(builder, profile, frames, cap_start, cap_end,
          smooth_normals=[(p[0], p[1], 0.0) for p in profile])


def _strap(builder, points, half_width, half_thickness, width_axis=(1.0, 0.0, 0.0),
           corner_segments=2, cap_start=True, cap_end=True):
    """Flat webbing through a polyline: shoulder straps, chinstraps, laces."""
    frames = _path_frames(points, width_axis)
    widths = half_width if isinstance(half_width, (list, tuple)) else [half_width] * len(points)
    depths = half_thickness if isinstance(half_thickness, (list, tuple)) else [half_thickness] * len(points)
    frames = [(frame[0], vmul(frame[1], w), vmul(frame[2], d), frame[3])
              for frame, w, d in zip(frames, widths, depths)]
    sweep(builder, profile_rounded_rect(1.0, 1.0, 0.34, corner_segments), frames,
          cap_start, cap_end)


def _crease(builder, start, end, half_width, height, outward):
    """Cloth fold or raised seam: a thin triangular ridge from `start` to `end`."""
    axis = vsub(end, start)
    if vlen(axis) < 1e-6:
        return
    w = vnorm(axis)
    projected = vsub(outward, vmul(w, vdot(outward, w)))
    if vlen(projected) < 1e-6:
        return
    v = vnorm(projected)
    u = vcross(v, w)
    sweep(builder, [(-half_width, 0.0), (half_width, 0.0), (0.0, height)],
          [(start, u, v, w), (end, u, v, w)], True, True)


def _stitch(builder, start, end, count, half_width, height, outward, duty=0.55):
    """A run of short raised dashes, which is what stitching reads as."""
    for index in range(count):
        first = (index + (1.0 - duty) * 0.5) / count
        second = (index + (1.0 + duty) * 0.5) / count
        _crease(builder, lerp3(start, end, first), lerp3(start, end, second),
                half_width, height, outward)


def _bolt(builder, centre, axis, radius, height, segments=6):
    """Hex-head fastener standing proud of a surface."""
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    frames = [(centre, vmul(u, radius), vmul(v, radius), w),
              (vadd(centre, vmul(w, height)), vmul(u, radius * 0.92), vmul(v, radius * 0.92), w)]
    sweep(builder, profile_circle(1.0, segments), frames, True, True)


def _rivets(builder, centre, axis, spacing, count, radius, height):
    """A row of fasteners along an axis perpendicular to `axis`."""
    w = vnorm(axis)
    u, _, _ = basis_from_w(w)
    for index in range(count):
        offset = (index - (count - 1) * 0.5) * spacing
        _bolt(builder, vadd(centre, vmul(u, offset)), w, radius, height)


def _dome(builder, centre, half_u, half_v, depth, u, v, outward, steps=3,
          corner_segments=3, radius_scale=0.34):
    """A rounded plate or lens: a chamfered outline lofted as it shrinks.

    `depth` is how far the plate stands proud of `centre`, so it must be
    positive. A negative depth would loft the far cap back through the surface
    and expose it as a dark interior face, which is what a hollow looks like when
    it is built without boolean subtraction - so a hollow is modelled as the
    ridges around it instead.
    """
    axis = vnorm(outward)
    depth = abs(depth)
    u = vnorm(u)
    v = vnorm(v)
    profile = profile_rounded_rect(half_u, half_v, min(half_u, half_v) * radius_scale,
                                   corner_segments)
    frames = []
    for step in range(steps + 1):
        t = step / steps
        scale = math.sqrt(max(0.04, 1.0 - t * t * 0.92))
        frames.append((vadd(centre, vmul(axis, depth * t)), vmul(u, scale),
                       vmul(v, scale), axis))
    sweep(builder, profile, frames, True, True)


def _band_profile(half_u, half_v, thickness, start, end, segments):
    """Crescent profile spanning `start`..`end` radians of an ellipse.

    Curved shell panels - a helmet's nape skirt, a brow lip - are this profile
    extruded, which gives a wall of real thickness instead of a bent plane.
    """
    points = []
    for index in range(segments + 1):
        angle = start + (end - start) * index / segments
        points.append((half_u * math.cos(angle), half_v * math.sin(angle)))
    for index in range(segments, -1, -1):
        angle = start + (end - start) * index / segments
        points.append(((half_u - thickness) * math.cos(angle),
                       (half_v - thickness) * math.sin(angle)))
    return points


def _mirrored(builder):
    """Mirror a finished builder about x = 0, keeping winding and normals outward.

    The paired limbs share one authoring function, so the left side is the right
    side reflected rather than translated: without this, outboard kit would land
    against the torso on one arm and against the world on the other.
    """
    positions = builder.positions
    for index in range(len(positions)):
        x, y, z = positions[index]
        positions[index] = (-x, y, z)
    normals = builder.normals
    for index in range(len(normals)):
        x, y, z = normals[index]
        normals[index] = (-x, y, z)
    indices = builder.indices
    for index in range(0, len(indices), 3):
        indices[index + 1], indices[index + 2] = indices[index + 2], indices[index + 1]


def _sided(parts, side):
    """Reflect a part list built for the right-hand side onto the left."""
    if side > 0.0:
        return parts
    for _, _, builder in parts:
        _mirrored(builder)
    return parts


# --------------------------------------------------------------------------
# Torso. Built directly in hips-local space, so it needs no extra pivot. The
# chest is covered by the plate carrier, so the budget goes where the shirt is
# actually visible: the collar, the shoulder yoke, the waist and the seams.
# --------------------------------------------------------------------------

def build_torso():
    """Combat shirt: chest, waist, collar, yoke, seams and folds."""
    body = Builder()
    # Pelvis -> waist -> chest -> shoulders. Real soldiers taper at the waist and
    # widen at the shoulders, and the chest sits forward of the spine.
    stations = [
        (-0.030, 0.146, 0.094, 0.000),
        (0.020, 0.150, 0.098, 0.002),
        (0.070, 0.156, 0.103, 0.004),
        (0.120, 0.154, 0.100, 0.006),
        (0.170, 0.148, 0.096, 0.008),
        (0.230, 0.155, 0.102, 0.010),
        (0.290, 0.170, 0.110, 0.012),
        (0.350, 0.188, 0.118, 0.014),
        (0.410, 0.205, 0.126, 0.016),
        (0.470, 0.218, 0.131, 0.016),
        (0.520, 0.226, 0.132, 0.014),
        (0.570, 0.230, 0.128, 0.012),
        (0.610, 0.226, 0.122, 0.010),
        (0.640, 0.196, 0.110, 0.008),
        (0.660, 0.150, 0.092, 0.006),
    ]
    _stacked(body, stations, 24)
    # Trapezius shelf from the collar out onto each shoulder.
    for side in (-1.0, 1.0):
        _route(body, [(0.0, 0.636, 0.010), (side * 0.070, 0.630, 0.006),
                      (side * 0.140, 0.606, 0.000), (side * 0.196, 0.560, 0.000)],
               [0.062, 0.058, 0.052, 0.046], 14)
    # Collar stand, its rolled lip, and the neck inside it. The stand tops out at
    # hips-local 0.678 and the mandible's chin at world 1.63, so the collar closes
    # round the neck instead of riding up to the jaw.
    _stacked(body, [(0.600, 0.098, 0.088, 0.004), (0.640, 0.090, 0.082, 0.006),
                    (0.664, 0.086, 0.078, 0.006)], 20)
    _ring(body, (0.0, 0.666, 0.006), 0.086, 0.078, 0.007, 0.008, 26, profile_segments=8)
    tube(body, (0.0, 0.600, 0.006), (0.0, 0.700, 0.008), 0.060, 20, radius_end=0.056, steps=4)
    # Sleeve seam piping around each armhole, which is what separates the sleeve
    # from the shirt without a hard edge.
    for side in (-1.0, 1.0):
        _route(body, [(side * 0.150, 0.560, 0.086), (side * 0.205, 0.560, 0.020),
                      (side * 0.212, 0.548, -0.070), (side * 0.196, 0.500, -0.124),
                      (side * 0.150, 0.470, -0.140)], 0.006, 8)
    # Folds where the arms meet the torso, three per side, plus the tuck line
    # where the shirt goes under the belt.
    for side in (-1.0, 1.0):
        for index in range(3):
            y = 0.548 - index * 0.034
            _crease(body, (side * 0.126, y, 0.096 + index * 0.004),
                    (side * 0.212, y - 0.024, 0.048 + index * 0.004),
                    0.008, 0.006, (side * 0.6, 0.0, 1.0))
    _ring(body, (0.0, 0.118, 0.004), 0.153, 0.101, 0.006, 0.007, 26, profile_segments=8)
    # Waist folds and side seams under the cummerbund.
    for side in (-1.0, 1.0):
        for index in range(2):
            y = 0.166 + index * 0.028
            _crease(body, (side * 0.030, y, 0.104), (side * 0.130, y + 0.006, 0.072),
                    0.007, 0.005, (0.0, 0.0, 1.0))
        _stitch(body, (side * 0.148, 0.150, 0.050), (side * 0.162, 0.540, 0.016),
                16, 0.004, 0.003, (side, 0.0, 0.4))
        _crease(body, (side * 0.152, 0.180, 0.0), (side * 0.176, 0.560, 0.0),
                0.005, 0.004, (side, 0.0, 0.0))
    # Back yoke seam and the two shoulder-blade panels it separates.
    _stitch(body, (-0.148, 0.520, -0.116), (0.148, 0.520, -0.116), 22, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    for side in (-1.0, 1.0):
        _crease(body, (side * 0.020, 0.520, -0.132), (side * 0.170, 0.470, -0.116),
                0.006, 0.005, (0.0, 0.0, -1.0))
    # Fly seam and pelvis folds, visible between the belt and the legs.
    _crease(body, (0.0, 0.030, 0.104), (0.0, 0.104, 0.100), 0.005, 0.004, (0.0, 0.0, 1.0))
    for side in (-1.0, 1.0):
        _crease(body, (side * 0.040, -0.016, 0.092), (side * 0.110, 0.056, 0.086),
                0.006, 0.005, (side * 0.4, 0.0, 1.0))
        _stitch(body, (side * 0.052, 0.024, -0.098), (side * 0.120, 0.090, -0.080),
                7, 0.004, 0.003, (0.0, 0.0, -1.0))
    return [("torso", "ds_uniform", body)]


# --------------------------------------------------------------------------
# Plate carrier. Modelled as separate volumes - front and rear plate bags, a
# cummerbund round the ribs, straps over the shoulders, a PALS grid, magazine
# and utility pouches, a dump pouch and a padded belt - because the renderer
# needs gap and lip between adjacent volumes to resolve them.
# --------------------------------------------------------------------------

def build_vest():
    """Plate carrier front and rear, cummerbund, pouches, webbing and belt."""
    # Front plate bag: a flat face with a chamfered edge, which is what a
    # ceramic plate in a carrier reads as.
    front = Builder()
    slab(front, 0.158, 0.150, 0.032, 0.146, 0.180, origin=(0.0, 0.398, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0), corner_segments=4)
    # Plate outline seam and the bag's hem.
    _ring(front, (0.0, 0.398, 0.180), 0.126, 0.120, 0.005, 0.008, 40)
    _ring(front, (0.0, 0.398, 0.148), 0.158, 0.150, 0.006, 0.006, 40, profile_segments=8)
    box(front, (0.0, 0.262, 0.164), (0.290, 0.024, 0.034))
    # PALS: five horizontal webbing rows with the vertical stitch columns that
    # turn them into attachment points.
    for row in range(5):
        y = 0.292 + row * 0.048
        rounded_box(front, (0.0, y, 0.181), (0.284, 0.013, 0.007), 0.003, corner_segments=2)
        for column in range(7):
            x = (column - 3) * 0.042
            rounded_box(front, (x, y, 0.183), (0.009, 0.019, 0.006), 0.002)
    # Plate corner tacks and the stitching round the bag.
    for side in (-1.0, 1.0):
        _bolt(front, (side * 0.140, 0.272, 0.181), (0.0, 0.0, 1.0), 0.007, 0.005)
        _bolt(front, (side * 0.140, 0.524, 0.181), (0.0, 0.0, 1.0), 0.007, 0.005)
    _stitch(front, (-0.140, 0.545, 0.181), (0.140, 0.545, 0.181), 16, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    _stitch(front, (-0.140, 0.250, 0.181), (0.140, 0.250, 0.181), 16, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    # Admin pouch with its flap, velcro panel and buckle.
    rounded_box(front, (0.016, 0.506, 0.194), (0.148, 0.056, 0.026), 0.008, corner_segments=3)
    rounded_box(front, (0.016, 0.528, 0.198), (0.150, 0.026, 0.030), 0.008, corner_segments=3)
    rounded_box(front, (0.016, 0.502, 0.208), (0.132, 0.026, 0.004), 0.001)
    _ring(front, (0.086, 0.508, 0.200), 0.018, 0.014, 0.004, 0.004, 12, profile_segments=6)
    _stitch(front, (-0.058, 0.536, 0.212), (0.090, 0.536, 0.212), 12, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    # Drag handle over the top of the plate.
    _strap(front, [(0.076, 0.546, 0.184), (0.054, 0.578, 0.178),
                   (-0.054, 0.578, 0.178), (-0.076, 0.546, 0.184)],
           0.019, 0.006, width_axis=(0.0, 1.0, 0.0))

    # Rear plate bag, with the radio pouch's mounting panel and its own handle.
    back = Builder()
    slab(back, 0.152, 0.148, 0.032, -0.180, -0.146, origin=(0.0, 0.398, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0), corner_segments=4)
    _ring(back, (0.0, 0.398, -0.180), 0.122, 0.118, 0.005, 0.008, 40)
    _ring(back, (0.0, 0.398, -0.148), 0.152, 0.148, 0.006, 0.006, 40, profile_segments=8)
    for row in range(3):
        y = 0.320 + row * 0.052
        rounded_box(back, (0.0, y, -0.181), (0.272, 0.013, 0.007), 0.003, corner_segments=2)
        for column in range(7):
            rounded_box(back, ((column - 3) * 0.040, y, -0.183), (0.009, 0.019, 0.006), 0.002)
    for side in (-1.0, 1.0):
        _bolt(back, (side * 0.134, 0.272, -0.181), (0.0, 0.0, -1.0), 0.007, 0.005)
        _bolt(back, (side * 0.134, 0.520, -0.181), (0.0, 0.0, -1.0), 0.007, 0.005)
    _strap(back, [(0.074, 0.542, -0.184), (0.052, 0.574, -0.178),
                  (-0.052, 0.574, -0.178), (-0.074, 0.542, -0.184)],
           0.019, 0.006, width_axis=(0.0, 1.0, 0.0))
    _stitch(back, (-0.134, 0.540, -0.181), (0.134, 0.540, -0.181), 16, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    _stitch(back, (-0.134, 0.252, -0.181), (0.134, 0.252, -0.181), 16, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    # Padded lumbar pad, which is what keeps a loaded carrier off the spine.
    rounded_box(back, (0.0, 0.290, -0.196), (0.150, 0.070, 0.030), 0.012, corner_segments=3)
    for index in range(3):
        _crease(back, (-0.064, 0.268 + index * 0.024, -0.212),
                (0.064, 0.268 + index * 0.024, -0.212), 0.006, 0.005, (0.0, 0.0, -1.0))

    # Cummerbund: side panels round the ribs, each with its own PALS field, an
    # elastic section and a side-release buckle at the front edge.
    cummer = Builder()
    for side in (-1.0, 1.0):
        slab(cummer, 0.118, 0.112, 0.030, 0.0, 0.032, origin=(side * 0.194, 0.398, 0.0),
             u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), w=(side, 0.0, 0.0), corner_segments=4)
        for row in range(4):
            y = 0.312 + row * 0.048
            rounded_box(cummer, (side * 0.227, y, 0.0), (0.006, 0.013, 0.166), 0.003,
                        corner_segments=2)
            for column in range(3):
                rounded_box(cummer, (side * 0.229, y, (column - 1) * 0.052),
                            (0.005, 0.019, 0.009), 0.002)
        # Elastic section and the panel's piping.
        for index in range(3):
            rounded_box(cummer, (side * 0.226, 0.398, 0.070 + index * 0.016),
                        (0.006, 0.096, 0.008), 0.003, corner_segments=2)
        _ring(cummer, (side * 0.226, 0.398, 0.0), 0.112, 0.116, 0.004, 0.005, 30,
              u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0))
        _stitch(cummer, (side * 0.228, 0.286, -0.090), (side * 0.228, 0.286, 0.090),
                12, 0.004, 0.003, (side, 0.0, 0.0))
        # Side-release buckle closing the cummerbund onto the front plate.
        rounded_box(cummer, (side * 0.200, 0.398, 0.118), (0.026, 0.048, 0.020), 0.006)
        box(cummer, (side * 0.196, 0.398, 0.132), (0.030, 0.012, 0.014))
        _strap(cummer, [(side * 0.196, 0.398, 0.124), (side * 0.184, 0.398, 0.150)],
               0.024, 0.006, width_axis=(0.0, 1.0, 0.0))

    # Shoulder straps, routed over the shoulders, with pads, buckles and the
    # sternum strap that holds them together. The crown of each strap follows the
    # trapezius ridge at hips-local y = 0.64 and only stands a centimetre proud
    # of it; a strap arced higher reads as a fin welded to the shoulder.
    straps = Builder()
    for side in (-1.0, 1.0):
        _strap(straps, [(side * 0.098, 0.492, 0.180), (side * 0.112, 0.552, 0.124),
                        (side * 0.118, 0.578, 0.010), (side * 0.112, 0.556, -0.100),
                        (side * 0.094, 0.496, -0.148)],
               0.030, 0.008, width_axis=(1.0, 0.0, 0.0))
        # Padded section on the crown of the shoulder.
        for index in range(2):
            _strap(straps, [(side * 0.106, 0.564 - index * 0.020, 0.058 - index * 0.032),
                            (side * 0.114, 0.572 - index * 0.020, 0.018 - index * 0.032)],
                   0.028 - index * 0.002, 0.012, width_axis=(1.0, 0.0, 0.0))
        # Front side-release buckle and its keepers.
        rounded_box(straps, (side * 0.098, 0.508, 0.192), (0.036, 0.030, 0.014), 0.005)
        rounded_box(straps, (side * 0.098, 0.480, 0.190), (0.030, 0.026, 0.012), 0.004)
        _ring(straps, (side * 0.106, 0.542, 0.150), 0.032, 0.010, 0.005, 0.005, 12,
              u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=6)
        _stitch(straps, (side * 0.108, 0.560, 0.096), (side * 0.110, 0.588, 0.030),
                9, 0.004, 0.003, (side * 0.4, 0.4, 0.8))
    _strap(straps, [(-0.100, 0.516, 0.186), (0.100, 0.516, 0.186)], 0.016, 0.005,
           width_axis=(0.0, 1.0, 0.0))
    rounded_box(straps, (0.0, 0.516, 0.194), (0.032, 0.032, 0.014), 0.005)
    box(straps, (0.0, 0.516, 0.202), (0.010, 0.022, 0.008))

    # Three rifle magazine pouches with lids, closure straps and bungee
    # retention: the tallest volume on the front of the carrier.
    magazines = Builder()
    for index in range(3):
        x = (index - 1) * 0.090
        y = 0.288 - (0.018 if index == 1 else 0.0)
        rounded_box(magazines, (x, y, 0.206), (0.082, 0.120, 0.048), 0.008, corner_segments=3)
        # Divider ridge and a drain eyelet at the base.
        _crease(magazines, (x, y - 0.048, 0.230), (x, y + 0.048, 0.230), 0.004, 0.003,
                (0.0, 0.0, 1.0))
        _ring(magazines, (x, y - 0.062, 0.214), 0.007, 0.007, 0.004, 0.003, 10,
              profile_segments=6)
        for side in (-1.0, 1.0):
            _stitch(magazines, (x + side * 0.041, y - 0.052, 0.204),
                    (x + side * 0.041, y + 0.052, 0.204), 6, 0.004, 0.003, (0.0, 0.0, 1.0))
        # Lid, hinged at the top, with the closure strap and buckle down the front.
        rounded_box(magazines, (x, y + 0.070, 0.206), (0.084, 0.034, 0.052), 0.008,
                    corner_segments=3)
        _crease(magazines, (x - 0.040, y + 0.086, 0.196), (x + 0.040, y + 0.086, 0.196),
                0.005, 0.005, (0.0, 1.0, 0.0))
        _strap(magazines, [(x, y + 0.076, 0.236), (x, y + 0.030, 0.244),
                           (x, y - 0.014, 0.240)], 0.012, 0.004, width_axis=(1.0, 0.0, 0.0))
        rounded_box(magazines, (x, y + 0.020, 0.248), (0.028, 0.024, 0.010), 0.004)
        box(magazines, (x, y + 0.020, 0.254), (0.014, 0.008, 0.006))
        _route(magazines, [(x - 0.042, y + 0.084, 0.230), (x, y + 0.054, 0.250),
                           (x + 0.042, y + 0.084, 0.230)], [0.0035, 0.0035, 0.0035], 8)
        rounded_box(magazines, (x, y - 0.062, 0.230), (0.070, 0.028, 0.008), 0.002)

    # Utility pouches: radio with a whip antenna on the right, grenade and
    # smoke pouches on the left, plus a small compass pouch.
    utilities = Builder()
    rounded_box(utilities, (0.202, 0.330, 0.128), (0.052, 0.112, 0.060), 0.010,
                corner_segments=3)
    rounded_box(utilities, (0.202, 0.394, 0.132), (0.054, 0.030, 0.064), 0.010,
                corner_segments=3)
    _route(utilities, [(0.212, 0.400, 0.140), (0.216, 0.470, 0.146),
                       (0.218, 0.560, 0.150)], [0.0060, 0.0042, 0.0032], 10)
    rounded_box(utilities, (0.218, 0.566, 0.150), (0.014, 0.018, 0.014), 0.005)
    for index in range(4):
        rounded_box(utilities, (0.228, 0.318 + index * 0.014, 0.128), (0.005, 0.007, 0.040),
                    0.002)
    _bolt(utilities, (0.204, 0.280, 0.158), (0.0, 0.0, 1.0), 0.006, 0.005)
    for index in range(2):
        y = 0.300 + index * 0.086
        rounded_box(utilities, (-0.202, y, 0.132), (0.052, 0.078, 0.056), 0.010,
                    corner_segments=3)
        rounded_box(utilities, (-0.202, y + 0.048, 0.136), (0.054, 0.024, 0.060), 0.010,
                    corner_segments=3)
        _strap(utilities, [(-0.202, y + 0.052, 0.162), (-0.202, y, 0.168),
                           (-0.202, y - 0.046, 0.164)], 0.020, 0.004,
               width_axis=(1.0, 0.0, 0.0))
        rounded_box(utilities, (-0.202, y - 0.010, 0.170), (0.026, 0.022, 0.009), 0.004)
        _route(utilities, [(-0.240, y + 0.046, 0.156), (-0.202, y + 0.020, 0.172),
                           (-0.164, y + 0.046, 0.156)], [0.0035, 0.0035, 0.0035], 8)
    rounded_box(utilities, (-0.140, 0.290, 0.166), (0.056, 0.044, 0.028), 0.008,
                corner_segments=3)
    rounded_box(utilities, (-0.140, 0.312, 0.170), (0.058, 0.018, 0.032), 0.008,
                corner_segments=3)
    _stitch(utilities, (-0.168, 0.270, 0.178), (-0.112, 0.270, 0.178), 7, 0.004, 0.003,
            (0.0, 0.0, 1.0))

    # Dump pouch, collapsed against the left rear hip and held by two straps.
    dump = Builder()
    rounded_box(dump, (-0.186, 0.296, -0.104), (0.062, 0.094, 0.076), 0.014,
                corner_segments=3)
    _ring(dump, (-0.186, 0.344, -0.104), 0.031, 0.038, 0.006, 0.007, 16,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
    for index in range(4):
        _crease(dump, (-0.186, 0.250 + index * 0.020, -0.142),
                (-0.186, 0.250 + index * 0.020, -0.066), 0.006, 0.005, (-1.0, 0.0, 0.0))
    for index in range(2):
        z = -0.130 + index * 0.052
        _strap(dump, [(-0.186, 0.348, z), (-0.186, 0.300, z + 0.004),
                      (-0.186, 0.252, z)], 0.010, 0.004, width_axis=(0.0, 0.0, 1.0))
        rounded_box(dump, (-0.212, 0.296, z + 0.002), (0.016, 0.022, 0.014), 0.004)
    _bolt(dump, (-0.186, 0.240, -0.104), (-0.4, -1.0, 0.0), 0.006, 0.005)
    _stitch(dump, (-0.186, 0.336, -0.136), (-0.186, 0.336, -0.072), 8, 0.004, 0.003,
            (-1.0, 0.0, 0.0))

    # Padded belt: a closed band with a cobra buckle, keepers, side pouches, a
    # medical pouch and pistol magazine pouches.
    belt = Builder()
    _ring(belt, (0.0, 0.148, 0.004), 0.164, 0.108, 0.026, 0.020, 30,
          profile_segments=0, corner_segments=3)
    rounded_box(belt, (0.0, 0.148, 0.116), (0.052, 0.040, 0.024), 0.008)
    box(belt, (0.0, 0.148, 0.130), (0.034, 0.020, 0.010))
    for side in (-1.0, 1.0):
        rounded_box(belt, (side * 0.040, 0.150, 0.120), (0.030, 0.036, 0.016), 0.005)
        _stitch(belt, (side * 0.062, 0.140, 0.104), (side * 0.152, 0.140, 0.064),
                12, 0.004, 0.003, (0.0, 0.0, 1.0))
        for index in range(2):
            x = side * (0.062 + index * 0.070)
            _ring(belt, (x, 0.148, 0.100), 0.030, 0.014, 0.006, 0.006, 14,
                  u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=6)
            rounded_box(belt, (x, 0.128, 0.104), (0.030, 0.030, 0.012), 0.005)
        rounded_box(belt, (side * 0.170, 0.146, 0.020), (0.050, 0.072, 0.050), 0.010,
                    corner_segments=3)
        rounded_box(belt, (side * 0.172, 0.180, 0.020), (0.052, 0.020, 0.054), 0.010,
                    corner_segments=3)
        rounded_box(belt, (side * 0.194, 0.158, 0.020), (0.014, 0.022, 0.012), 0.004)
    rounded_box(belt, (-0.130, 0.146, -0.086), (0.060, 0.078, 0.034), 0.010,
                corner_segments=3)
    _stitch(belt, (-0.160, 0.112, -0.086), (-0.100, 0.112, -0.086), 8, 0.004, 0.003,
            (0.0, -1.0, 0.0))
    for index in range(2):
        rounded_box(belt, (0.140, 0.146, -0.084 + index * 0.038), (0.038, 0.052, 0.030),
                    0.008, corner_segments=3)
    return [("vest_front", "ds_vest", front), ("vest_back", "ds_vest", back),
            ("vest_cummerbund", "ds_vest", cummer), ("vest_straps", "ds_gear", straps),
            ("vest_magazines", "ds_gear", magazines), ("vest_utilities", "ds_gear", utilities),
            ("vest_dump", "ds_gear", dump), ("belt", "ds_gear", belt)]


def build_pack():
    """Hydration and radio pack on the back, with its tube over the shoulder."""
    pack = Builder()
    # Main body, its lid and the panel seams that split it into volumes.
    rounded_box(pack, (0.0, 0.398, -0.204), (0.196, 0.298, 0.118), 0.030, corner_segments=4)
    rounded_box(pack, (0.0, 0.560, -0.212), (0.194, 0.070, 0.122), 0.028, corner_segments=4)
    _crease(pack, (-0.096, 0.300, -0.266), (0.096, 0.300, -0.266), 0.006, 0.005, (0.0, 0.0, -1.0))
    for index in range(3):
        _crease(pack, (-0.090, 0.340 + index * 0.060, -0.266),
                (0.090, 0.340 + index * 0.060, -0.266), 0.005, 0.004, (0.0, 0.0, -1.0))
    # PALS columns, a zipper strip, and the lid's compression straps.
    for row in range(3):
        y = 0.330 + row * 0.046
        rounded_box(pack, (0.0, y, -0.266), (0.170, 0.013, 0.007), 0.003, corner_segments=2)
        for column in range(5):
            rounded_box(pack, ((column - 2) * 0.040, y, -0.268), (0.009, 0.019, 0.006), 0.002)
    _stitch(pack, (-0.070, 0.520, -0.272), (0.070, 0.520, -0.272), 14, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    for index in range(2):
        x = -0.062 + index * 0.124
        _strap(pack, [(x, 0.596, -0.268), (x, 0.540, -0.276), (x, 0.470, -0.270)],
               0.018, 0.006, width_axis=(1.0, 0.0, 0.0))
        rounded_box(pack, (x, 0.556, -0.280), (0.030, 0.026, 0.012), 0.005)
    # Radio pouch on the lid with a whip antenna, and the hydration bladder's
    # filler cap on the flank.
    rounded_box(pack, (-0.108, 0.586, -0.206), (0.070, 0.052, 0.076), 0.012,
                corner_segments=3)
    _route(pack, [(-0.108, 0.596, -0.180), (-0.116, 0.660, -0.170),
                  (-0.120, 0.740, -0.164)], [0.0060, 0.0040, 0.0030], 10)
    rounded_box(pack, (-0.120, 0.746, -0.164), (0.014, 0.020, 0.014), 0.005)
    for index in range(3):
        rounded_box(pack, (-0.108, 0.566 + index * 0.012, -0.168), (0.040, 0.006, 0.005), 0.002)
    _ring(pack, (0.0, 0.610, -0.212), 0.030, 0.026, 0.008, 0.008, 14,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
    # Drinking tube: over the right shoulder, down the front, to a bite valve.
    _route(pack, [(0.090, 0.560, -0.150), (0.112, 0.580, -0.070),
                  (0.118, 0.586, 0.020), (0.110, 0.560, 0.104),
                  (0.104, 0.512, 0.150), (0.098, 0.470, 0.156)],
           [0.0070, 0.0070, 0.0070, 0.0070, 0.0065, 0.0060], 10)
    rounded_box(pack, (0.098, 0.458, 0.158), (0.020, 0.030, 0.018), 0.006)
    # Drag handle and the shoulder-strap attachment points.
    _strap(pack, [(-0.052, 0.628, -0.244), (0.0, 0.640, -0.236), (0.052, 0.628, -0.244)],
           0.018, 0.006, width_axis=(0.0, 1.0, 0.0))
    for side in (-1.0, 1.0):
        rounded_box(pack, (side * 0.088, 0.470, -0.150), (0.036, 0.040, 0.018), 0.006)
        _ring(pack, (side * 0.088, 0.470, -0.146), 0.022, 0.022, 0.005, 0.005, 12,
              u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=6)
        _stitch(pack, (side * 0.096, 0.300, -0.264), (side * 0.096, 0.500, -0.264),
                10, 0.004, 0.003, (0.0, 0.0, -1.0))
    return [("pack", "ds_gear", pack)]


def build_pelvis():
    """Seat and crotch: the mass that closes the torso hem into both thighs.

    The torso stops at hips-local -0.03 and each leg's own section is 9.4 cm wide
    on a 13 cm pitch, so on their own they leave a 9 cm see-through slot between
    the inner thighs from the hem down. This part supplies what a pair of
    trousers actually has there: a seat behind, a tapered crotch in front of it,
    the inner-thigh surfaces closing onto that wedge, a fly with its cover flap,
    the waistband standing proud under the belt, and the seat seams.
    """
    pelvis = Builder()
    # Seat: the pelvis mass, wide enough to meet both thigh sections. Its hem is
    # the lowest point of the torso and its sides reach past each leg's centre.
    _stacked(pelvis, [
        (-0.010, 0.172, 0.106, 0.004, 0.06),
        (-0.040, 0.174, 0.108, 0.004, 0.02),
        (-0.072, 0.160, 0.104, 0.006, -0.04),
        (-0.100, 0.128, 0.096, 0.008, -0.12),
        (-0.124, 0.090, 0.082, 0.010, -0.20),
        (-0.144, 0.050, 0.062, 0.012, -0.28),
        (-0.158, 0.020, 0.044, 0.014, -0.34),
    ], 26)
    # Crotch wedge in front of the seat: a gusset spanning the slot between the
    # thigh inner faces, hanging to just below mid-thigh where a standing figure's
    # thighs part. It belongs to the body, not to either thigh, so it stays put
    # when the legs swing instead of bridging them.
    _stacked(pelvis, [
        (-0.048, 0.100, 0.070, 0.070, -0.16),
        (-0.084, 0.082, 0.058, 0.076, -0.26),
        (-0.118, 0.068, 0.050, 0.078, -0.34),
        (-0.152, 0.060, 0.044, 0.074, -0.40),
        (-0.184, 0.056, 0.040, 0.068, -0.44),
        (-0.216, 0.052, 0.036, 0.062, -0.48),
        (-0.250, 0.048, 0.032, 0.056, -0.52),
        (-0.285, 0.042, 0.030, 0.048, -0.55),
        (-0.325, 0.036, 0.028, 0.042, -0.58),
    ], 22)
    # Inner thighs: each side's surface, closing onto the gusset, so no line of
    # sight passes between the legs down to the parting point.
    for side in (-1.0, 1.0):
        _stacked(pelvis, [
            (-0.056, 0.042, 0.066, 0.020, -0.12),
            (-0.090, 0.056, 0.056, 0.034, -0.20),
            (-0.124, 0.062, 0.046, 0.048, -0.28),
            (-0.156, 0.064, 0.038, 0.058, -0.34),
            (-0.186, 0.064, 0.032, 0.062, -0.40),
            (-0.218, 0.062, 0.028, 0.060, -0.46),
            (-0.250, 0.058, 0.026, 0.056, -0.50),
            (-0.285, 0.054, 0.024, 0.050, -0.54),
            (-0.325, 0.052, 0.022, 0.044, -0.58),
        ], 18)
    # Waistband standing proud over the shirt, tucked under the belt: its top edge
    # reaches hips-local 0.116, past the belt's lower edge at 0.107, so the two
    # overlap and the belt-to-legs transition reads as one garment.
    _ring(pelvis, (0.0, 0.086, 0.004), 0.170, 0.104, 0.030, 0.009, 30,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    _stitch(pelvis, (-0.070, 0.060, 0.108), (0.070, 0.060, 0.108), 14, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    # Fly: the seam down the centre front, its cover flap, and the button.
    _crease(pelvis, (0.006, 0.050, 0.106), (0.006, -0.096, 0.078), 0.005, 0.005,
            (0.0, 0.0, 1.0))
    slab(pelvis, 0.026, 0.086, 0.008, 0.104, 0.112, origin=(0.008, -0.022, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0), corner_segments=3)
    _stitch(pelvis, (0.026, 0.020, 0.112), (0.026, -0.088, 0.108), 9, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    _bolt(pelvis, (0.0, 0.056, 0.116), (0.0, 0.0, 1.0), 0.007, 0.005)
    # Seat seams and the back pocket flaps, which is what reads from behind.
    for side in (-1.0, 1.0):
        _crease(pelvis, (side * 0.010, -0.010, -0.102), (side * 0.120, -0.086, -0.078),
                0.006, 0.005, (0.0, 0.0, -1.0))
        rounded_box(pelvis, (side * 0.082, -0.062, -0.098), (0.072, 0.058, 0.010), 0.004)
        _stitch(pelvis, (side * 0.048, -0.038, -0.100), (side * 0.116, -0.038, -0.100),
                6, 0.004, 0.003, (0.0, 0.0, -1.0))
        # Outer belt-adjacent tab, tying the waistband into the belt.
        rounded_box(pelvis, (side * 0.128, 0.052, 0.020), (0.036, 0.038, 0.036), 0.006)
    # A short seat seam across the top of the wedge.
    _stitch(pelvis, (-0.086, -0.062, 0.086), (0.086, -0.062, 0.086), 14, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    return [("pelvis", "ds_uniform", pelvis)]


# --------------------------------------------------------------------------
# Head. Built in head-local space; the head pivot sits at hips-local 0.88, so
# the skull is centred slightly below it and the neck continues down to the
# collar at hips-local 0.74. The face reads +Z.
# --------------------------------------------------------------------------

def build_head():
    """Neck, cranium, mandible, brow, cheekbones, nose, mouth and ears.

    The cranium is deliberately shallow front to back: a symmetric ellipsoid
    that already included the face's depth would leave the brow, cheekbones and
    nose buried inside the skull, so the face plane is built from its own
    volumes - brow ridge, cheekbone, mandible, nose - standing proud of it.
    """
    head = Builder()
    # Neck, with the sternocleidomastoid running from the collar to behind the ear.
    tube(head, (0.0, -0.226, 0.002), (0.0, -0.108, 0.008), 0.058, 20, radius_end=0.055, steps=4)
    for side in (-1.0, 1.0):
        _route(head, [(side * 0.040, -0.210, 0.036), (side * 0.058, -0.168, 0.030),
                      (side * 0.066, -0.132, 0.010)], [0.020, 0.017, 0.012], 10)
    # Cranium. `tilt` drops the face and lifts the nape, so the brow sits above
    # the chin the way a real cranium leans over the jaw.
    _stacked(head, [
        (-0.188, 0.062, 0.056, -0.006, -0.10),
        (-0.162, 0.080, 0.074, -0.002, -0.12),
        (-0.128, 0.090, 0.084, 0.004, -0.10),
        (-0.088, 0.095, 0.088, 0.010, -0.04),
        (-0.040, 0.095, 0.090, 0.014, 0.02),
        (0.000, 0.088, 0.086, 0.016, 0.06),
        (0.032, 0.068, 0.070, 0.016, 0.08),
        (0.048, 0.038, 0.040, 0.014, 0.06),
    ], 24)
    # Mandible: its own volume, so the jaw reads against the cheek instead of
    # blending into it, and it carries the chin forward under the mouth.
    _stacked(head, [
        (-0.246, 0.036, 0.030, 0.030, -0.32),
        (-0.232, 0.056, 0.048, 0.024, -0.30),
        (-0.212, 0.072, 0.066, 0.014, -0.24),
        (-0.188, 0.084, 0.080, 0.006, -0.18),
        (-0.160, 0.090, 0.088, 0.002, -0.10),
        (-0.132, 0.092, 0.090, 0.002, -0.05),
    ], 24)
    # Jaw line from the chin to the ear, which is what separates face from throat.
    for side in (-1.0, 1.0):
        _crease(head, (side * 0.020, -0.226, 0.064), (side * 0.086, -0.160, 0.020),
                0.005, 0.005, (side * 0.7, -0.3, 0.6))
    # Brow ridge, following the cranium's ellipse out to each temple.
    _strap(head, [(0.092, -0.086, 0.046), (0.056, -0.098, 0.092),
                  (0.0, -0.096, 0.104), (-0.056, -0.098, 0.092),
                  (-0.092, -0.086, 0.046)], 0.013, 0.009, width_axis=(0.0, 1.0, 0.0))
    for side in (-1.0, 1.0):
        _crease(head, (side * 0.010, -0.104, 0.102), (side * 0.030, -0.112, 0.092),
                0.004, 0.004, (0.0, 0.0, 1.0))
    # Cheekbone, the jaw's rear corner, and the temple. The hollows beneath and
    # behind them are modelled by the ridges that bound them rather than by
    # recessed plates: without boolean subtraction a recessed plate would expose
    # its own interior as a dark face instead of reading as a hollow.
    for side in (-1.0, 1.0):
        _dome(head, (side * 0.066, -0.150, 0.062), 0.026, 0.032, 0.014,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side * 0.9, -0.15, 0.45))
        _dome(head, (side * 0.068, -0.180, 0.030), 0.022, 0.028, 0.013,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side * 0.9, 0.10, 0.30))
        _dome(head, (side * 0.076, -0.110, 0.044), 0.020, 0.026, 0.012,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side, 0.0, 0.30))
        _crease(head, (side * 0.036, -0.166, 0.064), (side * 0.082, -0.138, 0.018),
                0.005, 0.004, (side * 0.5, 0.0, 1.0))
        # The two folds that bound the cheek hollow: under the cheekbone, and
        # down the back of the cheek in front of the ear.
        _crease(head, (side * 0.038, -0.196, 0.036), (side * 0.078, -0.160, 0.010),
                0.005, 0.004, (side * 0.7, 0.0, 0.8))
        _crease(head, (side * 0.082, -0.144, 0.024), (side * 0.086, -0.158, -0.030),
                0.004, 0.004, (side, 0.0, 0.2))
    # Nose: one blade from the bridge to the tip, then the wings and septum.
    _strap(head, [(0.0, -0.098, 0.098), (0.0, -0.146, 0.108), (0.0, -0.184, 0.104),
                  (0.0, -0.200, 0.088)],
           [0.015, 0.019, 0.023, 0.021], [0.013, 0.019, 0.023, 0.017],
           width_axis=(1.0, 0.0, 0.0))
    for side in (-1.0, 1.0):
        _dome(head, (side * 0.020, -0.194, 0.076), 0.015, 0.017, 0.012,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side, -0.2, 0.5))
        _crease(head, (side * 0.005, -0.206, 0.078), (side * 0.019, -0.202, 0.072),
                0.004, 0.004, (side * 0.4, 0.0, 1.0))
    # Mouth: upper lip, lower lip, the line between them and the chin crease.
    _crease(head, (-0.026, -0.208, 0.090), (0.026, -0.208, 0.090), 0.005, 0.004,
            (0.0, 0.0, 1.0))
    _strap(head, [(-0.028, -0.202, 0.086), (0.0, -0.208, 0.092), (0.028, -0.202, 0.086)],
           0.010, 0.006, width_axis=(0.0, 1.0, 0.0))
    _strap(head, [(-0.024, -0.216, 0.082), (0.0, -0.220, 0.088), (0.024, -0.216, 0.082)],
           0.009, 0.006, width_axis=(0.0, 1.0, 0.0))
    _dome(head, (0.0, -0.240, 0.064), 0.024, 0.020, 0.016, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
          (0.0, -0.3, 1.0))
    _crease(head, (-0.018, -0.230, 0.082), (0.018, -0.230, 0.082), 0.005, 0.004,
            (0.0, -0.3, 1.0))
    # Ears: helix rim, lobe, tragus and a recessed canal.
    for side in (-1.0, 1.0):
        slab(head, 0.026, 0.036, 0.013, 0.090, 0.106, origin=(0.0, -0.126, 0.008),
             u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(side, 0.0, 0.0), corner_segments=3)
        _ring(head, (side * 0.104, -0.124, 0.008), 0.028, 0.034, 0.005, 0.006, 14,
              u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
        _dome(head, (side * 0.098, -0.154, -0.020), 0.017, 0.019, 0.012,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side, -0.3, 0.0))
        _dome(head, (side * 0.098, -0.110, 0.016), 0.013, 0.019, 0.010,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side, 0.3, 0.4))
        tube(head, (side * 0.078, -0.134, 0.006), (side * 0.096, -0.136, 0.006),
             0.009, 10, cap_start=False)
        _stitch(head, (side * 0.096, -0.158, -0.006), (side * 0.096, -0.146, -0.016),
                4, 0.004, 0.003, (side, 0.0, 0.0))
    return [("skull", "ds_skin", head)]


def build_helmet():
    """Ballistic helmet: shell, brow lip, nape skirt, rails, vents and rivets.

    The shell's rim sits at head-local -0.078, which is 1.8 cm above the eye line
    at -0.096. A shell carried any lower cuts across the goggles and reads as a
    mask rather than a helmet; the nape skirt, not the rim, is what covers the
    neck behind.
    """
    shell = Builder()
    _stacked(shell, [
        (-0.078, 0.106, 0.112, -0.004, -0.16),
        (-0.055, 0.114, 0.121, -0.002, -0.12),
        (-0.020, 0.118, 0.126, 0.004, -0.06),
        (0.010, 0.116, 0.124, 0.008, 0.00),
        (0.038, 0.104, 0.110, 0.012, 0.06),
        (0.058, 0.082, 0.086, 0.014, 0.12),
        (0.072, 0.048, 0.052, 0.014, 0.16),
        (0.082, 0.018, 0.020, 0.012, 0.18),
    ], 32)
    # Rolled rim round the bottom edge, and the raised brow lip above the brim.
    _ring(shell, (0.0, -0.080, -0.004), 0.108, 0.114, 0.008, 0.007, 36,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0))
    extrude(shell, _band_profile(0.112, 0.118, 0.010, -0.78, 0.78, 22), 0.0, 0.016,
            origin=(0.0, -0.070, 0.0), u=(0.0, 0.0, 1.0), v=(1.0, 0.0, 0.0),
            w=(0.0, 1.0, 0.0))
    # Nape skirt: the rear lip that covers the neck, as its own curved panel. It
    # hangs below the rim, which is where a real helmet's rear edge ends up. The
    # profile's winding assumes extrusion along +`w`, so `start` must be the
    # lower value: running it the other way emits the panel inside-out.
    extrude(shell, _band_profile(0.112, 0.118, 0.010, 0.78, 2.36, 20), -0.032, 0.0,
            origin=(0.0, -0.076, 0.0), u=(0.0, 0.0, 1.0), v=(1.0, 0.0, 0.0),
            w=(0.0, 1.0, 0.0))
    # Crown panel seams splitting the shell into volumes.
    for offset in (-0.52, 0.0, 0.52):
        for side in (-1.0, 1.0):
            _crease(shell, (side * 0.104 * math.cos(offset), -0.054 + side * 0.020,
                            0.122 * math.sin(offset) + 0.010),
                    (side * 0.026 * math.cos(offset), 0.052, 0.030 * math.sin(offset) + 0.014),
                    0.004, 0.004, (math.cos(offset), 0.2, math.sin(offset)))
    # Vent slots on the front slope of the crown, with raised lips so they read
    # as cut into the shell rather than laid on it.
    for index in range(4):
        y = 0.014 + index * 0.011
        z = 0.126 - index * 0.013
        rounded_box(shell, (0.0, y, z), (0.100, 0.007, 0.014), 0.003)
        for side in (-1.0, 1.0):
            rounded_box(shell, (side * 0.028, y, z - 0.001), (0.040, 0.010, 0.018), 0.004)
    # Side rails: thin plates standing off the shell at the temple, running front
    # to back, with accessory slots cut into their outer face.
    for side in (-1.0, 1.0):
        slab(shell, 0.058, 0.015, 0.007, 0.112, 0.128, origin=(0.0, -0.046, 0.004),
             u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), w=(side, 0.0, 0.0), corner_segments=3)
        for index in range(5):
            rounded_box(shell, (side * 0.130, -0.046, -0.044 + index * 0.024),
                        (0.008, 0.017, 0.010), 0.002)
        _stitch(shell, (side * 0.131, -0.060, -0.050), (side * 0.131, -0.060, 0.054),
                7, 0.004, 0.003, (side, 0.0, 0.0))
        for end in (-0.050, 0.056):
            _bolt(shell, (side * 0.130, -0.046, end), (side, 0.0, 0.0), 0.006, 0.005)
        # Rear bracket tying the rail back onto the shell.
        _ring(shell, (side * 0.120, -0.062, 0.006), 0.018, 0.018, 0.007, 0.006, 12,
              u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=6)
    # Helmet cover: stitching round the brim and across the crown.
    _stitch(shell, (-0.080, -0.066, 0.078), (0.080, -0.066, 0.078), 16, 0.004, 0.003,
            (0.0, -0.5, 1.0))
    _stitch(shell, (-0.010, 0.046, -0.098), (-0.010, 0.046, 0.098), 12, 0.004, 0.003,
            (0.0, 1.0, 0.0))
    return [("helmet", "ds_helmet", shell)]


def build_helmet_gear():
    """NVG shroud and mount arm on the brow, plus the chin strap routing.

    The mount projects forward from the brim: the shroud plate lies on the shell
    at head-local y = -0.052, the arm cantilevers out to +Z, and the horn ends at
    head-local z = +0.15, just above the brim's 0.13. A mount built along the
    head's local axes instead points straight down the back of the helmet.
    """
    gear = Builder()
    # Shroud: a plate bolted flat onto the front slope of the shell, at the brim.
    # `slab`'s `w` is the extrusion axis, so the plate lies in x/z with its
    # outward face along +Z and is thin in Y - the way it sits on the brow. As
    # with any extrusion, `start` must be the lower value along `w`.
    slab(gear, 0.032, 0.028, 0.009, -0.070, -0.052, origin=(0.0, 0.0, 0.106),
         u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), w=(0.0, 1.0, 0.0), corner_segments=3)
    for side in (-1.0, 1.0):
        for index in range(2):
            _bolt(gear, (side * 0.021, -0.058 - index * 0.010, 0.132), (0.0, 0.0, 1.0),
                  0.006, 0.005)
    # Mount arm. With no optic fitted the arm is folded up against the shell, so
    # it lies along the brim's front slope and the horn stops clear of the
    # goggles; cantilevered out at eye level it would read as a lens the soldier
    # is looking through. Built as tubes along that path - a slab extruded along
    # +Y would stand the arm straight up out of the crown.
    tube(gear, (0.0, -0.042, 0.118), (0.0, -0.014, 0.138), 0.014, 12)
    tube(gear, (0.0, -0.012, 0.136), (0.0, 0.006, 0.158), 0.012, 12)
    cone(gear, (0.0, 0.008, 0.158), (0.0, 0.014, 0.202), 0.025, 16)
    _ring(gear, (0.0, 0.012, 0.184), 0.026, 0.026, 0.005, 0.005, 16,
          u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=8)
    rounded_box(gear, (0.0, 0.010, 0.172), (0.056, 0.012, 0.012), 0.004)
    _bolt(gear, (0.030, 0.010, 0.172), (1.0, 0.0, 0.0), 0.006, 0.005)
    # The lever that releases the mount, on the near side of the arm.
    rounded_box(gear, (0.040, -0.014, 0.132), (0.010, 0.022, 0.034), 0.004)
    # Chin strap: down each side behind the rail, under the jaw, closed by a
    # buckle that meets at the chin, plus the nape strap at the back.
    for side in (-1.0, 1.0):
        _strap(gear, [(side * 0.106, -0.070, 0.010), (side * 0.100, -0.130, -0.052),
                      (side * 0.070, -0.186, -0.108), (side * 0.030, -0.214, -0.140)],
               0.012, 0.005, width_axis=(0.0, 0.0, 1.0))
        rounded_box(gear, (side * 0.034, -0.214, -0.142), (0.026, 0.020, 0.028), 0.005)
        _bolt(gear, (side * 0.034, -0.220, -0.154), (0.0, -0.6, -1.0), 0.005, 0.004)
        _strap(gear, [(side * 0.104, -0.056, -0.048), (side * 0.064, -0.048, -0.110),
                      (side * 0.018, -0.044, -0.136)], 0.011, 0.005,
               width_axis=(0.0, 1.0, 0.0))
        _bolt(gear, (side * 0.104, -0.066, 0.012), (side, 0.0, 0.0), 0.006, 0.005)
    rounded_box(gear, (0.0, -0.220, -0.146), (0.044, 0.024, 0.020), 0.006)
    box(gear, (0.0, -0.226, -0.150), (0.020, 0.010, 0.009))
    # Counterweight pouch on the nape, strapped down onto the shell's rear edge.
    rounded_box(gear, (0.0, -0.010, -0.128), (0.090, 0.056, 0.040), 0.012, corner_segments=3)
    _strap(gear, [(-0.042, -0.010, -0.146), (0.0, -0.010, -0.152),
                  (0.042, -0.010, -0.146)], 0.014, 0.005, width_axis=(0.0, 1.0, 0.0))
    _stitch(gear, (-0.036, -0.038, -0.146), (0.036, -0.038, -0.146), 6, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    return [("helmetgear", "ds_gear", gear)]


def build_face():
    """Nose bridge, mouth line, beard shadow and the jaw's soft detail.

    The goggles carry the eye region, so this part covers what stays visible
    around them: the nasal bridge under the frame, the nasolabial folds, the
    lips, the chin and the stubble line along the jaw.
    """
    face = Builder()
    # Nasal bridge filler where the cranium, mandible and nose meet.
    _dome(face, (0.0, -0.168, 0.096), 0.022, 0.020, 0.010, (1.0, 0.0, 0.0),
          (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    # Nasolabial folds and the two smile lines beside the mouth.
    for side in (-1.0, 1.0):
        _crease(face, (side * 0.019, -0.206, 0.088), (side * 0.044, -0.172, 0.064),
                0.005, 0.004, (side * 0.6, 0.0, 0.8))
        _crease(face, (side * 0.030, -0.216, 0.080), (side * 0.054, -0.196, 0.058),
                0.004, 0.004, (side * 0.7, 0.0, 0.7))
    # Chin ball and the crease above it, which is what gives the jaw its point.
    _dome(face, (0.0, -0.238, 0.070), 0.024, 0.020, 0.014, (1.0, 0.0, 0.0),
          (0.0, 1.0, 0.0), (0.0, -0.3, 1.0))
    _crease(face, (-0.017, -0.228, 0.080), (0.017, -0.228, 0.080), 0.005, 0.004,
            (0.0, -0.2, 1.0))
    # Beard shadow: a stubble line along the jaw and up over the upper lip,
    # laid on as low-relief dashes rather than a shell.
    for offset in (-0.026, 0.0, 0.026):
        _strap(face, [(offset - 0.026, -0.204, 0.086), (offset, -0.214, 0.082),
                      (offset + 0.026, -0.204, 0.086)], 0.007, 0.0025,
               width_axis=(0.0, 1.0, 0.0))
    for side in (-1.0, 1.0):
        _strap(face, [(side * 0.006, -0.240, 0.062), (side * 0.026, -0.230, 0.072),
                      (side * 0.044, -0.212, 0.064)], 0.009, 0.0025,
               width_axis=(0.0, 1.0, 0.0))
        _stitch(face, (side * 0.034, -0.198, 0.058), (side * 0.070, -0.156, 0.024),
                6, 0.004, 0.0025, (side * 0.7, 0.0, 0.6))
    return [("face_detail", "ds_skin", face)]


def build_goggles():
    """Sealed eye protection: frame and seal, lens, strap, adjuster and buckle.

    The eye sits at head-local z = 0.062, so the whole assembly - frame, lens,
    seal - is built around that plane rather than below it; a goggle that
    intersected the brow ridge would read as a visor pressed into the skull.
    """
    frame = Builder()
    eye_y = -0.096
    eye_z = 0.062
    for side in (-1.0, 1.0):
        # Frame band round each eye opening, and the foam seal behind it.
        _ring(frame, (side * 0.044, eye_y, eye_z), 0.046, 0.030, 0.014, 0.010, 20,
              u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
        _ring(frame, (side * 0.044, eye_y - 0.006, eye_z), 0.036, 0.022, 0.009, 0.007, 16,
              u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
        # Frame screws, and the vent slot at the outer corner.
        for index in range(2):
            _bolt(frame, (side * 0.084, eye_y + 0.018 + index * 0.036, eye_z + 0.028),
                  (0.0, 0.0, 1.0), 0.005, 0.004)
        rounded_box(frame, (side * 0.076, eye_y, eye_z - 0.026), (0.020, 0.028, 0.006), 0.002)
    # Bridge over the nose, with its own strap and pad.
    _strap(frame, [(-0.026, eye_y, eye_z + 0.004), (0.0, eye_y - 0.010, eye_z + 0.010),
                   (0.026, eye_y, eye_z + 0.004)], 0.026, 0.011,
           width_axis=(0.0, 1.0, 0.0))
    rounded_box(frame, (0.0, eye_y - 0.018, eye_z + 0.002), (0.036, 0.022, 0.018), 0.005)
    # Temples running back from the frame to the strap.
    for side in (-1.0, 1.0):
        _strap(frame, [(side * 0.082, -0.092, eye_z + 0.024), (side * 0.098, -0.048, eye_z + 0.018),
                       (side * 0.100, -0.004, eye_z - 0.014)], 0.014, 0.007,
               width_axis=(0.0, 1.0, 0.0))
    # Strap round the helmet. The shell widens as it rises, so the strap is set
    # out to the widest section it crosses (about 0.118 x 0.126) rather than the
    # rim's, which would leave it buried inside the shell.
    _ring(frame, (0.0, -0.006, 0.004), 0.124, 0.131, 0.016, 0.007, 30,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    # Adjuster: a sliding buckle on the left temple with its own strap tail.
    rounded_box(frame, (-0.108, -0.024, eye_z + 0.010), (0.026, 0.034, 0.022), 0.005)
    _bolt(frame, (-0.118, -0.024, eye_z + 0.010), (-1.0, 0.0, 0.0), 0.006, 0.005)
    _strap(frame, [(-0.108, -0.040, eye_z + 0.004), (-0.126, -0.006, eye_z - 0.014),
                   (-0.126, 0.022, eye_z - 0.026)], 0.010, 0.004,
           width_axis=(0.0, 0.0, 1.0))
    _stitch(frame, (-0.128, -0.044, eye_z), (-0.128, -0.010, eye_z - 0.016),
            5, 0.004, 0.003, (-1.0, 0.0, 0.0))
    # Rear buckle: the clasp that closes the strap behind the helmet, on the
    # nape skirt where the strap actually runs.
    rounded_box(frame, (0.0, -0.004, -0.104), (0.054, 0.032, 0.022), 0.006)
    box(frame, (0.0, -0.004, -0.118), (0.036, 0.014, 0.010))
    for side in (-1.0, 1.0):
        _strap(frame, [(side * 0.028, -0.004, -0.100), (side * 0.088, -0.004, -0.078)],
               0.012, 0.006, width_axis=(0.0, 1.0, 0.0))
        _bolt(frame, (side * 0.022, -0.004, -0.120), (0.0, 0.0, -1.0), 0.005, 0.004)
    # Retention strap over the helmet crown, which stops the goggles riding up.
    _strap(frame, [(-0.022, -0.002, 0.138), (0.0, 0.030, 0.132), (0.022, -0.002, 0.138)],
           0.012, 0.004, width_axis=(0.0, 1.0, 0.0))
    parts = [("goggles", "ds_gear", frame)]
    lens = Builder()
    for side in (-1.0, 1.0):
        # A domed pane set into the frame opening, so its edge is hidden by the
        # rim instead of cutting through it.
        _dome(lens, (side * 0.044, eye_y - 0.008, eye_z), 0.034, 0.021, 0.014,
              (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (side * 0.1, -1.0, 0.0), steps=3)
    parts.append(("goggle_lens", "ds_glass", lens))
    return parts


def build_headband():
    """Team-coloured helmet band with its strobing and ident patches.

    A band sits round the shell's base, over the brow and around the nape - the
    widest part of the shell, just above its rim. The `headband` pivot is at
    head-local y = 0.04, so the geometry is placed that far below it to land on
    that section rather than on the crown, where a band would read as a halo.
    """
    band = Builder()
    # The band itself, sitting just proud of the shell, over a narrower backing.
    _ring(band, (0.0, -0.088, 0.002), 0.118, 0.125, 0.020, 0.007, 30,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    _ring(band, (0.0, -0.088, 0.002), 0.122, 0.129, 0.009, 0.005, 30,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
    # Strobe housing at the ten o'clock position, with its lens and its switch.
    rounded_box(band, (-0.081, -0.088, 0.092), (0.030, 0.034, 0.018), 0.005)
    _dome(band, (-0.087, -0.088, 0.102), 0.011, 0.011, 0.008, (0.0, 1.0, 0.0),
          (0.0, 0.0, 1.0), (-0.3, 0.0, 1.0), steps=2, corner_segments=3)
    rounded_box(band, (-0.073, -0.106, 0.094), (0.017, 0.011, 0.010), 0.003)
    # IR ident patch at the rear: the cat-eye pair, its backing and stitching.
    for side in (-1.0, 1.0):
        _dome(band, (side * 0.020, -0.088, -0.116), 0.015, 0.017, 0.008,
              (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0), steps=2)
    rounded_box(band, (0.0, -0.088, -0.122), (0.076, 0.046, 0.010), 0.004)
    _stitch(band, (-0.036, -0.110, -0.116), (0.036, -0.110, -0.116), 6, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    # Blood-type / name panel on the right, and two keepers holding the band.
    rounded_box(band, (0.086, -0.088, 0.080), (0.038, 0.026, 0.014), 0.004)
    _stitch(band, (0.069, -0.088, 0.088), (0.103, -0.088, 0.088), 5, 0.004, 0.0025,
            (0.3, 0.0, 1.0))
    for side in (-1.0, 1.0):
        _ring(band, (side * 0.028, -0.088, 0.118), 0.019, 0.019, 0.006, 0.005, 12,
              u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=6)
    return [("band", "ds_team", band)]


def build_patch():
    """Chest team patch and the rank tab on the front plate."""
    patch = Builder()
    slab(patch, 0.026, 0.018, 0.005, 0.180, 0.192, origin=(-0.108, 0.536, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0), corner_segments=3)
    _ring(patch, (-0.108, 0.536, 0.186), 0.028, 0.020, 0.003, 0.004, 14,
          u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))
    rounded_box(patch, (-0.108, 0.536, 0.174), (0.056, 0.040, 0.006), 0.002)
    _stitch(patch, (-0.130, 0.518, 0.190), (-0.086, 0.518, 0.190), 6, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    # Rank tab: a smaller panel above the admin pouch, level with the top row.
    slab(patch, 0.022, 0.013, 0.004, 0.180, 0.190, origin=(0.104, 0.556, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0), corner_segments=3)
    _stitch(patch, (0.086, 0.544, 0.190), (0.122, 0.544, 0.190), 5, 0.004, 0.0025,
            (0.0, 0.0, 1.0))
    rounded_box(patch, (0.104, 0.556, 0.176), (0.048, 0.030, 0.006), 0.002)
    return [("patch", "ds_team", patch)]


# --------------------------------------------------------------------------
# Arms. One rigid group per pivot, hanging down from hips-local y = +0.5, so
# `animate_human`'s X/Z rotations swing the whole arm from the shoulder.
#
# Authored for the right arm in pivot-local space and reflected for the left, so
# the shoulder patch, elbow pad and thumb land outboard and inboard correctly on
# both sides. `+Z` is forward and the elbow points backwards.
# --------------------------------------------------------------------------

def build_arm(side):
    arm = Builder()
    # Deltoid. The shoulder joint at arm-local 0 sits about 0.14 m below the
    # acromion, so the deltoid has to reach +0.135 to meet the torso's shoulder
    # and blend into it. A deltoid that stops at the joint leaves its flat top
    # cap exposed beside the shoulder, which reads as a block bolted on.
    _stacked(arm, [
        (0.135, 0.030, 0.032, 0.004, -0.18),
        (0.114, 0.054, 0.058, 0.004, -0.14),
        (0.082, 0.076, 0.080, 0.002, -0.07),
        (0.044, 0.086, 0.090, 0.000, 0.00),
        (0.004, 0.090, 0.094, 0.000, 0.04),
        (-0.040, 0.084, 0.088, 0.002, 0.06),
        (-0.078, 0.072, 0.076, 0.004, 0.08),
    ], 20, cap_end=False)
    # Upper arm, elbow, forearm and wrist.
    tube(arm, (0.0, -0.070, 0.002), (0.0, -0.288, 0.006), 0.060, 20, radius_end=0.052, steps=4)
    _stacked(arm, [
        (-0.284, 0.052, 0.056, 0.006, 0.03),
        (-0.310, 0.056, 0.060, 0.000, 0.00),
        (-0.336, 0.052, 0.056, 0.006, -0.03),
    ], 20)
    tube(arm, (0.0, -0.330, 0.004), (0.0, -0.568, 0.008), 0.052, 20, radius_end=0.044, steps=4)
    tube(arm, (0.0, -0.560, 0.008), (0.0, -0.610, 0.010), 0.044, 16, radius_end=0.040, steps=2)
    # Sleeve cuff, its seam, and the folds that build up in front of the elbow.
    _ring(arm, (0.0, -0.548, 0.008), 0.050, 0.050, 0.012, 0.006, 16,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    _stitch(arm, (0.030, -0.548, 0.040), (-0.030, -0.548, 0.040), 6, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    for index in range(3):
        x = -0.030 + index * 0.030
        _crease(arm, (x, -0.336, 0.048), (x, -0.284, 0.052), 0.006, 0.005, (0.0, 0.0, 1.0))
        _crease(arm, (x, -0.360, 0.040), (x, -0.330, 0.048), 0.005, 0.004, (0.0, 0.0, 1.0))
    # Armpit folds where the deltoid meets the torso.
    for index in range(2):
        _crease(arm, (-0.058 + index * 0.030, -0.030 - index * 0.020, -0.062),
                (-0.040 + index * 0.030, -0.084 - index * 0.020, -0.050),
                0.006, 0.005, (0.0, 0.0, -1.0))
    # Shoulder patch, worn on the outer face of the deltoid.
    slab(arm, 0.032, 0.034, 0.008, 0.074, 0.088, origin=(0.0, -0.010, 0.0),
         u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), w=(1.0, 0.0, 0.0), corner_segments=3)
    _ring(arm, (0.080, -0.010, 0.0), 0.034, 0.036, 0.004, 0.005, 16,
          u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0))
    _stitch(arm, (0.082, -0.038, 0.030), (0.082, -0.038, -0.030), 6, 0.004, 0.003,
            (1.0, 0.0, 0.0))
    parts = [("left_arm" if side < 0.0 else "right_arm", "ds_uniform", arm)]

    # Elbow pad: a cup over the point of the elbow with its own two straps.
    gear = Builder()
    rounded_box(gear, (0.0, -0.312, -0.042), (0.086, 0.070, 0.052), 0.018, corner_segments=3)
    _dome(gear, (0.0, -0.312, -0.070), 0.036, 0.030, 0.014, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
          (0.0, 0.0, -1.0))
    for index in range(2):
        y = -0.286 - index * 0.052
        _strap(gear, [(-0.048, y, -0.020), (0.0, y - 0.006, -0.006), (0.048, y, -0.020)],
               0.010, 0.004, width_axis=(0.0, 1.0, 0.0))
        rounded_box(gear, (0.040, y - 0.004, -0.014), (0.020, 0.020, 0.014), 0.004)
    _stitch(gear, (-0.030, -0.286, -0.062), (0.030, -0.286, -0.062), 6, 0.004, 0.003,
            (0.0, 0.0, -1.0))
    parts.append(("left_arm_pad" if side < 0.0 else "right_arm_pad", "ds_gear", gear))

    # Gloved hand: separated fingers and thumb, two segments each, curled.
    glove = Builder()
    _stacked(glove, [
        (-0.606, 0.038, 0.042, 0.010, 0.02),
        (-0.634, 0.042, 0.048, 0.006, 0.00),
        (-0.664, 0.044, 0.052, 0.002, -0.02),
        (-0.694, 0.042, 0.050, 0.000, -0.04),
    ], 16)
    # Knuckle bar, then the four fingers arrayed front to back.
    rounded_box(glove, (-0.006, -0.700, 0.0), (0.038, 0.030, 0.100), 0.010, corner_segments=3)
    for index in range(4):
        z = -0.036 + index * 0.024
        radius = [0.0115, 0.0110, 0.0105, 0.0092][index]
        base = (0.0, -0.712, z)
        joint = (-0.008, -0.752, z + 0.004)
        tip = (-0.032, -0.766, z + 0.008)
        _route(glove, [base, joint, tip], [radius, radius * 0.95, radius * 0.86], 10)
        _ring(glove, (-0.004, -0.714, z), radius + 0.002, radius + 0.002, 0.006, 0.004, 10,
              u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=6)
        _dome(glove, tip, radius * 0.9, radius * 0.9, radius * 0.9, (1.0, 0.0, 0.0),
              (0.0, 0.0, 1.0), (-0.9, -0.3, 0.2), steps=2, corner_segments=3)
        _stitch(glove, (-0.020, -0.734, z), (-0.020, -0.746, z), 3, 0.003, 0.0025,
                (-1.0, 0.0, 0.0))
    # Thumb: two segments, splayed across the front of the hand.
    _route(glove, [(0.006, -0.664, 0.046), (-0.006, -0.700, 0.060), (-0.024, -0.716, 0.056)],
           [0.0140, 0.0125, 0.0105], 12)
    _ring(glove, (0.004, -0.666, 0.046), 0.015, 0.015, 0.006, 0.004, 10,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=6)
    # Palm pad, finger seams and the glove's velcro cuff.
    _dome(glove, (-0.030, -0.666, 0.006), 0.024, 0.030, 0.008, (0.0, 1.0, 0.0),
          (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0), steps=2)
    rounded_box(glove, (-0.040, -0.668, 0.006), (0.010, 0.036, 0.058), 0.004)
    _strap(glove, [(-0.042, -0.640, 0.030), (-0.042, -0.646, 0.0), (-0.042, -0.640, -0.030)],
           0.010, 0.004, width_axis=(0.0, 1.0, 0.0))
    rounded_box(glove, (-0.046, -0.642, 0.006), (0.012, 0.026, 0.020), 0.004)
    _ring(glove, (0.0, -0.610, 0.010), 0.046, 0.048, 0.010, 0.006, 16,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    parts.append(("left_arm_glove" if side < 0.0 else "right_arm_glove", "ds_glove", glove))
    return _sided(parts, side)


# --------------------------------------------------------------------------
# Legs. One rigid group per pivot at hips-local y = 0, so the whole leg swings
# from the hip. Authored for the right leg and reflected for the left.
# --------------------------------------------------------------------------

def build_leg(side):
    leg = Builder()
    # Hip and upper thigh.
    _stacked(leg, [
        (0.030, 0.094, 0.100, 0.002, -0.04),
        (-0.020, 0.098, 0.104, 0.004, -0.02),
        (-0.070, 0.094, 0.100, 0.006, 0.00),
    ], 22)
    # Thigh. The pivots are 13 cm apart while a circular thigh is 9.4 cm wide, so
    # the two inner faces would sit 3.6 cm apart at the hem and diverge straight
    # into a see-through slot. A standing thigh is D-shaped rather than round: its
    # inner face is nearly flat, and two standing thighs touch from the crotch to
    # about mid-thigh before parting. The `x_offset` biases each station so the
    # inner face stays in contact down to y = -0.20 and then withdraws, giving the
    # natural parting below mid-thigh. Authoring the thigh as this section is what
    # closes the slot; a separate inboard bulge cannot, because it would sit inside
    # the round thigh and add no silhouette.
    _stacked(leg, [
        (-0.050, 0.104, 0.094, 0.004, -0.02, -0.011),
        (-0.110, 0.103, 0.092, 0.006, 0.02, -0.013),
        (-0.170, 0.102, 0.090, 0.008, 0.05, -0.013),
        (-0.220, 0.101, 0.089, 0.010, 0.07, -0.011),
        (-0.270, 0.099, 0.088, 0.010, 0.08, -0.001),
        (-0.320, 0.094, 0.086, 0.010, 0.09, -0.002),
        (-0.370, 0.090, 0.084, 0.010, 0.10, 0.008),
        (-0.410, 0.088, 0.080, 0.010, 0.10, 0.012),
    ], 22, cap_start=False, cap_end=False)
    # Knee block: narrower than the thigh, deeper front to back.
    _stacked(leg, [
        (-0.376, 0.080, 0.086, 0.010, 0.10),
        (-0.412, 0.076, 0.084, 0.012, 0.06),
        (-0.448, 0.078, 0.088, 0.008, 0.00),
        (-0.480, 0.082, 0.092, 0.004, -0.06),
    ], 22)
    # Calf, including the muscle bulging behind it, down to the ankle.
    tube(leg, (0.0, -0.470, 0.008), (0.0, -0.700, 0.014), 0.082, 22, radius_end=0.054, steps=5)
    _stacked(leg, [
        (-0.500, 0.070, 0.062, -0.030, 0.0),
        (-0.556, 0.074, 0.066, -0.036, 0.0),
        (-0.612, 0.070, 0.060, -0.032, 0.0),
        (-0.664, 0.058, 0.046, -0.020, 0.0),
    ], 20, cap_start=False, cap_end=False)
    # Trousers bloused over the boot: the cuff hangs just short of the boot's own
    # collar, so the two volumes overlap by a centimetre rather than a hand-span.
    _ring(leg, (0.0, -0.700, 0.012), 0.066, 0.070, 0.014, 0.008, 20,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    _ring(leg, (0.0, -0.726, 0.012), 0.058, 0.062, 0.010, 0.006, 20,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=8)
    # Cloth folds: hip, knee and ankle, which are the three places a uniform
    # actually bunches on a standing soldier.
    for index in range(3):
        y = -0.120 - index * 0.036
        _crease(leg, (-0.060 + index * 0.012, y, 0.086), (0.060 - index * 0.012, y - 0.012, 0.086),
                0.007, 0.006, (0.0, 0.0, 1.0))
        _crease(leg, (-0.056, y - 0.020, -0.090), (0.056, y - 0.030, -0.090),
                0.007, 0.005, (0.0, 0.0, -1.0))
    for index in range(3):
        x = -0.044 + index * 0.044
        _crease(leg, (x, -0.330, 0.076), (x, -0.284, 0.084), 0.006, 0.005, (0.0, 0.0, 1.0))
        _crease(leg, (x, -0.360, -0.076), (x, -0.320, -0.086), 0.006, 0.005, (0.0, 0.0, -1.0))
    for index in range(3):
        y = -0.628 - index * 0.024
        _crease(leg, (-0.050 + index * 0.008, y, 0.052), (0.050 - index * 0.008, y - 0.010, 0.056),
                0.006, 0.005, (0.0, 0.0, 1.0))
    _stitch(leg, (0.076, -0.100, 0.030), (0.070, -0.660, 0.030), 18, 0.004, 0.003,
            (1.0, 0.0, 0.0))
    _stitch(leg, (-0.076, -0.100, 0.030), (0.076, -0.100, 0.030), 8, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    parts = [("left_leg" if side < 0.0 else "right_leg", "ds_uniform", leg)]

    # Knee pad and thigh pocket: the padded gear carried on the leg.
    gear = Builder()
    rounded_box(gear, (0.0, -0.446, 0.070), (0.116, 0.116, 0.064), 0.024, corner_segments=4)
    _dome(gear, (0.0, -0.446, 0.100), 0.046, 0.046, 0.018, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
          (0.0, 0.0, 1.0))
    for index in range(2):
        y = -0.404 - index * 0.086
        _strap(gear, [(-0.058, y, 0.030), (0.0, y - 0.006, 0.046), (0.058, y, 0.030)],
               0.012, 0.005, width_axis=(0.0, 1.0, 0.0))
        rounded_box(gear, (0.050, y - 0.004, 0.034), (0.024, 0.024, 0.018), 0.005)
    _stitch(gear, (-0.044, -0.492, 0.078), (0.044, -0.492, 0.078), 8, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    for side_bolt in (-1.0, 1.0):
        _bolt(gear, (side_bolt * 0.048, -0.446, 0.102), (0.0, 0.0, 1.0), 0.007, 0.006)
    # Cargo pocket on the outer thigh, with its flap and retention strap.
    rounded_box(gear, (0.072, -0.246, 0.042), (0.062, 0.112, 0.070), 0.012, corner_segments=3)
    rounded_box(gear, (0.074, -0.204, 0.046), (0.064, 0.030, 0.074), 0.012, corner_segments=3)
    _strap(gear, [(0.100, -0.208, 0.040), (0.104, -0.246, 0.032), (0.100, -0.288, 0.038)],
           0.012, 0.004, width_axis=(0.0, 1.0, 0.0))
    rounded_box(gear, (0.112, -0.240, 0.036), (0.014, 0.026, 0.018), 0.004)
    _ring(gear, (0.072, -0.300, 0.040), 0.030, 0.034, 0.010, 0.006, 16,
          u=(0.0, 1.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    _stitch(gear, (0.104, -0.250, 0.010), (0.104, -0.250, 0.074), 6, 0.004, 0.003,
            (1.0, 0.0, 0.0))
    parts.append(("left_leg_pad" if side < 0.0 else "right_leg_pad", "ds_gear", gear))

    # Boot: cuff, upper, foot, toe cap, heel counter, lugged sole and laces.
    # Laid out from the ground up: the leg pivot sits at world y = 0.9 and the
    # map floor is world y = 0, so the tread lugs must bottom out at leg-local
    # -0.900. Both the ported model and the first procedural pass sank the feet
    # below the floor; the lugs are now the contact surface and they rest on it.
    boot = Builder()
    _ring(boot, (0.0, -0.725, 0.014), 0.062, 0.066, 0.014, 0.008, 18,
          u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), profile_segments=0, corner_segments=3)
    rounded_box(boot, (0.0, -0.769, 0.016), (0.106, 0.092, 0.128), 0.022, corner_segments=3)
    rounded_box(boot, (0.0, -0.813, 0.040), (0.112, 0.062, 0.204), 0.024, corner_segments=4)
    # Heel counter and the padded collar behind the ankle.
    rounded_box(boot, (0.0, -0.787, -0.048), (0.100, 0.070, 0.070), 0.022, corner_segments=3)
    _dome(boot, (0.0, -0.781, -0.082), 0.044, 0.034, 0.014, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
          (0.0, 0.0, -1.0))
    # Toe cap: the separate reinforced volume at the front of the foot.
    _dome(boot, (0.0, -0.817, 0.128), 0.050, 0.032, 0.024, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
          (0.0, 0.0, 1.0))
    _stitch(boot, (-0.048, -0.819, 0.106), (0.048, -0.819, 0.106), 8, 0.004, 0.003,
            (0.0, -0.4, 1.0))
    # Sole: midsole over the tread slab, whose underside carries the lugs.
    rounded_box(boot, (0.0, -0.839, 0.030), (0.116, 0.026, 0.226), 0.010, corner_segments=3)
    rounded_box(boot, (0.0, -0.867, 0.026), (0.112, 0.048, 0.220), 0.008, corner_segments=3)
    # Heel block, raised under the arch at the back of the tread.
    rounded_box(boot, (0.0, -0.855, -0.066), (0.110, 0.052, 0.076), 0.014, corner_segments=3)
    # Lugs: proud tread blocks across the sole, resting on the floor at -0.900.
    for row in range(6):
        z = -0.070 + row * 0.030
        span = 0.100 if row > 0 else 0.074
        for column in range(4):
            x = (column - 1.5) * (span / 4.0)
            box(boot, (x, -0.892, z), (span / 4.0 * 0.70, 0.016, 0.017))
    for row in range(2):
        z = -0.062 + row * 0.026
        for side_lug in (-1.0, 1.0):
            box(boot, (side_lug * 0.050, -0.879, z), (0.016, 0.026, 0.020))
    # Laces: crossings with their eyelets and the tongue under them.
    rounded_box(boot, (0.0, -0.791, 0.066), (0.074, 0.126, 0.032), 0.012, corner_segments=3)
    for index in range(5):
        y = -0.743 - index * 0.024
        for side_lace in (-1.0, 1.0):
            _ring(boot, (side_lace * 0.038, y, 0.090 - index * 0.002), 0.008, 0.008,
                  0.005, 0.004, 10, u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), profile_segments=6)
        _strap(boot, [(-0.046, y + 0.010, 0.084), (0.046, y - 0.010, 0.088)],
               0.006, 0.003, width_axis=(0.0, 1.0, 0.0))
        _strap(boot, [(0.046, y + 0.010, 0.084), (-0.046, y - 0.010, 0.088)],
               0.006, 0.003, width_axis=(0.0, 1.0, 0.0))
    _strap(boot, [(-0.030, -0.861, 0.092), (0.0, -0.869, 0.100), (0.030, -0.861, 0.092)],
           0.007, 0.004, width_axis=(0.0, 1.0, 0.0))
    _stitch(boot, (-0.040, -0.749, 0.104), (0.040, -0.749, 0.104), 6, 0.004, 0.003,
            (0.0, 0.0, 1.0))
    parts.append(("left_leg_boot" if side < 0.0 else "right_leg_boot", "ds_boot", boot))
    return _sided(parts, side)


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
    attach(build_pelvis(), "hips")
    attach(build_vest(), "hips")
    attach(build_pack(), "hips")
    attach(build_patch(), "hips")
    attach(build_head(), "head")
    attach(build_helmet(), "head")
    attach(build_helmet_gear(), "head")
    attach(build_face(), "face")
    attach(build_goggles(), "face")
    attach(build_headband(), "headband")
    attach(build_arm(-1.0), "left_arm")
    attach(build_arm(1.0), "right_arm")
    attach(build_leg(-1.0), "left_leg")
    attach(build_leg(1.0), "right_leg")
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
