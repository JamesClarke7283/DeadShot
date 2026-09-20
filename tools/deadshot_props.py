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
  `streak_care_package`           `mainRotor` about Y, `tailRotor` about X - the
                                    transport helicopter that drops the crate
  `care_crate`, `care_pickup`     marker lamp geometry only; the root moves
  `rocket`, `ammo_pickup`, `weapon_drop`, `equipment_*`  no named pivots

Every builder here is a statement of structure rather than of vertices: the
detail vocabulary below (oriented boxes in arbitrary frames, revolved collars,
lofted ribbons, panel and fragmentation grids) is what puts real chamfers,
recessed panel lines and small proud features onto these shapes.
"""

from __future__ import annotations

import math

from deadshot_detail import (
    Builder, basis_from_w, box, cone, lerp3, profile_circle, profile_rounded_rect, rail,
    rounded_box, screw, sweep, swept_tube, tube, vadd, vcross, vdot, vlen, vmul, vnorm,
    vsub,
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

def body_of_revolution(builder, stations, segments=16, cap_start=True, cap_end=True):
    """`stations` is `(z, radius)` along the local Z axis.

    Stations are sorted along the local Z and the frame's `w` is taken along
    `+Z`, which makes `u x v` point along `w`; the generated quads then face
    outward for every profile, whatever order the caller listed the stations in.
    """
    frames = [((0.0, 0.0, z), vmul((1.0, 0.0, 0.0), r), vmul((0.0, 1.0, 0.0), r), (0.0, 0.0, 1.0))
              for z, r in sorted(stations)]
    sweep(builder, profile_circle(1.0, segments), frames, cap_start, cap_end)


def stacked(builder, stations, segments=16, cap_start=True, cap_end=True):
    """`stations` is `(y, radius)` along the local Y axis."""
    frames = [((0.0, y, 0.0), vmul((1.0, 0.0, 0.0), r), vmul((0.0, 0.0, 1.0), r), (0.0, 1.0, 0.0))
              for y, r in stations]
    sweep(builder, profile_circle(1.0, segments), frames, cap_start, cap_end)


# --------------------------------------------------------------------------
# Detail vocabulary.
#
# Every proud feature these assets need — rib, rivet, latch, bracket, panel,
# fragmentation block — is one of a handful of oriented solids, so the builders
# below state structure instead of vertices. `oriented_box` is the workhorse:
# `rounded_box` in an arbitrary frame, which is what puts features on curved
# casings and on faces that do not align with a world axis.
# --------------------------------------------------------------------------

def mix(a, b, t):
    return a + (b - a) * t


def radius_at(stations, y):
    """Radius of a `(y, radius)` profile at `y`, linearly interpolated."""
    if y <= stations[0][0]:
        return stations[0][1]
    if y >= stations[-1][0]:
        return stations[-1][1]
    for index in range(len(stations) - 1):
        y0, r0 = stations[index]
        y1, r1 = stations[index + 1]
        if y0 <= y <= y1:
            if y1 <= y0:
                return r1
            return mix(r0, r1, (y - y0) / (y1 - y0))
    return stations[-1][1]


def perpendicular(axis):
    """A right-handed `(u, v)` unit pair normal to `axis`: `u x v == axis`."""
    u, v, _w = basis_from_w(axis)
    return u, v


def revolve(builder, centre, axis, profile, segments=20, phase=0.0, arc=TAU, smooth=False):
    """Revolve a closed `profile` of `(radius, height)` points about `axis`.

    `profile` MUST run counter-clockwise in the `(radius, height)` plane: the
    emitted faces then point away from the axis, which is the winding
    `Builder.quad` wants. This is the primitive for every annular feature a real
    asset has — crimp rings, bearing races, base collars, pull rings, cord loops
    and nozzle bells — none of which an oriented box can express.
    """
    axis = vnorm(axis)
    u, v = perpendicular(axis)
    closed = arc >= TAU - 1e-9
    rings = segments if closed else segments + 1
    count = len(profile)
    if count < 3 or rings < 2:
        return
    ring_points = []
    ring_radials = []
    for index in range(rings):
        angle = phase + arc * index / segments
        sin_a, cos_a = math.sin(angle), math.cos(angle)
        radial = vadd(vmul(u, cos_a), vmul(v, sin_a))
        ring_radials.append(radial)
        ring_points.append([vadd(centre, vadd(vmul(radial, radius), vmul(axis, height)))
                            for radius, height in profile])
    # Analytic outward normal of the surface of revolution: `radial * dh -
    # axis * dr`, which is what makes a revolved cone read as round.
    edges = []
    for index in range(count):
        j = (index + 1) % count
        edges.append((profile[j][0] - profile[index][0], profile[j][1] - profile[index][1]))

    def normal_at(radial, edge):
        return vnorm(vsub(vmul(radial, edge[1]), vmul(axis, edge[0])))

    last = rings - 1
    for index in range(last):
        lower, upper = ring_points[index], ring_points[index + 1]
        lower_radial, upper_radial = ring_radials[index], ring_radials[index + 1]
        for k in range(count):
            j = (k + 1) % count
            if smooth:
                builder.quad(lower[k], upper[k], upper[j], lower[j],
                             normal_at(lower_radial, edges[k]),
                             normal_at(upper_radial, edges[k]),
                             normal_at(upper_radial, edges[j]),
                             normal_at(lower_radial, edges[j]))
            else:
                builder.quad(lower[k], upper[k], upper[j], lower[j])
    if closed:
        return
    # Open arc: the material sits between the two cut planes, so the start cap
    # faces the decreasing-angle side and the end cap the increasing-angle one.
    # The profile is counter-clockwise in `(radial, height)`, whose normal is
    # `+tangent`, so the start cap is that order reversed.
    first, final = ring_points[0], ring_points[-1]
    for k in range(1, count - 1):
        builder.triangle(first[0], first[k + 1], first[k])
        builder.triangle(final[0], final[k], final[k + 1])


def ring_collar(builder, start, end, outer, inner, segments=18):
    """A proud annular collar: crimp rings, bearing races, base collars."""
    axis = vsub(end, start)
    length = vlen(axis)
    if length < 1e-9 or outer <= inner:
        return
    revolve(builder, start, axis,
            [(inner, 0.0), (outer, 0.0), (outer, length), (inner, length)], segments)


def torus_arc(builder, centre, axis, radius, tube_radius, start_angle=0.0, end_angle=TAU,
              segments=18, arc_segments=8):
    """A partial torus: pull rings, wire runs, lanyards and cord loops."""
    profile = [(radius + tube_radius * math.cos(TAU * index / arc_segments),
                tube_radius * math.sin(TAU * index / arc_segments))
               for index in range(arc_segments)]
    revolve(builder, centre, axis, profile, segments,
            phase=start_angle, arc=end_angle - start_angle, smooth=True)


def oriented_box(builder, centre, u, v, w, half_u, half_v, half_w, radius=0.0015,
                 corner_segments=2):
    """Chamfered box in an arbitrary orthonormal frame.

    `u`/`v` span the profile plane and `w` is the extrusion axis, matching
    `sweep`; the axes are normalised here so callers can pass any orthogonal
    triple.
    """
    u, v, w = vnorm(u), vnorm(v), vnorm(w)
    half_u, half_v = abs(half_u), abs(half_v)
    profile = profile_rounded_rect(half_u, half_v, min(abs(radius), half_u * 0.9, half_v * 0.9),
                                   corner_segments)
    sweep(builder, profile,
          [(vadd(centre, vmul(w, -half_w)), u, v, w),
           (vadd(centre, vmul(w, half_w)), u, v, w)], True, True)


def plate(builder, points, offset):
    """A convex planar polygon extruded by `offset`, faces pointed along it."""
    centre = (0.0, 0.0, 0.0)
    for point in points:
        centre = vadd(centre, point)
    centre = vmul(centre, 1.0 / len(points))
    normal = (0.0, 0.0, 0.0)
    for index in range(len(points)):
        a = points[index]
        b = points[(index + 1) % len(points)]
        normal = vadd(normal, vcross(vsub(a, centre), vsub(b, centre)))
    if vdot(normal, offset) < 0.0:
        points = list(reversed(points))
    top = [vadd(p, vmul(offset, 0.5)) for p in points]
    bottom = [vadd(p, vmul(offset, -0.5)) for p in points]
    for index in range(1, len(points) - 1):
        builder.triangle(top[0], top[index], top[index + 1])
        builder.triangle(bottom[0], bottom[index + 1], bottom[index])
    for index in range(len(points)):
        j = (index + 1) % len(points)
        builder.quad(top[index], bottom[index], bottom[j], top[j])


def ribbon(builder, points, out, half_width, half_thickness, corner_segments=2):
    """A flat strip lofted through `points`; `out` is the outward side.

    Spoons, safety clips, slings, detonator cords and cable runs are all this
    one solid following a different path.
    """
    frames = []
    for index, point in enumerate(points):
        if index == 0:
            tangent = vsub(points[1], points[0])
        elif index == len(points) - 1:
            tangent = vsub(points[-1], points[-2])
        else:
            tangent = vsub(points[index + 1], points[index - 1])
        w = vnorm(tangent)
        u = vnorm(vcross(out, w))
        v = vnorm(vcross(w, u))
        frames.append((point, u, v, w))
    sweep(builder, profile_rounded_rect(half_width, half_thickness, 0.0012, corner_segments),
          frames, True, True)


def bolt_ring(builder, centre, axis, radius, count, bolt_radius, length, phase=0.0):
    """A circle of proud bolt heads around `axis`."""
    u, v = perpendicular(axis)
    for index in range(count):
        angle = phase + TAU * index / count
        offset = vadd(vmul(u, radius * math.cos(angle)), vmul(v, radius * math.sin(angle)))
        screw(builder, vadd(centre, offset), axis, bolt_radius, length)


def bolt_row(builder, start, end, normal, count, radius, length):
    """An evenly spaced row of proud bolt heads along a line."""
    direction = vsub(end, start)
    for index in range(count):
        centre = vadd(start, vmul(direction, (index + 1.0) / (count + 1.0)))
        screw(builder, centre, normal, radius, length)


def panel_grid(builder, centre, u, v, w, half_u, half_v, columns, rows, depth=0.004,
               fill=0.62, radius=0.002, corner_segments=3):
    """A grid of proud panels over a rectangular face, `w` being the normal.

    The clear space between panels is the recessed seam, so one call produces
    both crossing seam families on a wrapper, a crate side or a lid.
    """
    u, v, w = vnorm(u), vnorm(v), vnorm(w)
    cell_u = 2.0 * half_u / columns
    cell_v = 2.0 * half_v / rows
    for column in range(columns):
        for row in range(rows):
            cu = (column + 0.5) * cell_u - half_u
            cv = (row + 0.5) * cell_v - half_v
            position = vadd(centre, vadd(vadd(vmul(u, cu), vmul(v, cv)), vmul(w, depth * 0.5)))
            oriented_box(builder, position, u, v, w, cell_u * 0.5 * fill,
                         cell_v * 0.5 * fill, depth * 0.5, radius, corner_segments)


def curved_grid(builder, stations, columns, rows, y_low, y_high, depth=0.0035, fill=0.6,
                radius_offset=0.0, corner_segments=2):
    """Proud blocks over a `stacked` casing profile: the fragmentation matrix.

    Blocks sit at the centre of each `columns` x `rows` cell of the casing, so
    the clear space between them reads as two orthogonal families of recessed
    grooves — the dominant visual on a fragmentation body.
    """
    for row in range(rows):
        y0 = mix(y_low, y_high, row / rows)
        y1 = mix(y_low, y_high, (row + 1) / rows)
        y = 0.5 * (y0 + y1)
        radius = radius_at(stations, y) + radius_offset
        cell_v = y1 - y0
        cell_angle = TAU / columns
        for column in range(columns):
            angle = column * cell_angle + cell_angle * 0.5
            cos_a, sin_a = math.cos(angle), math.sin(angle)
            oriented_box(builder, (radius * cos_a, y, radius * sin_a),
                         (-sin_a, 0.0, cos_a), (0.0, 1.0, 0.0), (cos_a, 0.0, sin_a),
                         radius * cell_angle * 0.5 * fill, cell_v * 0.5 * fill,
                         depth * 0.5, 0.0012, corner_segments)


def hole_row(builder, stations, y, count, phase, hole_radius, sink=0.008):
    """A drilled port through a `stacked` casing at height `y`.

    `sink` is how deep the recess starts, so the rim ring reads as a chamfered
    drill entry rather than a bump.
    """
    radius = radius_at(stations, y)
    step = TAU / count
    for index in range(count):
        angle = phase + index * step
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        tube(builder, (cos_a * (radius - sink), y, sin_a * (radius - sink)),
             (cos_a * (radius + 0.0015), y, sin_a * (radius + 0.0015)), hole_radius, 10,
             cap_start=False, cap_end=False)
        ring_collar(builder, (cos_a * (radius - 0.0010), y, sin_a * (radius - 0.0010)),
                    (cos_a * (radius + 0.0018), y, sin_a * (radius + 0.0018)),
                    hole_radius * 1.42, hole_radius, 12)


def twisted_blade(builder, start, end, half_chord, half_thickness, twist,
                  root_scale=0.55, tip_scale=0.82, stations=6, corner_segments=3,
                  mid_bulge=1.0):
    """A rotor blade: a chord-tapered loft with real washout twist about the span."""
    axis = vsub(end, start)
    u, v, w = basis_from_w(axis)
    frames = []
    for index in range(stations + 1):
        t = index / stations
        angle = twist * t
        scale = mix(root_scale, tip_scale, t)
        if mid_bulge != 1.0:
            scale *= 1.0 + (mid_bulge - 1.0) * math.sin(math.pi * t)
        chord = vmul(vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle))),
                     half_chord * scale)
        thick = vmul(vadd(vmul(u, -math.sin(angle)), vmul(v, math.cos(angle))),
                     half_thickness * scale)
        frames.append((lerp3(start, end, t), chord, thick, w))
    sweep(builder, profile_rounded_rect(1.0, 1.0, 0.5, corner_segments), frames, True, True)


def wing_loft(builder, side, plan, corner_segments=4):
    """A lofted wing panel: `plan` is `(span, mid_z, chord, half_thickness)`."""
    frames = [((side * span, 0.0, mid_z), vmul((0.0, 0.0, 1.0), chord * 0.5),
               vmul((0.0, 1.0, 0.0), half_thickness), (side, 0.0, 0.0))
              for span, mid_z, chord, half_thickness in plan]
    sweep(builder, profile_rounded_rect(1.0, 1.0, 0.55, corner_segments), frames, True, True)


def wheel(builder, centre, axis, tyre_radius, width, treads=16, spokes=5, rim_scale=0.58):
    """A road wheel: tyre, shoulder rings, tread blocks, rim, spokes and hub."""
    axis = vnorm(axis)
    half_width = width * 0.5
    inner = tyre_radius * rim_scale
    u, v = perpendicular(axis)
    tube(builder, vadd(centre, vmul(axis, -half_width)), vadd(centre, vmul(axis, half_width)),
         tyre_radius, 20, cap_start=False, cap_end=False, steps=2)
    for sign in (-1.0, 1.0):
        ring_collar(builder, vadd(centre, vmul(axis, sign * half_width * 0.78)),
                    vadd(centre, vmul(axis, sign * half_width)), tyre_radius * 0.99,
                    tyre_radius * 0.80, 20)
    for index in range(treads):
        angle = index * TAU / treads
        radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
        oriented_box(builder, vadd(centre, vmul(radial, tyre_radius * 0.99)), radial, axis,
                     vcross(radial, axis), 0.0045, width * 0.40, 0.011, 0.0015, 2)
    tube(builder, vadd(centre, vmul(axis, -half_width * 0.55)),
         vadd(centre, vmul(axis, half_width * 0.55)), inner * 0.94, 18, cap_start=False,
         cap_end=False, steps=1)
    for index in range(spokes):
        angle = index * TAU / spokes
        radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
        oriented_box(builder, vadd(centre, vmul(radial, inner * 0.48)), axis, radial,
                     vcross(radial, axis), half_width * 0.30, inner * 0.44, 0.006, 0.0015, 2)
    ring_collar(builder, vadd(centre, vmul(axis, -half_width * 0.62)),
                vadd(centre, vmul(axis, half_width * 0.62)), inner * 0.34, inner * 0.20, 14)
    bolt_ring(builder, vadd(centre, vmul(axis, half_width * 0.64)), axis, inner * 0.42, 5,
              0.0055, 0.006)

# --------------------------------------------------------------------------
# Scorestreaks.
# --------------------------------------------------------------------------


def build_uav_hull():
    """Blended-wing reconnaissance drone: airframe, spar, sensors, antennae."""
    hull = Builder()
    # Centre body: seven stations carrying a real thickness distribution so the
    # planform reads as blended rather than a fuselage with wings bolted on.
    body_stations = [(0.0, 0.030, 0.024), (0.18, 0.056, 0.042), (0.40, 0.064, 0.046),
                     (0.62, 0.062, 0.046), (0.80, 0.048, 0.036), (0.92, 0.030, 0.022),
                     (1.0, 0.016, 0.013)]
    sweep(hull, profile_rounded_rect(1.0, 1.0, 0.5, 5),
          [((0.0, 0.0, -0.30 + t * 0.60), vmul((1.0, 0.0, 0.0), half_w),
            vmul((0.0, 1.0, 0.0), half_h), (0.0, 0.0, 1.0))
           for t, half_w, half_h in body_stations], True, True)
    # Ring seams split the body into nose, payload bay and tail sections.
    for z, half_w, half_h in ((-0.250, 0.046, 0.034), (-0.145, 0.060, 0.044),
                              (0.020, 0.064, 0.047), (0.170, 0.056, 0.041),
                              (0.268, 0.030, 0.021)):
        sweep(hull, profile_rounded_rect(1.0, 1.0, 0.5, 5),
              [((0.0, 0.0, z - 0.0035), vmul((1.0, 0.0, 0.0), half_w * 1.04),
                vmul((0.0, 1.0, 0.0), half_h * 1.04), (0.0, 0.0, 1.0)),
               ((0.0, 0.0, z + 0.0035), vmul((1.0, 0.0, 0.0), half_w * 1.04),
                vmul((0.0, 1.0, 0.0), half_h * 1.04), (0.0, 0.0, 1.0))], True, True)
    # Dorsal spine panel line, the deck's skin panels and the rivet rows beside
    # them.
    oriented_box(hull, (0.0, 0.045, 0.020), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.290, 0.016, 0.0035, 0.001, 2)
    panel_grid(hull, (0.0, 0.046, 0.020), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
               0.290, 0.044, 5, 2, 0.0035, 0.62, 0.0022, 3)
    for side in (-1.0, 1.0):
        panel_grid(hull, (side * 0.056, 0.004, 0.020), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.270, 0.032, 4, 2, 0.0035, 0.62, 0.0022, 3)
        bolt_row(hull, (side * 0.058, 0.036, -0.280), (side * 0.030, 0.040, 0.290),
                 (side, 0.0, 0.0), 14, 0.0030, 0.0032)
        bolt_row(hull, (side * 0.050, -0.036, -0.250), (side * 0.058, -0.030, 0.250),
                 (side, 0.0, 0.0), 12, 0.0030, 0.0032)
    for side in (-1.0, 1.0):
        bolt_row(hull, (side * 0.044, 0.038, -0.255), (side * 0.044, 0.042, 0.255),
                 (0.0, 1.0, 0.0), 18, 0.0035, 0.004)
        bolt_row(hull, (side * 0.058, -0.030, -0.200), (side * 0.058, -0.030, 0.200),
                 (0.0, -1.0, 0.0), 12, 0.0035, 0.004)
    # Wing: one loft per side, tapering and thinning outboard.
    plan = ((0.030, -0.020, 0.400, 0.026), (0.150, -0.010, 0.340, 0.021),
            (0.290, 0.005, 0.280, 0.016), (0.420, 0.020, 0.220, 0.011),
            (0.520, 0.036, 0.150, 0.007))
    for side in (-1.0, 1.0):
        wing_loft(hull, side, plan)
        # Spar cap, then a full rib set down the span.
        oriented_box(hull, (side * 0.290, 0.020, -0.030), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.055, 0.245, 0.006, 0.0015, 2)
        # The wing skin: a spanwise and chordwise panel grid on both surfaces,
        # following the taper, plus a fastener at every panel corner. This is
        # what a real wing surface reads as up close.
        for index in range(11):
            t = index / 10.0
            span = mix(0.040, 0.515, t)
            chord = mix(0.400, 0.155, t)
            mid = mix(-0.018, 0.036, t)
            thickness = mix(0.025, 0.007, t)
            for surface in (-1.0, 1.0):
                height = surface * thickness
                for cell in range(4):
                    cell_z = mid + (cell - 1.5) * chord * 0.24
                    oriented_box(hull, (side * span, height, cell_z), (0.0, 0.0, 1.0),
                                 (0.0, surface, 0.0), (side, 0.0, 0.0),
                                 0.0125, chord * 0.104, 0.0035, 0.0012, 2)
                bolt_row(hull, (side * span, height * 1.04, mid - chord * 0.44),
                         (side * span, height * 1.04, mid + chord * 0.44),
                         (0.0, surface, 0.0), 6, 0.0026, 0.0028)
            # Rib web inside the skin at every other station.
            if index % 2 == 0:
                oriented_box(hull, (side * span, mid * 0.02, mid + chord * 0.30),
                             (0.0, 0.0, 1.0), (side, 0.0, 0.0), (0.0, 1.0, 0.0),
                             0.012, chord * 0.30, 0.005, 0.0012, 2)
                oriented_box(hull, (side * span, -mid * 0.02 - 0.021, mid + chord * 0.28),
                             (0.0, 0.0, 1.0), (side, 0.0, 0.0), (0.0, -1.0, 0.0),
                             0.010, chord * 0.28, 0.004, 0.0012, 2)
        elevon = [(side * 0.140, 0.0, -0.150), (side * 0.510, 0.0, 0.020),
                  (side * 0.510, 0.0, 0.070), (side * 0.140, 0.0, -0.080)]
        plate(hull, elevon, (0.0, 0.012, 0.0))
        # Wingtip winglet, its bolts and the navigation light lens.
        plate(hull, [(side * 0.500, 0.010, 0.020), (side * 0.540, 0.060, 0.030),
                     (side * 0.540, 0.060, 0.010), (side * 0.500, 0.010, 0.000)],
              (side * 0.012, 0.0, 0.0))
        bolt_row(hull, (side * 0.520, 0.045, 0.010), (side * 0.520, 0.045, 0.090),
                 (side, 0.0, 0.0), 6, 0.0028, 0.003)
        tube(hull, (side * 0.552, 0.030, 0.055), (side * 0.560, 0.030, 0.055), 0.008, 12)
        # Underwing hardpoint: pylon, ejector lugs and mounting bolts.
        oriented_box(hull, (side * 0.300, -0.045, -0.020), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, -1.0, 0.0), 0.070, 0.024, 0.028, 0.002, 2)
        bolt_ring(hull, (side * 0.300, -0.073, -0.020), (0.0, -1.0, 0.0), 0.018, 4,
                  0.0035, 0.004)
    # Sensor turret under the nose: ball, mount collar, window and rim bolts.
    body_of_revolution(hull, [(-0.296, 0.016), (-0.318, 0.030), (-0.344, 0.034),
                              (-0.368, 0.030), (-0.382, 0.018)], segments=20)
    ring_collar(hull, (0.0, -0.006, -0.300), (0.0, -0.006, -0.314), 0.034, 0.026, 18)
    tube(hull, (0.0, -0.008, -0.376), (0.0, -0.008, -0.392), 0.024, 16, radius_end=0.021)
    bolt_ring(hull, (0.0, -0.008, -0.336), (0.0, 0.0, -1.0), 0.030, 6, 0.0032, 0.0035)
    # Antennae: a blade with its insulator base, and a whip with a ball tip.
    plate(hull, [(-0.012, 0.056, 0.230), (0.012, 0.056, 0.230),
                 (0.008, 0.104, 0.268), (-0.008, 0.104, 0.268)], (0.0, 0.0, 0.004))
    oriented_box(hull, (0.0, 0.054, 0.230), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.024, 0.016, 0.006, 0.002, 2)
    swept_tube(hull, [(-0.030, 0.040, 0.150), (-0.038, 0.075, 0.170), (-0.044, 0.108, 0.182)],
               0.0035, 8)
    tube(hull, (-0.044, 0.108, 0.182), (-0.046, 0.116, 0.185), 0.006, 10)
    # Landing skids with shoes and strut bolts.
    for side in (-1.0, 1.0):
        swept_tube(hull, [(side * 0.030, -0.030, -0.100), (side * 0.042, -0.058, -0.040),
                          (side * 0.044, -0.070, 0.060), (side * 0.044, -0.072, 0.150)],
                   0.007, 10)
        for z in (-0.060, 0.040, 0.130):
            oriented_box(hull, (side * 0.037, -0.050, z), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                         (0.0, -1.0, 0.0), 0.055, 0.026, 0.006, 0.002, 2)
            bolt_row(hull, (side * 0.024, -0.078, z - 0.030), (side * 0.024, -0.078, z + 0.030),
                     (0.0, -1.0, 0.0), 3, 0.0032, 0.0035)
    parts = [("hull", "ds_p_hull", hull)]

    # `rotor` is the pivot the streak system spins: the radar bar, its feed and
    # its counterweights, modelled around the node's own origin.
    rotor = Builder()
    tube(rotor, (0.0, 0.030, 0.0), (0.0, 0.078, 0.0), 0.032, 18, radius_end=0.026, steps=3)
    ring_collar(rotor, (0.0, 0.032, 0.0), (0.0, 0.046, 0.0), 0.036, 0.030, 18)
    bolt_ring(rotor, (0.0, 0.048, 0.0), (0.0, 1.0, 0.0), 0.030, 6, 0.0035, 0.004)
    oriented_box(rotor, (0.0, 0.062, 0.030), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                 0.150, 0.020, 0.010, 0.002, 3)
    for side in (-1.0, 1.0):
        oriented_box(rotor, (side * 0.070, 0.062, 0.030), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.030, 0.026, 0.012, 0.002, 2)
        swept_tube(rotor, [(side * 0.040, 0.062, 0.010), (side * 0.110, 0.068, 0.030),
                           (side * 0.140, 0.072, 0.048)], 0.004, 8)
        tube(rotor, (side * 0.140, 0.072, 0.048), (side * 0.146, 0.074, 0.052), 0.006, 10)
        for index in range(5):
            x = side * mix(0.030, 0.130, index / 4.0)
            oriented_box(rotor, (x, 0.052, 0.030), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                         (0.0, 1.0, 0.0), 0.010, 0.008, 0.005, 0.0012, 2)
        bolt_row(rotor, (side * 0.020, 0.072, 0.030), (side * 0.140, 0.072, 0.030),
                 (0.0, 1.0, 0.0), 6, 0.0028, 0.003)
    torus_arc(rotor, (0.0, 0.090, 0.010), (0.0, 1.0, 0.0), 0.052, 0.0045, 0.0, TAU * 0.75,
              segments=14, arc_segments=6)
    box(rotor, (0.0, 0.090, 0.010), (0.008, 0.008, 0.008))
    parts.append(("rotor", "ds_p_metal", rotor))

    lamp = Builder()
    tube(lamp, (0.0, -0.034, -0.060), (0.0, -0.038, -0.060), 0.014, 12)
    parts.append(("lamp", "ds_p_green", lamp))
    return parts


def build_sentry_base():
    """The static half of the sentry: tripod, pedestal, bearing ring, controls."""
    base = Builder()
    # Three splayed legs with cast feet, gusset plates and leg bolts.
    for index in range(3):
        angle = index * TAU / 3.0 + QUARTER
        ux, uz = math.cos(angle), math.sin(angle)
        swept_tube(base, [(0.0, 0.300, 0.0), (ux * 0.105, 0.255, uz * 0.105),
                          (ux * 0.225, 0.135, uz * 0.225), (ux * 0.300, 0.0, uz * 0.300)],
                   0.013, 12)
        rounded_box(base, (ux * 0.300, 0.008, uz * 0.300), (0.078, 0.016, 0.078), 0.009,
                    corner_segments=3)
        bolt_ring(base, (ux * 0.300, 0.018, uz * 0.300), (0.0, 1.0, 0.0), 0.027, 4, 0.0045, 0.005)
        oriented_box(base, (ux * 0.108, 0.212, uz * 0.108), (ux, 0.0, uz), (0.0, 1.0, 0.0),
                     (-uz, 0.0, ux), 0.058, 0.032, 0.005, 0.0015, 2)
        for step in range(3):
            t = (step + 1.0) / 4.0
            reach = mix(0.0, 0.280, t)
            height = mix(0.300, 0.012, t)
            bolt_row(base, (ux * reach - uz * 0.016, height, uz * reach + ux * 0.016),
                     (ux * reach + uz * 0.016, height, uz * reach - ux * 0.016),
                     (0.0, 1.0, 0.0), 2, 0.0032, 0.0035)
    # Pedestal: tapered column, machined bearing rings, retaining bolts.
    tube(base, (0.0, 0.090, 0.0), (0.0, 0.400, 0.0), 0.050, 22, radius_end=0.041, steps=5)
    ring_collar(base, (0.0, 0.128, 0.0), (0.0, 0.142, 0.0), 0.055, 0.049, 20)
    ring_collar(base, (0.0, 0.300, 0.0), (0.0, 0.312, 0.0), 0.050, 0.044, 20)
    tube(base, (0.0, 0.400, 0.0), (0.0, 0.452, 0.0), 0.064, 22, radius_end=0.062, steps=3)
    ring_collar(base, (0.0, 0.452, 0.0), (0.0, 0.464, 0.0), 0.072, 0.062, 22)
    bolt_ring(base, (0.0, 0.466, 0.0), (0.0, 1.0, 0.0), 0.056, 10, 0.005, 0.006)
    bolt_ring(base, (0.0, 0.096, 0.0), (0.0, -1.0, 0.0), 0.044, 6, 0.0045, 0.005)
    body_of_revolution(base, [(0.076, 0.092), (0.090, 0.108), (0.104, 0.100)],
                       segments=22, cap_start=False)
    # Ammunition box on the front leg: panelled faces, hinges, catch and straps.
    rounded_box(base, (0.0, 0.140, 0.130), (0.200, 0.180, 0.140), 0.012, corner_segments=4)
    for side in (-1.0, 1.0):
        panel_grid(base, (side * 0.101, 0.140, 0.130), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.062, 0.082, 2, 3, 0.005, 0.66, 0.003, 3)
        bolt_row(base, (side * 0.101, 0.058, 0.062), (side * 0.101, 0.058, 0.198),
                 (side, 0.0, 0.0), 5, 0.0032, 0.0035)
    panel_grid(base, (0.0, 0.234, 0.130), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.090, 0.060, 3, 2, 0.005, 0.66, 0.003, 3)
    oriented_box(base, (0.0, 0.192, 0.204), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                 0.030, 0.020, 0.008, 0.002, 2)
    torus_arc(base, (0.0, 0.192, 0.212), (1.0, 0.0, 0.0), 0.024, 0.0045, 0.0, math.pi,
              segments=10, arc_segments=6)
    bolt_row(base, (0.0, 0.058, 0.062), (0.0, 0.058, 0.198), (0.0, -1.0, 0.0), 6, 0.0034, 0.0036)
    # Feed chute from the box up into the head, with its clamps.
    swept_tube(base, [(0.0, 0.210, 0.140), (0.0, 0.330, 0.120), (0.0, 0.430, 0.070)],
               (0.016, 0.014, 0.013), 10)
    for t in (0.35, 0.7):
        oriented_box(base, (0.0, mix(0.210, 0.430, t), mix(0.140, 0.070, t)),
                     (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     0.024, 0.012, 0.006, 0.002, 2)
    # Control panel with its display, keypad, guarded switches and edge bolts.
    rounded_box(base, (-0.130, 0.170, -0.020), (0.112, 0.220, 0.160), 0.012, corner_segments=4)
    oriented_box(base, (-0.130, 0.176, -0.104), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0),
                 0.052, 0.038, 0.004, 0.002, 2)
    panel_grid(base, (-0.130, 0.170, -0.104), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0),
               0.044, 0.030, 3, 2, 0.004, 0.7, 0.0025, 3)
    for column in range(3):
        for row in range(2):
            oriented_box(base, (-0.130 + (column - 1) * 0.026, 0.100 - row * 0.024, -0.106),
                         (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0),
                         0.009, 0.008, 0.004, 0.0015, 2)
    for index in range(5):
        bolt_row(base, (-0.176, 0.070 + index * 0.042, -0.101),
                 (-0.084, 0.070 + index * 0.042, -0.101), (0.0, 0.0, -1.0), 2, 0.003, 0.003)
    return [("base", "ds_p_hull", base)]


# Height the sentry's traversing head sits at, above the base column.
SENTRY_HEAD_Y = 0.500



def build_sentry_head():
    """The `gun` pivot: everything that traverses about Y.

    `streak_system` rotates this node about Y in place, so the head is modelled
    around its own origin and the node matrix lifts it onto the column.
    """
    head = Builder()
    # Traversing housing with bearing race underneath and access panels.
    rounded_box(head, (0.0, 0.0, 0.0), (0.200, 0.176, 0.240), 0.014, corner_segments=4)
    ring_collar(head, (0.0, -0.092, 0.0), (0.0, -0.074, 0.0), 0.094, 0.072, 30)
    ring_collar(head, (0.0, -0.074, 0.0), (0.0, -0.056, 0.0), 0.084, 0.072, 30)
    bolt_ring(head, (0.0, -0.052, 0.0), (0.0, 1.0, 0.0), 0.076, 10, 0.005, 0.006)
    # Skin panels on every face of the housing, with a fastener field on the
    # seams between them.
    for side in (-1.0, 1.0):
        panel_grid(head, (side * 0.101, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.100, 0.070, 4, 3, 0.005, 0.66, 0.003, 3)
        bolt_row(head, (side * 0.104, 0.080, -0.100), (side * 0.104, 0.080, 0.100),
                 (side, 0.0, 0.0), 10, 0.0038, 0.004)
    panel_grid(head, (0.0, 0.089, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.090, 0.110, 4, 4, 0.005, 0.66, 0.003, 3)
    panel_grid(head, (0.0, 0.0, 0.121), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0),
               0.090, 0.076, 3, 3, 0.005, 0.66, 0.003, 3)
    for face in (-1.0, 1.0):
        for index in range(6):
            oriented_box(head, (-0.070 + index * 0.028, 0.062 + (index % 2) * 0.030,
                                face * 0.124), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                         (0.0, 0.0, face), 0.0055, 0.006, 0.0032, 0.0010, 2)
    # Barrel: stepped tube, cooling rings and a vented shroud.
    tube(head, (0.0, 0.010, -0.080), (0.0, 0.010, -0.232), 0.0195, 28, radius_end=0.0175, steps=4)
    for index in range(5):
        z = -0.108 - index * 0.026
        ring_collar(head, (0.0, 0.010, z - 0.004), (0.0, 0.010, z + 0.004), 0.0245, 0.0195, 28)
    for ring in range(4):
        z = -0.100 - ring * 0.030
        for index in range(8):
            angle = QUARTER + index * TAU / 8.0
            ux, uz = math.cos(angle), math.sin(angle)
            oriented_box(head, (ux * 0.0215, 0.010 + uz * 0.0215, z), (0.0, 0.0, 1.0),
                         (-uz, ux, 0.0), (ux, uz, 0.0), 0.0065, 0.0045, 0.003, 0.001, 2)
    # Shroud fasteners and the feed sprocket that pulls the belt in.
    for index in range(6):
        z = -0.100 - index * 0.022
        for angle in (0.0, math.pi):
            ux, uz = math.cos(angle), math.sin(angle)
            screw(head, (ux * 0.0200, 0.010 + uz * 0.0200, z), (ux, 0.0, uz), 0.0028, 0.0030)
    tube(head, (0.030, 0.030, -0.070), (0.038, 0.030, -0.094), 0.0085, 14, steps=2)
    ring_collar(head, (0.038, 0.030, -0.094), (0.038, 0.030, -0.102), 0.011, 0.0085, 14)
    for index in range(4):
        oriented_box(head, (0.040, 0.030, -0.108 - index * 0.014), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.010, 0.004, 0.003, 0.0010, 2)
    # Muzzle brake with side ports and a crowned muzzle.
    tube(head, (0.0, 0.010, -0.232), (0.0, 0.010, -0.262), 0.027, 28, radius_end=0.023, steps=2)
    ring_collar(head, (0.0, 0.010, -0.262), (0.0, 0.010, -0.272), 0.025, 0.017, 28)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uz = math.cos(angle), math.sin(angle)
        oriented_box(head, (ux * 0.026, 0.010 + uz * 0.026, -0.248), (0.0, 0.0, 1.0),
                     (-uz, ux, 0.0), (ux, uz, 0.0), 0.010, 0.006, 0.003, 0.001, 2)
    # Sensor pod with a glazed window, rim bolts and the daylight optic above it.
    rounded_box(head, (0.0, 0.062, -0.010), (0.092, 0.080, 0.172), 0.010, corner_segments=4)
    tube(head, (0.0, 0.066, -0.096), (0.0, 0.066, -0.112), 0.024, 24, radius_end=0.020, steps=2)
    ring_collar(head, (0.0, 0.066, -0.094), (0.0, 0.066, -0.082), 0.028, 0.024, 24)
    tube(head, (0.0, 0.066, -0.052), (0.0, 0.066, 0.040), 0.017, 24, cap_start=False,
         cap_end=False)
    ring_collar(head, (0.0, 0.066, 0.038), (0.0, 0.066, 0.050), 0.021, 0.017, 24)
    bolt_ring(head, (0.0, 0.066, -0.078), (0.0, 0.0, -1.0), 0.030, 6, 0.0038, 0.004)
    for side in (-1.0, 1.0):
        panel_grid(head, (side * 0.046, 0.062, -0.010), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.070, 0.030, 3, 1, 0.004, 0.6, 0.0028, 3)
        bolt_row(head, (side * 0.047, 0.100, -0.078), (side * 0.047, 0.100, 0.058),
                 (side, 0.0, 0.0), 4, 0.0028, 0.0030)
    # Left-hand electronics bay: heat-sink fins, catches and a hinged lid arm.
    rounded_box(head, (-0.112, -0.010, 0.020), (0.080, 0.140, 0.120), 0.010, corner_segments=4)
    for index in range(6):
        oriented_box(head, (-0.156, -0.055 + index * 0.020, 0.020), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0), 0.048, 0.0040, 0.005, 0.0014, 2)
    for row in (-1, 1):
        oriented_box(head, (-0.112, row * 0.062, 0.086), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     (0.0, 0.0, 1.0), 0.030, 0.008, 0.006, 0.002, 2)
    torus_arc(head, (-0.112, 0.072, 0.086), (1.0, 0.0, 0.0), 0.020, 0.004, 0.0, math.pi,
              segments=8, arc_segments=6)
    # Right-hand counterweight discs and the traverse motor housing.
    for index in range(4):
        body_of_revolution(head, [(0.108 + index * 0.026, 0.052 - index * 0.004),
                                  (0.120 + index * 0.026, 0.058 - index * 0.004),
                                  (0.130 + index * 0.026, 0.050 - index * 0.004)],
                           segments=26, cap_start=False, cap_end=False)
    body_of_revolution(head, [(0.104, 0.040), (0.132, 0.054), (0.150, 0.046)],
                       segments=26, cap_start=False)
    bolt_ring(head, (0.152, 0.0, 0.0), (1.0, 0.0, 0.0), 0.036, 6, 0.004, 0.004)
    # Grab handles either side of the housing.
    for side in (-1.0, 1.0):
        ribbon(head, [(side * 0.104, 0.070, -0.120), (side * 0.126, 0.070, -0.080),
                      (side * 0.126, 0.070, 0.040), (side * 0.104, 0.070, 0.080)],
               (0.0, 1.0, 0.0), 0.008, 0.005)
        for z in (-0.120, 0.080):
            oriented_box(head, (side * 0.112, 0.070, z), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                         (0.0, 1.0, 0.0), 0.014, 0.012, 0.006, 0.002, 2)
    return [("gun", "ds_p_hull", head)]


def build_predator():
    """Long-endurance hunter-killer: slender airframe, V-tail, pusher prop."""
    body = Builder()
    # Airframe: seeker nose, warhead shoulder, motor section and boat-tail.
    body_of_revolution(body, [(0.300, 0.030), (0.282, 0.038), (0.255, 0.041),
                              (0.150, 0.042), (0.020, 0.042), (-0.060, 0.041),
                              (-0.180, 0.039), (-0.270, 0.036), (-0.300, 0.010)],
                       segments=22)
    # Panel seams splitting the sections, warhead shoulder ring included.
    for z, r in ((0.150, 0.0425), (0.020, 0.0425), (-0.060, 0.0415), (-0.180, 0.0395)):
        ring_collar(body, (0.0, 0.0, z - 0.003), (0.0, 0.0, z + 0.003), r * 1.05, r * 0.98, 22)
    bolt_ring(body, (0.0, 0.0, 0.148), (0.0, 0.0, 1.0), 0.038, 12, 0.0035, 0.004)
    bolt_ring(body, (0.0, 0.0, -0.058), (0.0, 0.0, 1.0), 0.037, 12, 0.0035, 0.004)
    # Longitudinal seam and the access panels on the flanks.
    for index in range(8):
        angle = index * TAU / 8.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.041, 0.010 * math.sin(angle * 2.0), 0.045), (0.0, 0.0, 1.0),
                     (uy, -ux, 0.0), (ux, uy, 0.0), 0.130, 0.004, 0.004, 0.0012, 2)
    # Skin panels run the length of the airframe on every station, with a
    # fastener row down each longitudinal seam between them.
    for index in range(8):
        angle = index * TAU / 8.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        for cell in range(7):
            t = (cell + 0.5) / 7.0
            z = mix(-0.290, 0.290, t)
            radius = mix(0.036, 0.042, 1.0 - abs(t - 0.45) * 1.6) if t < 0.45 else \
                mix(0.042, 0.010, (t - 0.45) / 0.55)
            oriented_box(body, (ux * radius, uy * radius, z), (0.0, 0.0, 1.0),
                         (uy, -ux, 0.0), (ux, uy, 0.0), 0.040, 0.0035, 0.0032, 0.0012, 2)
        for cell in range(9):
            t = (cell + 1.0) / 10.0
            z = mix(-0.290, 0.290, t)
            radius = mix(0.036, 0.042, 1.0 - abs(t - 0.45) * 1.6) if t < 0.45 else \
                mix(0.042, 0.010, (t - 0.45) / 0.55)
            screw(body, (ux * radius, uy * radius, z), (ux, uy, 0.0), 0.0028, 0.003)
    # Cruciform mid-body fins with a raised spar and a root fillet.
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        planform = [(ux * 0.020, uy * 0.020, -0.190), (ux * 0.105, uy * 0.105, -0.090),
                    (ux * 0.105, uy * 0.105, 0.030), (ux * 0.020, uy * 0.020, 0.000)]
        plate(body, planform, (uy * 0.009, -ux * 0.009, 0.0))
        oriented_box(body, (ux * 0.062, uy * 0.062, -0.060), (0.0, 0.0, 1.0),
                     (uy, -ux, 0.0), (ux, uy, 0.0), 0.055, 0.008, 0.004, 0.0015, 2)
        bolt_row(body, (ux * 0.030, uy * 0.030, -0.170), (ux * 0.030, uy * 0.030, 0.010),
                 (uy, -ux, 0.0), 5, 0.0028, 0.003)
        # Fin skin panels both faces, so the fin is not a bare plate.
        for surface in (-1.0, 1.0):
            for cell in range(3):
                local = (cell - 1) * 0.028
                oriented_box(body, (ux * (0.052 + local * ux), uy * (0.052 + local * uy) + 0.0,
                                    -0.060 - local * 0.0), (0.0, 0.0, 1.0),
                             (uy * surface, -ux * surface, 0.0), (ux, uy, 0.0),
                             0.016, 0.0045, 0.0028, 0.0012, 2)
        for surface in (-1.0, 1.0):
            for cell in range(4):
                local = (cell - 1.5) * 0.022
                screw(body, (ux * 0.078, uy * 0.078 + surface * 0.005,
                             -0.150 + cell * 0.045), (uy * surface, -ux * surface, 0.0),
                      0.0026, 0.0028)
    # Horizontal tail surfaces and the two V-tail panels with hinge lines.
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.018, 0.006, -0.286), (side * 0.140, 0.006, -0.226),
                     (side * 0.140, 0.006, -0.176), (side * 0.018, 0.006, -0.236)],
              (0.0, 0.008, 0.0))
        plate(body, [(side * 0.014, 0.010, -0.244), (side * 0.016, 0.150, -0.300),
                     (side * 0.016, 0.150, -0.348), (side * 0.014, 0.010, -0.292)],
              (side * 0.008, 0.0, 0.0))
        oriented_box(body, (side * 0.016, 0.078, -0.322), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     (side, 0.0, 0.0), 0.030, 0.005, 0.004, 0.0015, 2)
        for index in range(4):
            t = (index + 1) / 5.0
            bolt_row(body, (side * 0.016, mix(0.020, 0.140, t), mix(-0.272, -0.340, t)),
                     (side * 0.016, mix(0.020, 0.140, t), mix(-0.272, -0.340, t) + 0.02),
                     (side, 0.0, 0.0), 2, 0.0026, 0.0028)
        bolt_row(body, (side * 0.020, 0.006, -0.290), (side * 0.140, 0.006, -0.230),
                 (0.0, 1.0, 0.0), 4, 0.0026, 0.0028)
    # Intake and exhaust: a scoop, its lip and a slatted cooling grille.
    rounded_box(body, (0.0, -0.052, 0.180), (0.052, 0.030, 0.120), 0.006, corner_segments=3)
    ring_collar(body, (0.0, -0.052, 0.238), (0.0, -0.052, 0.248), 0.028, 0.020, 16)
    for index in range(4):
        oriented_box(body, (0.0, -0.066, 0.130 + index * 0.026), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, -1.0, 0.0), 0.020, 0.008, 0.004, 0.0012, 2)
    # Launch lugs and the umbilical connector on the spine.
    for z in (-0.050, 0.060):
        oriented_box(body, (0.0, 0.048, z), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     0.020, 0.014, 0.010, 0.002, 2)
        bolt_row(body, (-0.020, 0.052, z), (0.020, 0.052, z), (0.0, 1.0, 0.0), 2, 0.003, 0.003)
    oriented_box(body, (0.0, 0.046, 0.100), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.016, 0.012, 0.006, 0.002, 2)
    bolt_ring(body, (0.0, 0.052, 0.100), (0.0, 1.0, 0.0), 0.014, 4, 0.003, 0.003)
    # Antenna blade and the static-discharge wicks on the tail.
    plate(body, [(0.0, 0.042, 0.070), (0.006, 0.042, 0.070), (0.004, 0.078, 0.052),
                 (-0.004, 0.078, 0.052)], (0.004, 0.0, 0.0))
    for side in (-1.0, 1.0):
        swept_tube(body, [(side * 0.120, 0.006, -0.200), (side * 0.150, 0.006, -0.214)],
                   0.0026, 8)
    parts = [("body", "ds_p_hull", body)]

    # Sensor ball on its gimbal under the nose.
    sensor = Builder()
    body_of_revolution(sensor, [(-0.222, 0.014), (-0.238, 0.024), (-0.252, 0.026),
                                (-0.262, 0.018)], segments=20, cap_start=False)
    ring_collar(sensor, (0.0, -0.040, -0.222), (0.0, -0.040, -0.232), 0.030, 0.022, 18)
    tube(sensor, (0.0, -0.040, -0.254), (0.0, -0.040, -0.262), 0.020, 16, radius_end=0.016)
    bolt_ring(sensor, (0.0, -0.040, -0.222), (0.0, 0.0, -1.0), 0.026, 6, 0.003, 0.003)
    parts.append(("sensor", "ds_p_lens", sensor))

    # Exhaust nozzle with a bell, and the pusher propeller on a stub shaft.
    exhaust = Builder()
    tube(exhaust, (0.0, 0.0, 0.300), (0.0, 0.0, 0.322), 0.024, 20, radius_end=0.016, steps=2)
    ring_collar(exhaust, (0.0, 0.0, 0.298), (0.0, 0.0, 0.306), 0.026, 0.021, 20)
    tube(exhaust, (0.0, 0.0, 0.322), (0.0, 0.0, 0.336), 0.016, 16, radius_end=0.028, steps=2)
    ring_collar(exhaust, (0.0, 0.0, 0.336), (0.0, 0.0, 0.342), 0.030, 0.024, 18)
    bolt_ring(exhaust, (0.0, 0.0, 0.300), (0.0, 0.0, 1.0), 0.021, 6, 0.0032, 0.0035)
    parts.append(("exhaust", "ds_p_lamp", exhaust))

    propeller = Builder()
    tube(propeller, (0.0, 0.0, 0.342), (0.0, 0.0, 0.362), 0.010, 12, radius_end=0.014)
    ring_collar(propeller, (0.0, 0.0, 0.358), (0.0, 0.0, 0.366), 0.018, 0.012, 14)
    for index in range(3):
        angle = index * TAU / 3.0
        ux, uy = math.cos(angle), math.sin(angle)
        twisted_blade(propeller, (ux * 0.014, uy * 0.014, 0.360), (ux * 0.130, uy * 0.130, 0.360),
                      0.018, 0.0028, 0.42, 0.7, 0.9, 5)
        oriented_box(propeller, (ux * 0.022, uy * 0.022, 0.360), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.014, 0.008, 0.004, 0.0015, 2)
    return parts


def build_gunship():
    """Attack helicopter used by the chopper gunner and gunship streaks."""
    body = Builder()
    # Fuselage: seven stations down the boom, split by real panel seams.
    fuselage = [(0.0, 0.100, 0.100), (0.16, 0.170, 0.156), (0.34, 0.220, 0.200),
                (0.50, 0.222, 0.202), (0.66, 0.200, 0.180), (0.84, 0.150, 0.136),
                (1.0, 0.070, 0.070)]
    sweep(body, profile_circle(1.0, 22),
          [((0.0, 0.0, -1.20 + t * 1.60), vmul((1.0, 0.0, 0.0), rx),
            vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, 1.0))
           for t, rx, ry in fuselage], True, True)
    for t, scale in ((0.16, 1.05), (0.34, 1.05), (0.50, 1.05), (0.66, 1.04), (0.84, 1.04)):
        z = -1.20 + t * 1.60
        rx = mix(0.100, 0.070, t) if t < 0.34 else 0.220 * (1.0 - (t - 0.34) * 0.6)
        ring_collar(body, (0.0, 0.0, z - 0.004), (0.0, 0.0, z + 0.004), rx * scale + 0.004,
                    rx * scale - 0.004, 22)
    for side in (-1.0, 1.0):
        for index in range(5):
            z = -0.95 + index * 0.44
            radius = mix(0.215, 0.150, index / 4.0)
            oriented_box(body, (side * radius * 0.99, 0.0, z), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (side, 0.0, 0.0), 0.150, 0.070, 0.005, 0.0015, 2)
        bolt_row(body, (side * 0.16, 0.150, -0.90), (side * 0.12, 0.130, 0.70),
                 (side, 0.0, 0.0), 14, 0.0038, 0.004)
    # Tail boom, its ring frames and the fin with a hinge line.
    tube(body, (0.0, 0.0, 0.400), (0.0, 0.020, 0.940), 0.075, 18, radius_end=0.050, steps=4)
    for index in range(4):
        t = (index + 1) / 5.0
        ring_collar(body, (0.0, mix(0.0, 0.020, t), mix(0.400, 0.940, t) - 0.004),
                    (0.0, mix(0.0, 0.020, t), mix(0.400, 0.940, t) + 0.004),
                    mix(0.075, 0.050, t) + 0.004, mix(0.075, 0.050, t) - 0.004, 18)
    plate(body, [(0.0, 0.060, 0.820), (0.0, 0.230, 0.960), (0.0, 0.230, 0.880),
                 (0.0, 0.060, 0.760)], (0.012, 0.0, 0.0))
    oriented_box(body, (0.0, 0.100, 0.836), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                 0.090, 0.006, 0.005, 0.0015, 2)
    bolt_row(body, (0.0, 0.070, 0.830), (0.0, 0.220, 0.930), (1.0, 0.0, 0.0), 5, 0.003, 0.003)
    # Stub wings: lofted, with pylons, launch rails and bolts.
    for side in (-1.0, 1.0):
        wing_loft(body, side, ((0.150, -0.150, 0.220, 0.022), (0.400, -0.140, 0.200, 0.018),
                               (0.620, -0.130, 0.180, 0.013)))
        oriented_box(body, (side * 0.390, -0.100, -0.150), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.075, 0.170, 0.007, 0.0015, 2)
        for pylon in (0.0, 1.0):
            z = -0.300 + pylon * 0.190
            rounded_box(body, (side * 0.500, -0.070, z), (0.120, 0.140, 0.300), 0.014,
                        corner_segments=3)
            tube(body, (side * 0.500, -0.140, z - 0.140), (side * 0.500, -0.140, z + 0.160),
                 0.036, 14, steps=2)
            ring_collar(body, (side * 0.500, -0.140, z - 0.148), (side * 0.500, -0.140, z - 0.136),
                        0.040, 0.036, 14)
            ring_collar(body, (side * 0.500, -0.140, z + 0.152), (side * 0.500, -0.140, z + 0.164),
                        0.040, 0.036, 14)
            bolt_ring(body, (side * 0.500, -0.070, z - 0.148), (0.0, 0.0, -1.0), 0.048, 6,
                      0.004, 0.004)
            bolt_row(body, (side * 0.560, -0.060, z - 0.120), (side * 0.560, -0.060, z + 0.140),
                     (side, 0.0, 0.0), 5, 0.0035, 0.0038)
        # Wingtip fairing and position light.
        rounded_box(body, (side * 0.640, -0.130, -0.120), (0.060, 0.120, 0.260), 0.010,
                    corner_segments=3)
        tube(body, (side * 0.664, -0.130, 0.010), (side * 0.672, -0.130, 0.010), 0.010, 12)
    # Main rotor mast fairing and the transmission deck.
    tube(body, (0.0, 0.180, 0.0), (0.0, 0.235, 0.0), 0.090, 20, radius_end=0.070, steps=2)
    ring_collar(body, (0.0, 0.180, 0.0), (0.0, 0.196, 0.0), 0.098, 0.090, 20)
    bolt_ring(body, (0.0, 0.182, 0.0), (0.0, 1.0, 0.0), 0.088, 8, 0.005, 0.006)
    panel_grid(body, (0.0, 0.190, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.080, 0.100, 3, 3, 0.004, 0.62, 0.0028, 3)
    # Engine cowling with slatted intakes either side of the mast.
    for side in (-1.0, 1.0):
        rounded_box(body, (side * 0.150, 0.180, 0.170), (0.140, 0.120, 0.360), 0.014,
                    corner_segments=3)
        for index in range(5):
            oriented_box(body, (side * 0.215, 0.180, 0.020 + index * 0.048), (0.0, 0.0, 1.0),
                         (side, 0.0, 0.0), (0.0, 1.0, 0.0), 0.030, 0.020, 0.006, 0.0015, 2)
        bolt_row(body, (side * 0.215, 0.130, 0.020), (side * 0.215, 0.130, 0.330),
                 (side, 0.0, 0.0), 6, 0.0035, 0.0038)
    # Exhaust ducts with heat-stained shrouds.
    for side in (-1.0, 1.0):
        tube(body, (side * 0.170, 0.190, 0.300), (side * 0.230, 0.240, 0.400), 0.052, 16,
             radius_end=0.058, steps=2)
        ring_collar(body, (side * 0.228, 0.238, 0.394), (side * 0.238, 0.246, 0.408), 0.062,
                    0.054, 16)
    # Skids: struts, shoes, cross tubes and clamps.
    for side in (-1.0, 1.0):
        swept_tube(body, [(side * 0.200, -0.240, -0.600), (side * 0.240, -0.300, -0.300),
                          (side * 0.260, -0.340, 0.200), (side * 0.260, -0.340, 0.700)],
                   0.026, 12)
        for z in (-0.520, -0.400, 0.300, 0.640):
            oriented_box(body, (side * 0.255, -0.340, z), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), 0.045, 0.060, 0.006, 0.002, 2)
        for z in (-0.400, 0.300):
            tube(body, (side * 0.160, -0.100, z), (side * 0.240, -0.320, z), 0.014, 10, steps=3)
            ring_collar(body, (side * 0.196, -0.196, z), (side * 0.206, -0.212, z), 0.018,
                        0.014, 10)
            bolt_ring(body, (side * 0.166, -0.108, z), (0.0, 0.0, 1.0), 0.014, 3, 0.003, 0.003)
    # Ammunition bay under the nose, feeding the chin gun.
    rounded_box(body, (0.0, -0.180, -0.900), (0.180, 0.150, 0.220), 0.014, corner_segments=3)
    bolt_row(body, (0.0, -0.250, -0.960), (0.0, -0.250, -0.840), (0.0, -1.0, 0.0), 5, 0.0035, 0.0038)

    # Sensor turret in its own node, so the gimbal keeps reading as a separate
    # volume and the streak code can still reach `turret` by name.
    turret = Builder()
    tube(turret, (0.0, -0.090, -1.020), (0.0, -0.130, -1.020), 0.070, 20, radius_end=0.055,
         steps=3)
    ring_collar(turret, (0.0, -0.070, -1.020), (0.0, -0.082, -1.020), 0.074, 0.068, 20)
    bolt_ring(turret, (0.0, -0.086, -1.020), (0.0, -1.0, 0.0), 0.066, 8, 0.0045, 0.005)
    tube(turret, (0.0, -0.140, -1.060), (0.0, -0.140, -1.124), 0.022, 16, radius_end=0.019,
         steps=2)
    ring_collar(turret, (0.0, -0.140, -1.124), (0.0, -0.140, -1.134), 0.026, 0.020, 16)
    body_of_revolution(turret, [(-1.060, 0.040), (-1.076, 0.046), (-1.092, 0.040)],
                       segments=20, cap_start=False)

    # Cockpit glazing: a lofted shell with a frame arch and a centre post.
    cockpit = Builder()
    sweep(cockpit, profile_circle(1.0, 18),
          [((0.0, 0.100 + t * 0.060, -1.15 + t * 0.42), vmul((1.0, 0.0, 0.0), rx),
            vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, 1.0))
           for t, rx, ry in ((0.0, 0.050, 0.040), (0.35, 0.098, 0.072),
                             (0.70, 0.132, 0.096), (1.0, 0.060, 0.050))], True, True)
    for t, rx, ry in ((0.35, 0.098, 0.072), (0.70, 0.132, 0.096)):
        ring_collar(cockpit, (0.0, 0.100 + t * 0.060, -1.15 + t * 0.42 - 0.004),
                    (0.0, 0.100 + t * 0.060, -1.15 + t * 0.42 + 0.004), rx * 1.07, rx * 0.99, 18)
    oriented_box(cockpit, (0.0, 0.170, -1.010), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.016, 0.048, 0.006, 0.0018, 2)
    return [("body", "ds_p_hull", body), ("cockpit", "ds_p_lens", cockpit),
            ("turret", "ds_p_metal", turret)]


# Mount heights for the aircraft rotor pivots. The nodes sit at their parent's
# origin with an identity matrix, which the contract freezes, so the disc has to
# be carried at the height the mast actually reaches: `mainRotor` spins about Y
# through the node origin, so its hub stays on that axis and only its height
# moves, and `tailRotor` spins about X so its own offset is in Y and Z.
GUNSHIP_MAIN_ROTOR_Y = 0.180
GUNSHIP_TAIL_ROTOR_Y = 0.150
GUNSHIP_TAIL_ROTOR_Z = 0.900


def build_gunship_rotors():
    """`mainRotor` and `tailRotor` are the pivots the streak system spins.

    Both carry their blades about the pivot axis passing through the node
    origin, at the mount height the airframe reaches, so the spin stays a pure
    local rotation.
    """
    hy = GUNSHIP_MAIN_ROTOR_Y
    main = Builder()
    # Mast, hub, blade grips and the swashplate under them.
    tube(main, (0.0, hy, 0.0), (0.0, hy + 0.090, 0.0), 0.040, 18, steps=3)
    ring_collar(main, (0.0, hy + 0.010, 0.0), (0.0, hy + 0.026, 0.0), 0.048, 0.040, 18)
    ring_collar(main, (0.0, hy + 0.062, 0.0), (0.0, hy + 0.074, 0.0), 0.052, 0.044, 18)
    bolt_ring(main, (0.0, hy + 0.076, 0.0), (0.0, 1.0, 0.0), 0.042, 6, 0.0045, 0.005)
    for index in range(4):
        angle = index * HALF_PI
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(main, (ux * 0.070, hy + 0.085, uy * 0.070), (ux, 0.0, uy), (0.0, 1.0, 0.0),
                     (-uy, 0.0, ux), 0.036, 0.011, 0.030, 0.002, 3)
        bolt_row(main, (ux * 0.046, hy + 0.086, uy * 0.046), (ux * 0.094, hy + 0.086, uy * 0.094),
                 (0.0, 1.0, 0.0), 3, 0.0035, 0.0038)
        # Blade with real washout twist and a rounded tip.
        twisted_blade(main, (ux * 0.100, hy + 0.085, uy * 0.100),
                      (ux * 2.400, hy + 0.075, uy * 2.400),
                      0.080, 0.011, 0.22, 0.55, 0.85, 8, corner_segments=3)
        oriented_box(main, (ux * 0.340, hy + 0.086, uy * 0.340), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.100, 0.010, 0.005, 0.0015, 2)
        for t in (0.30, 0.62, 0.94):
            span = 2.400 * t
            oriented_box(main, (ux * span, hy + 0.083, uy * span), (0.0, 0.0, 1.0),
                         (uy, -ux, 0.0), (ux, uy, 0.0), 0.070, 0.009, 0.004, 0.0015, 2)
            bolt_row(main, (ux * span, hy + 0.090, uy * span - 0.05),
                     (ux * span, hy + 0.090, uy * span + 0.05), (0.0, 1.0, 0.0), 3, 0.0032, 0.0035)
    ty, tz = GUNSHIP_TAIL_ROTOR_Y, GUNSHIP_TAIL_ROTOR_Z
    tail = Builder()
    # Tail rotor on the fin: gearbox hub, two blades and their pitch links.
    tube(tail, (0.0, ty, tz), (0.040, ty, tz), 0.030, 16, steps=3)
    ring_collar(tail, (0.006, ty, tz), (0.018, ty, tz), 0.038, 0.030, 16)
    bolt_ring(tail, (0.038, ty, tz), (1.0, 0.0, 0.0), 0.028, 4, 0.0035, 0.004)
    for index in range(2):
        angle = index * math.pi
        uz, uy = math.cos(angle), math.sin(angle)
        twisted_blade(tail, (0.032, ty + uy * 0.036, tz + uz * 0.036),
                      (0.032, ty + uy * 0.520, tz + uz * 0.520),
                      0.034, 0.006, 0.30, 0.6, 0.88, 6, corner_segments=3)
        oriented_box(tail, (0.036, ty + uy * 0.070, tz + uz * 0.070), (0.0, uy, uz),
                     (1.0, 0.0, 0.0), (0.0, -uz, uy), 0.020, 0.010, 0.008, 0.002, 2)
        for span in (0.200, 0.360):
            oriented_box(tail, (0.036, ty + uy * span, tz + uz * span), (0.0, uy, uz),
                         (1.0, 0.0, 0.0), (0.0, -uz, uy), 0.036, 0.006, 0.004, 0.0015, 2)
    return [("mainRotor", "ds_p_dark", main), ("tailRotor", "ds_p_dark", tail)]


def build_strafe_jet():
    """The strafing aircraft: fighter airframe, canopy, stores and exhausts."""
    body = Builder()
    fuselage = [(0.0, 0.014, 0.014), (0.10, 0.040, 0.034), (0.22, 0.056, 0.048),
                (0.42, 0.062, 0.052), (0.58, 0.060, 0.050), (0.80, 0.044, 0.038),
                (1.0, 0.026, 0.024)]
    sweep(body, profile_circle(1.0, 20),
          [((0.0, 0.0, -0.62 + t * 1.24), vmul((1.0, 0.0, 0.0), rx),
            vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, 1.0)) for t, rx, ry in fuselage], True, True)
    for t, scale in ((0.10, 1.05), (0.22, 1.05), (0.42, 1.04), (0.58, 1.04), (0.80, 1.04)):
        z = -0.62 + t * 1.24
        rx = mix(0.014, 0.026, t) if t < 0.22 else mix(0.060, 0.026, (t - 0.22) / 0.78)
        ring_collar(body, (0.0, 0.0, z - 0.0035), (0.0, 0.0, z + 0.0035), rx * scale + 0.003,
                    rx * scale - 0.003, 20)
    for index in range(5):
        z = -0.20 + index * 0.24
        radius = mix(0.062, 0.044, index / 4.0)
        for side in (-1.0, 1.0):
            oriented_box(body, (side * radius * 0.99, 0.0, z), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (side, 0.0, 0.0), 0.090, 0.018, 0.004, 0.0012, 2)
        bolt_row(body, (0.0, 0.056, z), (0.0, -0.056, z), (0.0, 0.0, 1.0), 4, 0.003, 0.003)
    # Swept wings with a spar, slats, flaps and tip rails.
    for side in (-1.0, 1.0):
        wing_loft(body, side, ((0.040, -0.010, 0.300, 0.016), (0.200, 0.010, 0.260, 0.012),
                               (0.400, 0.040, 0.200, 0.008)))
        oriented_box(body, (side * 0.220, 0.020, -0.030), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.055, 0.160, 0.005, 0.0015, 2)
        plate(body, [(side * 0.050, 0.0, -0.130), (side * 0.400, 0.030, 0.130),
                     (side * 0.400, 0.030, 0.180), (side * 0.050, 0.0, -0.070)], (0.0, 0.010, 0.0))
        bolt_row(body, (side * 0.060, 0.030, -0.060), (side * 0.380, 0.055, 0.140),
                 (0.0, 1.0, 0.0), 8, 0.0032, 0.0035)
        # Underwing stores: two pylons, each with a rail and lugs.
        for span in (0.180, 0.260):
            tube(body, (side * span, -0.030, 0.020), (side * span, -0.030, -0.150), 0.014, 14,
                 steps=3)
            ring_collar(body, (side * span, -0.030, 0.014), (side * span, -0.030, 0.026), 0.018,
                        0.014, 14)
            oriented_box(body, (side * span, -0.005, -0.065), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                         (0.0, 1.0, 0.0), 0.024, 0.075, 0.006, 0.0015, 2)
            bolt_row(body, (side * span, -0.030, -0.140), (side * span, -0.030, 0.010),
                     (0.0, 1.0, 0.0), 4, 0.003, 0.003)
        # Canted tail plane and the tip-launch rail.
        tail_plan = [(side * 0.020, 0.030, 0.480), (side * 0.110, 0.130, 0.620),
                     (side * 0.110, 0.130, 0.520), (side * 0.020, 0.030, 0.460)]
        plate(body, tail_plan, (side * 0.014, 0.0, 0.0))
        oriented_box(body, (side * 0.062, 0.076, 0.520), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.030, 0.005, 0.004, 0.0015, 2)
        bolt_row(body, (side * 0.026, 0.040, 0.486), (side * 0.104, 0.124, 0.600),
                 (side, 0.0, 0.0), 4, 0.0028, 0.003)
        tube(body, (side * 0.030, 0.0, 0.620), (side * 0.030, 0.0, 0.672), 0.026, 16,
             radius_end=0.030, steps=2)
        ring_collar(body, (side * 0.030, 0.0, 0.660), (side * 0.030, 0.0, 0.676), 0.032, 0.027, 16)
        # Vertical fin.
        plate(body, [(side * 0.010, 0.040, 0.500), (side * 0.010, 0.150, 0.640),
                     (side * 0.010, 0.150, 0.560), (side * 0.010, 0.040, 0.470)],
              (side * 0.010, 0.0, 0.0))
    # Engine nozzles with petals and a heat shield.
    for side in (-1.0, 1.0):
        tube(body, (side * 0.022, 0.0, 0.500), (side * 0.026, 0.0, 0.640), 0.020, 16,
             radius_end=0.026, steps=3)
        ring_collar(body, (side * 0.026, 0.0, 0.636), (side * 0.028, 0.0, 0.652), 0.029, 0.023, 16)
        for index in range(6):
            angle = index * TAU / 6.0
            ux, uy = math.cos(angle), math.sin(angle)
            oriented_box(body, (side * 0.026 + ux * 0.026, uy * 0.026, 0.640), (0.0, 0.0, 1.0),
                         (-uy, ux, 0.0), (ux, uy, 0.0), 0.008, 0.005, 0.004, 0.0012, 2)
    # Nose pitot, angle-of-attack vanes and the gun port.
    tube(body, (0.0, 0.0, -0.620), (0.0, 0.0, -0.680), 0.005, 10, radius_end=0.0022, steps=2)
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.026, 0.006, -0.560), (side * 0.040, 0.006, -0.540),
                     (side * 0.040, 0.006, -0.520), (side * 0.026, 0.006, -0.540)],
              (0.0, 0.003, 0.0))
    rounded_box(body, (0.0, -0.032, -0.380), (0.060, 0.030, 0.120), 0.008, corner_segments=3)
    tube(body, (0.0, -0.040, -0.440), (0.0, -0.040, -0.462), 0.012, 12)
    parts = [("body", "ds_p_hull", body)]

    # Canopy: a lofted shell with a frame arch and a glazed hatch.
    canopy = Builder()
    sweep(canopy, profile_circle(1.0, 18),
          [((0.0, 0.052 - t * 0.010, -0.400 + t * 0.300), vmul((1.0, 0.0, 0.0), r),
            vmul((0.0, 1.0, 0.0), r * 0.55), (0.0, 0.0, 1.0))
           for t, r in ((0.0, 0.012), (0.18, 0.026), (0.35, 0.032), (0.62, 0.030),
                        (1.0, 0.014))], True, True)
    for t, r in ((0.18, 0.026), (0.35, 0.032), (0.62, 0.030)):
        z = -0.400 + t * 0.300
        ring_collar(canopy, (0.0, 0.052 - t * 0.010 - r * 0.55, z - 0.004),
                    (0.0, 0.052 - t * 0.010 - r * 0.55, z + 0.004), r * 1.06, r * 0.98, 18)
    oriented_box(canopy, (0.0, 0.070, -0.240), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.012, 0.030, 0.005, 0.0015, 2)
    return [("body", "ds_p_hull", body), ("canopy", "ds_p_lens", canopy)]



# --------------------------------------------------------------------------
# Equipment.
# --------------------------------------------------------------------------


def build_frag():
    """M67-style fragmentation grenade.

    Oval casing, the deep pre-fragmentation grid the read depends on, and a
    complete fuze group above it: collar, striker, spoon with its hinge and
    pull ring, plus the base plug. `body_of_revolution` at a high station count
    gives the silhouette; `curved_grid` gives the fragmentation pattern.
    """
    body = Builder()
    casing = [(-0.056, 0.010), (-0.050, 0.024), (-0.042, 0.034), (-0.030, 0.042),
              (-0.014, 0.0468), (0.004, 0.0485), (0.022, 0.0466), (0.036, 0.0425),
              (0.046, 0.0360), (0.054, 0.0280), (0.060, 0.0180), (0.064, 0.0080)]
    stacked(body, casing, segments=32)
    # Two crossing families of recessed grooves: the blocks sit at the centre of
    # each cell, so the clear space between them *is* the cut pattern.
    curved_grid(body, casing, 20, 10, -0.032, 0.050, depth=0.0042, fill=0.60)
    # Top shoulder ring and base plug, both with their own machined collars.
    ring_collar(body, (0.0, 0.050, 0.0), (0.0, 0.060, 0.0), 0.0435, 0.0310, 32)
    ring_collar(body, (0.0, -0.058, 0.0), (0.0, -0.050, 0.0), 0.0115, 0.0050, 24)
    stacked(body, [(0.058, 0.0280), (0.074, 0.0320), (0.088, 0.0310), (0.096, 0.0250)],
            segments=28)
    bolt_ring(body, (0.0, 0.076, 0.0), (0.0, 1.0, 0.0), 0.0255, 8, 0.0032, 0.0035)
    stacked(body, [(-0.082, 0.0150), (-0.074, 0.0170), (-0.064, 0.0140)], segments=24,
            cap_start=False)
    for index in range(8):
        angle = index * TAU / 8.0
        ux, uz = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.017, -0.074, uz * 0.017), (-uz, 0.0, ux), (0.0, 1.0, 0.0),
                     (ux, 0.0, uz), 0.006, 0.004, 0.004, 0.001, 2)

    # Fuze collar: the threaded joint between the body and the fuze head.
    tube(body, (0.0, 0.096, 0.0), (0.0, 0.128, 0.0), 0.0225, 26, radius_end=0.0205, steps=2)
    for index in range(6):
        ring_collar(body, (0.0, 0.100 + index * 0.005, 0.0), (0.0, 0.1025 + index * 0.005, 0.0),
                    0.0235, 0.0215, 26)
    # Fuze head with its side witness holes and the striker well on top.
    stacked(body, [(0.128, 0.0205), (0.140, 0.0235), (0.152, 0.0225), (0.158, 0.0165)],
            segments=26)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uz = math.cos(angle), math.sin(angle)
        tube(body, (ux * 0.019, 0.140, uz * 0.019), (ux * 0.025, 0.140, uz * 0.025), 0.0055, 12)
    stacked(body, [(0.158, 0.0125), (0.170, 0.0135), (0.178, 0.0110)], segments=20)
    # Striker: a proud pin in a collar, with the lever's pivot fork behind it.
    tube(body, (0.0, 0.178, 0.0), (0.0, 0.196, 0.0), 0.0075, 16, radius_end=0.0055, steps=2)
    ring_collar(body, (0.0, 0.174, 0.0), (0.0, 0.180, 0.0), 0.0105, 0.0075, 16)
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.014, 0.150, -0.020), (side * 0.014, 0.150, 0.018),
                     (side * 0.014, 0.170, 0.014), (side * 0.014, 0.170, -0.016)],
              (side * 0.005, 0.0, 0.0))
    # Safety lever (spoon): folded strip down the side, hinge at the top, with
    # its own raised stiffening rib.
    spoon = [(0.020, 0.176, 0.0), (0.030, 0.150, 0.0), (0.036, 0.114, 0.0),
             (0.036, 0.070, 0.0), (0.030, 0.020, 0.0), (0.024, -0.020, 0.0),
             (0.018, -0.050, 0.0)]
    ribbon(body, spoon, (1.0, 0.0, 0.0), 0.0155, 0.0035)
    ribbon(body, [(p[0] + 0.004, p[1], p[2]) for p in spoon], (1.0, 0.0, 0.0), 0.0055, 0.0028)
    torus_arc(body, (0.020, 0.178, 0.0), (0.0, 0.0, 1.0), 0.0085, 0.0032, 0.0, math.pi,
              segments=10, arc_segments=6)
    # Pull ring and its safety clip under the spoon tail.
    torus_arc(body, (0.046, 0.000, 0.0), (1.0, 0.0, 0.0), 0.020, 0.0042, 0.0, TAU,
              segments=24, arc_segments=7)
    ribbon(body, [(0.024, -0.018, 0.0), (0.040, -0.014, 0.0), (0.052, -0.004, 0.0)],
           (0.0, 0.0, 1.0), 0.0055, 0.0028)
    oriented_box(body, (0.018, -0.048, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.013, 0.008, 0.0035, 0.0012, 2)
    # Two witness bands low on the casing, proud of the grooves.
    for y in (-0.024, -0.038):
        radius = radius_at(casing, y) + 0.0022
        stacked(body, [(y, radius), (y + 0.007, radius)], segments=32)
    return [("body", "ds_p_hull", body)]


def build_flashbang():
    """M84-style flashbang.

    The defining read is the perforated steel tube, so the holes are real
    geometry: `body_of_revolution` gives the tube and a lattice of recessed
    tubes cuts the two staggered rows. Above it sits the fuze head with its
    spoon, hinge pin and pull ring, below it the crimped base cap.
    """
    body = Builder()
    tube_stations = [(-0.062, 0.0160), (-0.052, 0.0300), (-0.040, 0.0362), (-0.020, 0.0386),
                     (0.004, 0.0394), (0.028, 0.0384), (0.042, 0.0356), (0.050, 0.0290)]
    stacked(body, tube_stations, segments=30)
    # The perforation: six rows of six holes, plus four staggered rows between
    # them, so the pattern reads as a real drilled matrix.
    for row in range(6):
        hole_row(body, tube_stations, -0.036 + row * 0.0165, 6, 0.0, 0.0042)
    for row in range(4):
        hole_row(body, tube_stations, -0.0275 + row * 0.0165, 6, TAU / 12.0, 0.0038)
    # Crimp rings top and bottom, and the base cap.
    ring_collar(body, (0.0, 0.048, 0.0), (0.0, 0.056, 0.0), 0.0325, 0.0280, 30)
    ring_collar(body, (0.0, -0.068, 0.0), (0.0, -0.060, 0.0), 0.0195, 0.0150, 26)
    stacked(body, [(-0.080, 0.0230), (-0.070, 0.0292), (-0.052, 0.0280)], segments=26)
    bolt_ring(body, (0.0, -0.076, 0.0), (0.0, -1.0, 0.0), 0.0165, 6, 0.0030, 0.0032)
    # Fuze head: threaded collar, head body, spoon hinge and striker.
    tube(body, (0.0, 0.056, 0.0), (0.0, 0.086, 0.0), 0.0185, 24, radius_end=0.0170, steps=2)
    for index in range(5):
        ring_collar(body, (0.0, 0.060 + index * 0.005, 0.0), (0.0, 0.0625 + index * 0.005, 0.0),
                    0.0195, 0.0175, 24)
    stacked(body, [(0.086, 0.0170), (0.098, 0.0195), (0.108, 0.0185), (0.114, 0.0125)],
            segments=24)
    tube(body, (0.0, 0.114, 0.0), (0.0, 0.128, 0.0), 0.0065, 14, radius_end=0.0048, steps=2)
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.012, 0.096, -0.018), (side * 0.012, 0.096, 0.016),
                     (side * 0.012, 0.114, 0.012), (side * 0.012, 0.114, -0.014)],
              (side * 0.004, 0.0, 0.0))
    # Spoon down the flank with its stiffening rib, and the hinge pin crossways.
    spoon = [(0.017, 0.116, 0.0), (0.026, 0.096, 0.0), (0.032, 0.064, 0.0),
             (0.032, 0.026, 0.0), (0.028, -0.020, 0.0), (0.022, -0.056, 0.0)]
    ribbon(body, spoon, (1.0, 0.0, 0.0), 0.0140, 0.0032)
    ribbon(body, [(p[0] + 0.004, p[1], p[2]) for p in spoon], (1.0, 0.0, 0.0), 0.0050, 0.0026)
    tube(body, (-0.016, 0.118, 0.0), (0.016, 0.118, 0.0), 0.0032, 12)
    # Pull ring on its clip under the spoon tail.
    torus_arc(body, (0.042, 0.004, 0.0), (1.0, 0.0, 0.0), 0.0185, 0.0038, 0.0, TAU,
              segments=22, arc_segments=7)
    ribbon(body, [(0.020, -0.016, 0.0), (0.036, -0.012, 0.0), (0.048, -0.002, 0.0)],
           (0.0, 0.0, 1.0), 0.0050, 0.0026)
    # Safety clip: a second, wider ribbon wired to the ring.
    ribbon(body, [(0.020, -0.030, 0.0), (0.042, -0.030, 0.0), (0.056, -0.014, 0.0)],
           (0.0, 0.0, 1.0), 0.0035, 0.0024)
    oriented_box(body, (0.020, -0.056, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.012, 0.007, 0.0032, 0.0012, 2)
    return [("body", "ds_p_hull", body)]


def build_semtex():
    """Wrapped demolition brick: sheet backing, wrapped sheet and det cord."""
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.230, 0.092, 0.150), 0.012, corner_segments=4)
    # Wrapper: a proud panel grid on every face, so the seams cross the whole
    # brick, plus the folded end flaps the wrapper really has.
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.116, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.068, 0.038, 3, 2, 0.005, 0.62, 0.003, 3)
        for index in range(4):
            oriented_box(body, (side * 0.118, -0.048 + index * 0.032, 0.072),
                         (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (side, 0.0, 0.0),
                         0.010, 0.020, 0.006, 0.002, 2)
    panel_grid(body, (0.0, 0.048, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.105, 0.068, 4, 3, 0.005, 0.62, 0.003, 3)
    panel_grid(body, (0.0, -0.048, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0),
               0.105, 0.068, 4, 3, 0.005, 0.62, 0.003, 3)
    bolt_row(body, (-0.100, 0.050, -0.070), (0.100, 0.050, -0.070), (0.0, 1.0, 0.0), 7,
             0.0032, 0.0035)
    bolt_row(body, (-0.100, 0.050, 0.070), (0.100, 0.050, 0.070), (0.0, 1.0, 0.0), 7,
             0.0032, 0.0035)
    # The wrapper's folded end panels, which is where a wrapped brick always
    # shows its seams, plus the printed lot-number blocks on them.
    for end in (-1.0, 1.0):
        panel_grid(body, (end * 0.116, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (end, 0.0, 0.0), 0.068, 0.038, 3, 2, 0.005, 0.62, 0.003, 3)
        for index in range(3):
            oriented_box(body, (end * 0.120, -0.020 + index * 0.020, -0.020), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), (end, 0.0, 0.0), 0.030, 0.008, 0.004, 0.0015, 2)
        for side in (-1.0, 1.0):
            bolt_row(body, (end * 0.118, side * 0.044, -0.060), (end * 0.118, side * 0.044, 0.060),
                     (end, 0.0, 0.0), 5, 0.0030, 0.0032)
    # Paper backing sheet behind the brick, slightly proud on all sides.
    plate(body, [(-0.125, 0.050, -0.082), (0.125, 0.050, -0.082), (0.125, 0.050, 0.082),
                 (-0.125, 0.050, 0.082)], (0.0, 0.008, 0.0))
    plate(body, [(-0.118, 0.056, -0.040), (0.118, 0.056, -0.040), (0.118, 0.056, 0.060),
                 (-0.118, 0.056, 0.060)], (0.0, 0.005, 0.0))
    # Detonator with a timer face, keypad, a cord loop and the cord run.
    rounded_box(body, (0.0, 0.072, 0.0), (0.140, 0.036, 0.096), 0.008, corner_segments=3)
    ring_collar(body, (0.0, 0.086, 0.0), (0.0, 0.094, 0.0), 0.026, 0.020, 20)
    tube(body, (0.0, 0.094, 0.0), (0.0, 0.102, 0.0), 0.020, 18, radius_end=0.016, steps=2)
    for column in range(3):
        for row in range(2):
            oriented_box(body, ((column - 1) * 0.026, 0.091, -0.038 + row * 0.020),
                         (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         0.010, 0.008, 0.004, 0.0015, 2)
    bolt_ring(body, (0.0, 0.091, 0.060), (0.0, 1.0, 0.0), 0.036, 6, 0.0035, 0.0038)
    torus_arc(body, (0.0, 0.096, 0.0), (1.0, 0.0, 0.0), 0.026, 0.0045, 0.0, TAU,
              segments=16, arc_segments=6)
    # Detonator cord: a routed run over the wrapper into the brick, held down by
    # real clips at the control points.
    cord = [(0.030, 0.058, 0.0), (0.060, 0.040, 0.030), (0.100, 0.010, 0.055),
            (0.116, -0.020, 0.062)]
    swept_tube(body, cord, 0.0068, 10)
    for index in range(len(cord) - 1):
        middle = vmul(vadd(cord[index], cord[index + 1]), 0.5)
        oriented_box(body, vadd(middle, (0.0, 0.0, 0.002)), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), 0.010, 0.006, 0.004, 0.0012, 2)
    ring_collar(body, (0.116, -0.020, 0.048), (0.116, -0.020, 0.062), 0.011, 0.0068, 12)
    # Second cord run: the detonator's return lead, clipped along the lower edge.
    lead = [(-0.040, 0.040, -0.048), (-0.010, 0.014, -0.060), (0.060, -0.010, -0.062),
            (0.108, -0.030, -0.048)]
    swept_tube(body, lead, 0.0052, 10)
    for index in range(len(lead) - 1):
        middle = vmul(vadd(lead[index], lead[index + 1]), 0.5)
        oriented_box(body, middle, (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     0.009, 0.005, 0.004, 0.0012, 2)
    ring_collar(body, (-0.040, 0.040, -0.060), (-0.040, 0.040, -0.048), 0.009, 0.0052, 12)
    # `equipment_system` drives the stuck-charge blink by name, so the mesh it
    # tints keeps the asset's own name rather than a role name.
    return [("equipment_semtex", "ds_p_hull", body)]


def build_throwing_knife():
    """The thrown projectile: a tapered flat with a fuller and a cord wrap.

    `VisualFactory.create_equipment("knife")` maps to this asset and the thrown
    projectile spins the whole root, so the blade lies along local Z the way the
    ported model did. The blade keeps that plane and gains a real grind — a
    fuller ridge, a serrated heel, a ricasso, a guard, individual cord turns and
    a pommel — at twice the station count the ported flat had.
    """
    blade = Builder()
    stations = [(-0.230, 0.0010, 0.0000), (-0.208, 0.0017, 0.0125), (-0.186, 0.0023, 0.0170),
                (-0.164, 0.0028, 0.0215), (-0.142, 0.0031, 0.0245), (-0.120, 0.0032, 0.0250),
                (-0.098, 0.0035, 0.0285), (-0.076, 0.0037, 0.0295), (-0.054, 0.0039, 0.0300),
                (-0.032, 0.0039, 0.0296), (-0.010, 0.0040, 0.0290), (0.020, 0.0040, 0.0260)]
    edge = [0.0, -0.0300, -0.0520, -0.0430, -0.0340, -0.0300, -0.0230, -0.0190, -0.0160,
            -0.0120, -0.0080, -0.0040]
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
            # Fuller: a proud ridge down the middle of each flat, one prism per
            # station, so the blade reads as ground stock rather than a plane.
            span = 0.5 * (z0 + z1)
            depth = 0.5 * (e0 + spine0 * 0.72 + e1 + spine1 * 0.72)
            oriented_box(blade, (side * half0 * 0.62, depth, span), (0.0, 1.0, 0.0),
                         (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                         0.0016 * (index + 3), e1 - e0 + 0.006, abs(z1 - z0) * 0.45,
                         0.0008, 2)
    # Serrated heel: a tooth at every station pair along the rear third.
    for index in range(6):
        z = -0.206 + index * 0.024
        half = stations[index + 1][1]
        e = edge[index + 1]
        for side in (-1.0, 1.0):
            oriented_box(blade, (side * half * 0.9, e + 0.004, z), (0.0, 1.0, 0.0),
                         (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                         0.0028, 0.0075, 0.0034, 0.0010, 2)
    # Ricasso, guard block, the two guard wings and their bolts.
    rounded_box(blade, (0.0, 0.008, 0.030), (0.0125, 0.0370, 0.022), 0.0028, corner_segments=3)
    oriented_box(blade, (0.0, 0.008, 0.045), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                 0.0165, 0.0075, 0.0065, 0.0024, 3)
    for side in (-1.0, 1.0):
        plate(blade, [(side * 0.014, 0.000, 0.040), (side * 0.031, 0.008, 0.053),
                      (side * 0.031, 0.017, 0.041), (side * 0.014, 0.009, 0.030)],
              (side * 0.006, 0.0, 0.0))
        bolt_row(blade, (side * 0.017, 0.008, 0.038), (side * 0.017, 0.008, 0.051),
                 (side, 0.0, 0.0), 2, 0.0022, 0.0024)
    parts = [("blade", "ds_p_bright", blade)]

    # Cord wrap: fourteen individual turns over a visible tang, each with its own
    # slight tilt, plus the two exposed shoulders and the knot ends.
    grip = Builder()
    rounded_box(grip, (0.0, 0.004, 0.108), (0.0200, 0.0300, 0.130), 0.004, corner_segments=3)
    for index in range(14):
        z = 0.052 + index * 0.0092
        tilt = 0.0045 * math.sin(index * 1.1)
        for side in (-1.0, 1.0):
            oriented_box(grip, (side * 0.0092, 0.002 + tilt, z), (0.0, 1.0, 0.0),
                         (0.0, 0.0, 1.0), (side, 0.0, 0.0), 0.0076, 0.0125, 0.0038,
                         0.0014, 3)
            oriented_box(grip, (0.0, side * 0.0150, z - tilt), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                         (0.0, side, 0.0), 0.0092, 0.0125, 0.0036, 0.0014, 3)
    for side in (-1.0, 1.0):
        torus_arc(grip, (side * 0.012, 0.024, 0.054), (0.0, 0.0, 1.0), 0.008, 0.0026, 0.0,
                  TAU, segments=12, arc_segments=6)
    tube(grip, (0.0, 0.024, 0.054), (0.0, 0.030, 0.058), 0.0035, 10, steps=2)
    # Pommel with its lanyard hole and the retention ring.
    rounded_box(grip, (0.0, 0.004, 0.168), (0.0250, 0.0350, 0.022), 0.005, corner_segments=3)
    tube(grip, (0.0, 0.004, 0.174), (0.0, 0.004, 0.180), 0.0045, 12)
    torus_arc(grip, (0.0, 0.024, 0.180), (1.0, 0.0, 0.0), 0.011, 0.0032, 0.0, TAU,
              segments=14, arc_segments=6)
    parts.append(("grip", "ds_p_wood", grip))
    return parts


def build_claymore():
    """M18-style directional mine: curved plate, legs, sight and connector."""
    body = Builder()
    # The fragmentation plate: a genuinely curved front face, lofted from a
    # shallow arc so the silhouette is convex rather than a flat box.
    frames = []
    for index in range(7):
        u = -1.0 + index / 3.0
        bulge = 0.030 * math.cos(u * 1.35)
        frames.append(((u * 0.235, 0.070, bulge), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                       (1.0, 0.0, 0.0)))
    sweep(body, profile_rounded_rect(0.048, 0.142, 0.012, 4), frames, True, True)
    # The fragment matrix on the curved face: six columns by seven rows of tiles
    # standing proud along the face normal, so the gaps between them are the
    # crossing grooves.
    for column in range(6):
        u = -5.0 / 6.0 + column / 3.0
        bulge = 0.030 * math.cos(u * 1.35)
        normal = vnorm((-0.030 * 1.35 * math.sin(u * 1.35), 0.0, 1.0))
        surface = (u * 0.235 + normal[0] * 0.048, 0.070, bulge + normal[2] * 0.048)
        for row in range(7):
            y = -0.050 + row * 0.040
            oriented_box(body, (surface[0], y, surface[2]), (normal[2], 0.0, -normal[0]),
                         (0.0, 1.0, 0.0), normal, 0.0300, 0.0130, 0.0055, 0.0016, 2)
    # Rear case: a panelled shell behind the plate with its own bolts.
    rounded_box(body, (0.0, 0.070, -0.062), (0.420, 0.230, 0.056), 0.010, corner_segments=4)
    panel_grid(body, (0.0, 0.070, -0.091), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0),
               0.150, 0.080, 4, 3, 0.005, 0.62, 0.003, 3)
    bolt_row(body, (-0.180, 0.160, -0.088), (0.180, 0.160, -0.088), (0.0, 0.0, -1.0), 8,
             0.0034, 0.0036)
    bolt_row(body, (-0.180, -0.020, -0.088), (0.180, -0.020, -0.088), (0.0, 0.0, -1.0), 8,
             0.0034, 0.0036)
    # Folding legs: hinge block, strut, foot and the retention clip.
    for side in (-1.0, 1.0):
        tube(body, (side * 0.118, 0.070, -0.094), (side * 0.118, 0.070, -0.112), 0.012, 16,
             steps=2)
        ring_collar(body, (side * 0.118, 0.070, -0.092), (side * 0.118, 0.070, -0.084), 0.016,
                    0.012, 16)
        swept_tube(body, [(side * 0.118, 0.046, -0.106), (side * 0.146, -0.008, -0.108),
                          (side * 0.156, -0.096, -0.100)], 0.0075, 10)
        oriented_box(body, (side * 0.156, -0.108, -0.100), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), 0.026, 0.022, 0.006, 0.002, 2)
        bolt_row(body, (side * 0.118, 0.070, -0.118), (side * 0.118, -0.060, -0.118),
                 (0.0, 0.0, -1.0), 4, 0.0032, 0.0034)
    # Integral aiming sight: a folding blade with graduations and a rear notch.
    plate(body, [(0.0, 0.070, 0.092), (0.024, 0.070, 0.092), (0.020, 0.126, 0.070),
                 (0.004, 0.126, 0.070)], (-0.012, 0.0, 0.0))
    oriented_box(body, (0.012, 0.086, 0.086), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                 0.010, 0.020, 0.007, 0.002, 2)
    for index in range(4):
        oriented_box(body, (0.012, 0.096 + index * 0.014, 0.078), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), (1.0, 0.0, 0.0), 0.012, 0.0035, 0.006, 0.0012, 2)
    tube(body, (-0.024, 0.070, 0.090), (0.024, 0.070, 0.090), 0.0045, 12)
    # Wire connector well and its two contacts.
    rounded_box(body, (0.0, 0.070, -0.096), (0.070, 0.048, 0.026), 0.006, corner_segments=3)
    for side in (-1.0, 1.0):
        tube(body, (side * 0.014, 0.070, -0.100), (side * 0.014, 0.070, -0.116), 0.0068, 12,
             steps=2)
        ring_collar(body, (side * 0.014, 0.070, -0.098), (side * 0.014, 0.070, -0.092), 0.010,
                    0.0068, 12)
    return [("body", "ds_p_hull", body)]


def build_c4():
    """Moulded demolition charge with an embedded detonator and a wire run."""
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.320, 0.120, 0.220), 0.014, corner_segments=4)
    # Wrapper seam: a proud band all the way round, with the wrapper's panels
    # either side of it and the folded flaps at the ends.
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.161, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.098, 0.048, 4, 2, 0.005, 0.60, 0.003, 3)
        bolt_row(body, (side * 0.162, 0.058, -0.090), (side * 0.162, 0.058, 0.090),
                 (side, 0.0, 0.0), 7, 0.0032, 0.0035)
    panel_grid(body, (0.0, 0.062, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.150, 0.100, 5, 3, 0.005, 0.60, 0.003, 3)
    panel_grid(body, (0.0, -0.062, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0),
               0.150, 0.100, 5, 3, 0.005, 0.60, 0.003, 3)
    oriented_box(body, (0.0, 0.0, 0.112), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0),
                 0.156, 0.056, 0.006, 0.002, 3)
    for side in (-1.0, 1.0):
        oriented_box(body, (0.0, side * 0.062, 0.108), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, side, 0.0), 0.150, 0.014, 0.005, 0.0016, 2)
    # The wrapper's end panels and the stencil blocks printed on them.
    for end_x in (-1.0, 1.0):
        panel_grid(body, (end_x * 0.161, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (end_x, 0.0, 0.0), 0.098, 0.048, 4, 2, 0.005, 0.60, 0.003, 3)
        for index in range(3):
            oriented_box(body, (end_x * 0.166, -0.030 + index * 0.030, -0.030), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), (end_x, 0.0, 0.0), 0.040, 0.010, 0.004, 0.0015, 2)
    # Embedded detonator: well, body, timer face with its keypad and display.
    rounded_box(body, (0.062, 0.030, -0.046), (0.120, 0.096, 0.110), 0.010, corner_segments=3)
    ring_collar(body, (0.062, 0.030, -0.012), (0.062, 0.030, 0.002), 0.034, 0.026, 20)
    tube(body, (0.098, 0.046, -0.060), (0.110, 0.058, -0.072), 0.008, 14, steps=2)
    oriented_box(body, (0.062, 0.084, -0.046), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                 0.044, 0.032, 0.005, 0.002, 2)
    for column in range(3):
        for row in range(2):
            oriented_box(body, (0.030 + column * 0.020, 0.086, -0.088 + row * 0.022),
                         (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         0.008, 0.007, 0.004, 0.0015, 2)
    bolt_ring(body, (0.062, 0.086, -0.046), (0.0, 1.0, 0.0), 0.040, 6, 0.0035, 0.0038)
    # Wire run: a routed lead from the detonator round the block to the blasting
    # cap pocket, held down by real clips.
    swept_tube(body, [(0.110, 0.058, -0.072), (0.146, 0.050, -0.114),
                      (0.100, 0.020, -0.150), (0.020, -0.010, -0.156),
                      (-0.070, -0.030, -0.148)], 0.0048, 12)
    for t in (0.12, 0.34, 0.58, 0.82):
        position = (0.135 - t * 0.190, 0.052 - t * 0.075, -0.100 - t * 0.052)
        oriented_box(body, position, (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     0.008, 0.006, 0.004, 0.0012, 2)
    ring_collar(body, (0.062, 0.030, -0.008), (0.062, 0.030, 0.002), 0.028, 0.020, 18)
    parts = [("body", "ds_p_hull", body)]
    led = Builder()
    tube(led, (-0.100, 0.064, 0.0), (-0.100, 0.076, 0.0), 0.009, 14, steps=2)
    ring_collar(led, (-0.100, 0.062, 0.0), (-0.100, 0.068, 0.0), 0.013, 0.009, 14)
    # `equipment_system` pulses this LED by name (`part_3`), as the ported asset
    # named it, so the name is part of the contract rather than descriptive.
    parts.append(("part_3", "ds_p_red", led))
    return parts


def build_stun():
    """Nine-bang: a segmented body with a vented can and a full fuze group."""
    body = Builder()
    can = [(-0.058, 0.0200), (-0.046, 0.0440), (-0.030, 0.0520), (0.0, 0.0545),
           (0.034, 0.0530), (0.050, 0.0470), (0.060, 0.0340)]
    stacked(body, can, segments=38)
    for index in range(5):
        y = -0.040 + index * 0.022
        radius = radius_at(can, y) + 0.0035
        stacked(body, [(y, radius), (y + 0.005, radius)], segments=38)
    # Printed label matrix on the lower half, clear of the vent band.
    curved_grid(body, can, 14, 2, -0.052, -0.006, depth=0.0026, fill=0.68)
    # Vent band: four rows of six holes through the shoulder, staggered row to
    # row so the band reads as a proper drilled vent.
    for row in range(4):
        hole_row(body, can, 0.006 + row * 0.013, 6, row * TAU / 12.0, 0.0036)
    ring_collar(body, (0.0, -0.062, 0.0), (0.0, -0.054, 0.0), 0.024, 0.018, 24)
    ring_collar(body, (0.0, 0.056, 0.0), (0.0, 0.064, 0.0), 0.038, 0.030, 26)
    stacked(body, [(-0.078, 0.036), (-0.068, 0.046), (-0.046, 0.044)], segments=26,
            cap_start=False)
    bolt_ring(body, (0.0, -0.072, 0.0), (0.0, -1.0, 0.0), 0.026, 6, 0.0032, 0.0034)
    # Fuze head and its striker.
    tube(body, (0.0, 0.060, 0.0), (0.0, 0.088, 0.0), 0.019, 22, radius_end=0.0175, steps=2)
    stacked(body, [(0.088, 0.0175), (0.100, 0.0200), (0.110, 0.0190), (0.116, 0.0130)],
            segments=22)
    tube(body, (0.0, 0.116, 0.0), (0.0, 0.130, 0.0), 0.0068, 14, radius_end=0.0050, steps=2)
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.012, 0.098, -0.017), (side * 0.012, 0.098, 0.015),
                     (side * 0.012, 0.116, 0.011), (side * 0.012, 0.116, -0.013)],
              (side * 0.004, 0.0, 0.0))
    # Spoon, hinge, pull ring and safety clip.
    spoon = [(0.018, 0.118, 0.0), (0.028, 0.096, 0.0), (0.034, 0.060, 0.0),
             (0.034, 0.018, 0.0), (0.028, -0.030, 0.0), (0.022, -0.062, 0.0)]
    ribbon(body, spoon, (1.0, 0.0, 0.0), 0.0145, 0.0032)
    ribbon(body, [(p[0] + 0.004, p[1], p[2]) for p in spoon], (1.0, 0.0, 0.0), 0.0050, 0.0026)
    tube(body, (-0.016, 0.120, 0.0), (0.016, 0.120, 0.0), 0.0032, 12)
    torus_arc(body, (0.044, 0.000, 0.0), (1.0, 0.0, 0.0), 0.019, 0.0038, 0.0, TAU,
              segments=22, arc_segments=7)
    ribbon(body, [(0.020, -0.018, 0.0), (0.038, -0.012, 0.0), (0.050, -0.002, 0.0)],
           (0.0, 0.0, 1.0), 0.0050, 0.0026)
    oriented_box(body, (0.020, -0.058, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                 0.012, 0.007, 0.0032, 0.0012, 2)
    return [("body", "ds_p_hull", body)]


def build_smoke():
    """Smoke canister: vented top, pull ring, crimped base, label seam."""
    body = Builder()
    can = [(-0.128, 0.0200), (-0.120, 0.0400), (-0.106, 0.0560), (-0.088, 0.0620),
           (-0.040, 0.0655), (0.020, 0.0660), (0.070, 0.0650), (0.090, 0.0620),
           (0.104, 0.0540), (0.112, 0.0420), (0.118, 0.0280)]
    stacked(body, can, segments=40)
    # Three label seams splitting the can into quarters, so the can reads as a
    # rolled tube with real joints rather than one smooth cylinder.
    for y in (-0.052, 0.006, 0.064):
        stacked(body, [(y, radius_at(can, y) + 0.0030), (y + 0.006, radius_at(can, y) + 0.0030)],
                segments=40)
    # Printed label: a matrix of proud blocks between the seams, whose gaps are
    # the printed lines.
    curved_grid(body, can, 16, 2, -0.042, 0.000, depth=0.0026, fill=0.68)
    curved_grid(body, can, 16, 2, 0.016, 0.058, depth=0.0026, fill=0.68)
    bolt_row(body, (-0.055, 0.010, 0.060), (0.055, 0.010, 0.060), (0.0, 0.0, 1.0), 6,
             0.0032, 0.0034)
    bolt_row(body, (-0.055, 0.010, -0.060), (0.055, 0.010, -0.060), (0.0, 0.0, -1.0), 6,
             0.0032, 0.0034)
    # Vented top: a crimped rim, a drilled cap and four emission ports.
    ring_collar(body, (0.0, 0.114, 0.0), (0.0, 0.122, 0.0), 0.034, 0.027, 28)
    stacked(body, [(0.118, 0.0270), (0.132, 0.0320), (0.146, 0.0300), (0.152, 0.0220)],
            segments=28)
    for index in range(6):
        angle = index * TAU / 6.0
        ux, uz = math.cos(angle), math.sin(angle)
        tube(body, (ux * 0.020, 0.146, uz * 0.020), (ux * 0.028, 0.146, uz * 0.028), 0.0058,
             12, cap_start=False, cap_end=False)
    tube(body, (0.0, 0.152, 0.0), (0.0, 0.170, 0.0), 0.011, 18, radius_end=0.0090, steps=2)
    # Pull ring, its ring post and the safety pin through the fuze.
    torus_arc(body, (0.0, 0.182, 0.0), (1.0, 0.0, 0.0), 0.021, 0.0042, 0.0, TAU,
              segments=24, arc_segments=7)
    tube(body, (0.0, 0.170, 0.0), (0.0, 0.176, 0.0), 0.0058, 12)
    tube(body, (-0.026, 0.164, 0.0), (0.026, 0.164, 0.0), 0.0028, 12)
    tube(body, (0.0, 0.164, -0.026), (0.0, 0.164, 0.026), 0.0028, 12)
    # Base crimp and the standing base ring.
    ring_collar(body, (0.0, -0.130, 0.0), (0.0, -0.122, 0.0), 0.0230, 0.0190, 26)
    stacked(body, [(-0.142, 0.0320), (-0.136, 0.0400), (-0.120, 0.0400)], segments=26,
            cap_start=False)
    bolt_ring(body, (0.0, -0.136, 0.0), (0.0, -1.0, 0.0), 0.030, 6, 0.0032, 0.0034)
    return [("body", "ds_p_hull", body)]


def build_molotov():
    """Moulded bottle: shoulder, neck, cork with a rag wick and a liquid line."""
    bottle = Builder()
    profile = [(-0.150, 0.0240), (-0.142, 0.0420), (-0.126, 0.0530), (-0.100, 0.0580),
               (-0.060, 0.0605), (0.000, 0.0612), (0.060, 0.0600), (0.086, 0.0560),
               (0.100, 0.0480), (0.114, 0.0350), (0.124, 0.0230), (0.134, 0.0180)]
    stacked(bottle, profile, segments=38)
    # Moulding rings down the body and the shoulder's own shoulder seam.
    for y in (-0.110, -0.070, -0.020, 0.040):
        stacked(bottle, [(y, radius_at(profile, y) + 0.0028),
                         (y + 0.006, radius_at(profile, y) + 0.0028)], segments=30)
    stacked(bottle, [(0.096, radius_at(profile, 0.096) + 0.0032),
                     (0.102, radius_at(profile, 0.102) + 0.0032)], segments=30)
    # Punched label: a proud panel with its own border and a row of perforations.
    curved_grid(bottle, profile, 16, 3, -0.112, -0.020, depth=0.0024, fill=0.66)
    for index in range(4):
        y = -0.096 + index * 0.030
        radius = radius_at(profile, y)
        for step in range(6):
            angle = step * TAU / 6.0 + (index % 2) * TAU / 12.0
            ux, uz = math.cos(angle), math.sin(angle)
            tube(bottle, (ux * (radius - 0.004), y, uz * (radius - 0.004)),
                 (ux * (radius + 0.0016), y, uz * (radius + 0.0016)), 0.0046, 10,
                 cap_start=False, cap_end=False)
    # The moulded punt the base really has, and a second shoulder ring.
    body_of_revolution(bottle, [(-0.150, 0.0240), (-0.158, 0.0220), (-0.166, 0.0120)],
                       segments=38, cap_start=False)
    stacked(bottle, [(0.116, radius_at(profile, 0.116) + 0.0026),
                     (0.122, radius_at(profile, 0.122) + 0.0026)], segments=38)
    # Neck finish: the thread ring, the lip and the cork inside it.
    ring_collar(bottle, (0.0, 0.130, 0.0), (0.0, 0.138, 0.0), 0.0210, 0.0180, 24)
    ring_collar(bottle, (0.0, 0.138, 0.0), (0.0, 0.146, 0.0), 0.0195, 0.0165, 24)
    parts = [("bottle", "ds_p_lens", bottle)]

    wick = Builder()
    stacked(wick, [(0.134, 0.0165), (0.150, 0.0180), (0.166, 0.0165)], segments=22)
    for index in range(3):
        ring_collar(wick, (0.0, 0.140 + index * 0.008, 0.0), (0.0, 0.143 + index * 0.008, 0.0),
                    0.0195, 0.0160, 22)
    swept_tube(wick, [(0.0, 0.166, 0.0), (0.008, 0.190, 0.004), (0.016, 0.212, 0.010),
                      (0.022, 0.232, 0.016)], (0.0085, 0.0080, 0.0074, 0.0068), 10)
    for index in range(3):
        torus_arc(wick, (0.006 + index * 0.006, 0.188 + index * 0.016, 0.003 + index * 0.004),
                  (1.0, 0.0, 0.3), 0.0095, 0.0026, 0.0, TAU, segments=12, arc_segments=6)
    parts.append(("wick", "ds_p_wood", wick))

    flame = Builder()
    tube(flame, (0.022, 0.232, 0.016), (0.028, 0.272, 0.024), 0.0125, 16, radius_end=0.0040,
         steps=3)
    torus_arc(flame, (0.024, 0.244, 0.018), (1.0, 0.0, 0.2), 0.010, 0.0030, 0.0, TAU,
              segments=12, arc_segments=6)
    parts.append(("flame", "ds_p_lamp", flame))
    return parts


def build_thermite():
    """Thermite charge: lid with a striker strip, vented base, side vents."""
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.280, 0.320, 0.280), 0.016, corner_segments=4)
    # Panelled flanks and lid with the vented base collar below.
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.141, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.090, 0.100, 3, 4, 0.005, 0.62, 0.003, 3)
        bolt_row(body, (side * 0.142, 0.140, -0.110), (side * 0.142, 0.140, 0.110),
                 (side, 0.0, 0.0), 6, 0.0034, 0.0036)
        # Side vents cut into the shell.
        for index in range(4):
            z = -0.090 + index * 0.060
            for row in range(3):
                y = -0.090 + row * 0.070
                oriented_box(body, (side * 0.142, y, z), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                             (side, 0.0, 0.0), 0.020, 0.024, 0.005, 0.0016, 2)
    for face in (-1.0, 1.0):
        panel_grid(body, (0.0, 0.0, face * 0.141), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                   (0.0, 0.0, face), 0.110, 0.120, 4, 4, 0.005, 0.62, 0.003, 3)
    # Lid: a proud cap with a rim, hinges, latches and the striker strip.
    rounded_box(body, (0.0, 0.174, 0.0), (0.300, 0.056, 0.300), 0.014, corner_segments=4)
    ring_collar(body, (0.0, 0.146, 0.0), (0.0, 0.152, 0.0), 0.148, 0.140, 26)
    for side in (-1.0, 1.0):
        oriented_box(body, (side * 0.110, 0.152, 0.150), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     (0.0, 0.0, 1.0), 0.036, 0.012, 0.008, 0.002, 2)
        torus_arc(body, (side * 0.110, 0.182, 0.150), (1.0, 0.0, 0.0), 0.022, 0.0042, 0.0,
                  math.pi, segments=10, arc_segments=6)
        oriented_box(body, (side * 0.150, 0.160, -0.090), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.028, 0.016, 0.008, 0.002, 2)
    bolt_ring(body, (0.0, 0.202, 0.0), (0.0, 1.0, 0.0), 0.124, 10, 0.0045, 0.005)
    # Striker strip along the lid's top face, with its cap and lanyard ring.
    oriented_box(body, (0.0, 0.204, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                 0.130, 0.026, 0.006, 0.002, 2)
    for index in range(9):
        oriented_box(body, (-0.100 + index * 0.025, 0.208, 0.0), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.0055, 0.022, 0.005, 0.0012, 2)
    tube(body, (0.0, 0.208, 0.046), (0.0, 0.208, 0.056), 0.010, 16, radius_end=0.008, steps=2)
    torus_arc(body, (0.0, 0.218, 0.062), (1.0, 0.0, 0.0), 0.014, 0.0034, 0.0, TAU,
              segments=16, arc_segments=6)
    # Vented base: a standoff ring with real ports around it.
    ring_collar(body, (0.0, -0.160, 0.0), (0.0, -0.152, 0.0), 0.128, 0.116, 24)
    stacked(body, [(-0.186, 0.1280), (-0.176, 0.1420), (-0.152, 0.1460)], segments=24,
            cap_start=False)
    for index in range(8):
        angle = index * TAU / 8.0
        ux, uz = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.143, -0.176, uz * 0.143), (-uz, 0.0, ux), (0.0, 1.0, 0.0),
                     (ux, 0.0, uz), 0.012, 0.014, 0.006, 0.0016, 2)
    parts = [("body", "ds_p_hull", body)]
    glow = Builder()
    tube(glow, (0.0, 0.204, 0.0), (0.0, 0.216, 0.0), 0.116, 26, radius_end=0.108, steps=2)
    parts.append(("glow", "ds_p_lamp", glow))
    return parts


def build_snapshot():
    """Snapshot puck: body, recessed lens, emitter ring and controls."""
    body = Builder()
    rounded_box(body, (0.0, 0.0, 0.0), (0.240, 0.220, 0.240), 0.018, corner_segments=4)
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.121, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.090, 0.080, 3, 3, 0.005, 0.62, 0.003, 3)
    for face in (-1.0, 1.0):
        panel_grid(body, (0.0, face * 0.111, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                   (0.0, face, 0.0), 0.100, 0.100, 3, 3, 0.005, 0.62, 0.003, 3)
    # Lens barrel: a stepped shroud with a proud rim and a glazed front.
    tube(body, (0.0, 0.010, -0.118), (0.0, 0.010, -0.166), 0.038, 24, radius_end=0.032,
         steps=3)
    ring_collar(body, (0.0, 0.010, -0.166), (0.0, 0.010, -0.178), 0.041, 0.033, 24)
    ring_collar(body, (0.0, 0.010, -0.112), (0.0, 0.010, -0.122), 0.042, 0.038, 24)
    bolt_ring(body, (0.0, 0.010, -0.170), (0.0, 0.0, -1.0), 0.036, 8, 0.0035, 0.0038)
    # Emitter ring behind the lens: a real segmented arc of diodes.
    for index in range(12):
        angle = index * TAU / 12.0
        ux, uz = math.cos(angle), math.sin(angle)
        tube(body, (ux * 0.045, 0.010 + uz * 0.045, -0.112),
             (ux * 0.050, 0.010 + uz * 0.050, -0.112), 0.0062, 10, cap_start=False,
             cap_end=False)
    ring_collar(body, (0.0, 0.010, -0.104), (0.0, 0.010, -0.112), 0.054, 0.044, 24)
    # Controls: a guarded start button, three selector tabs and a data port.
    ring_collar(body, (0.0, 0.056, -0.070), (0.0, 0.064, -0.070), 0.020, 0.015, 18)
    tube(body, (0.0, 0.056, -0.070), (0.0, 0.072, -0.070), 0.015, 18, radius_end=0.012, steps=2)
    for index in range(3):
        oriented_box(body, (0.0, 0.084, -0.020 + index * 0.026), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), 0.020, 0.010, 0.006, 0.002, 2)
    rounded_box(body, (0.0, 0.062, 0.070), (0.070, 0.030, 0.050), 0.006, corner_segments=3)
    bolt_ring(body, (0.0, 0.076, 0.070), (0.0, 1.0, 0.0), 0.024, 6, 0.0032, 0.0034)
    # Battery cap, its latch and the corner strap lugs.
    tube(body, (0.0, -0.112, 0.0), (0.0, -0.140, 0.0), 0.030, 20, radius_end=0.026, steps=2)
    ring_collar(body, (0.0, -0.108, 0.0), (0.0, -0.116, 0.0), 0.034, 0.029, 20)
    oriented_box(body, (0.0, -0.136, 0.030), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0),
                 0.026, 0.012, 0.006, 0.002, 2)
    for side in (-1.0, 1.0):
        for face in (-1.0, 1.0):
            oriented_box(body, (side * 0.104, 0.0, face * 0.104), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), 0.016, 0.016, 0.006, 0.002, 2)
    parts = [("body", "ds_p_hull", body)]
    lens = Builder()
    tube(lens, (0.0, 0.010, -0.178), (0.0, 0.010, -0.190), 0.030, 20, radius_end=0.026, steps=2)
    ring_collar(lens, (0.0, 0.010, -0.178), (0.0, 0.010, -0.184), 0.033, 0.029, 20)
    parts.append(("lens", "ds_p_green", lens))
    return parts





# --------------------------------------------------------------------------
# Pickups and projectiles.
# --------------------------------------------------------------------------


def build_ammo_pickup():
    """Open ammunition box: a real magazine and modelled rounds inside it."""
    can = Builder()
    rounded_box(can, (0.0, 0.140, 0.0), (0.460, 0.280, 0.340), 0.022, corner_segments=4)
    # Panelled sides and end handles, with the corner brackets a steel box has.
    for side in (-1.0, 1.0):
        panel_grid(can, (side * 0.231, 0.140, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.120, 0.090, 3, 2, 0.005, 0.62, 0.003, 3)
        for face in (-1.0, 1.0):
            swept_tube(can, [(side * 0.200, 0.290, face * 0.120),
                             (side * 0.212, 0.150, face * 0.140),
                             (side * 0.212, 0.030, face * 0.140)], 0.010, 10)
            ring_collar(can, (side * 0.204, 0.284, face * 0.124),
                        (side * 0.212, 0.270, face * 0.128), 0.014, 0.010, 10)
    for face in (-1.0, 1.0):
        panel_grid(can, (0.0, 0.140, face * 0.171), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                   (0.0, 0.0, face), 0.180, 0.090, 4, 2, 0.005, 0.62, 0.003, 3)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            oriented_box(can, (sx * 0.215, 0.140, sz * 0.150), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                         (0.0, 0.0, 1.0), 0.020, 0.136, 0.020, 0.003, 3)
            bolt_row(can, (sx * 0.215, 0.020, sz * 0.150), (sx * 0.215, 0.256, sz * 0.150),
                     (sx, 0.0, 0.0), 4, 0.0032, 0.0034)
    # Lid hinged back on its two hinges, with the latch hasps and a stencil block.
    rounded_box(can, (0.0, 0.298, -0.020), (0.440, 0.036, 0.320), 0.012, corner_segments=3)
    panel_grid(can, (0.0, 0.318, -0.020), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.190, 0.140, 4, 3, 0.005, 0.62, 0.003, 3)
    for side in (-1.0, 1.0):
        torus_arc(can, (side * 0.170, 0.284, 0.140), (1.0, 0.0, 0.0), 0.020, 0.0045, 0.0,
                  math.pi, segments=10, arc_segments=6)
        oriented_box(can, (side * 0.170, 0.290, 0.120), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), 0.024, 0.016, 0.007, 0.002, 2)
        oriented_box(can, (side * 0.130, 0.286, -0.170), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.020, 0.014, 0.007, 0.002, 2)
    # Stencil-plate blocks on the lid and the front face.
    for index in range(4):
        for row in range(2):
            oriented_box(can, (-0.120 + index * 0.060, 0.322, -0.070 + row * 0.045),
                         (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         0.022, 0.014, 0.004, 0.0015, 2)
    # Magazine standing in the tray and the modelled rounds beside it.
    rounded_box(can, (-0.120, 0.190, -0.060), (0.090, 0.220, 0.170), 0.010, corner_segments=3)
    for index in range(6):
        oriented_box(can, (-0.120, 0.088 + index * 0.026, 0.026), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.040, 0.076, 0.004, 0.0015, 2)
    for index in range(6):
        oriented_box(can, (-0.120 - 0.038 + index * 0.015, 0.300, -0.060), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.006, 0.038, 0.006, 0.001, 2)
    oriented_box(can, (-0.120, 0.296, -0.060), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                 0.044, 0.082, 0.004, 0.0015, 2)
    # Loose rounds: cases, shoulders and projectiles, stacked in the tray.
    for index in range(7):
        x = -0.040 + (index % 4) * 0.052
        z = 0.060 + (index // 4) * 0.070
        tube(can, (x - 0.045, 0.062, z), (x + 0.045, 0.062, z), 0.0105, 14, steps=2)
        ring_collar(can, (x + 0.044, 0.062, z), (x + 0.052, 0.062, z), 0.0115, 0.0095, 14)
        cone(can, (x + 0.050, 0.062, z), (x + 0.086, 0.062, z), 0.0085, 12)
        ring_collar(can, (x - 0.048, 0.062, z), (x - 0.040, 0.062, z), 0.0125, 0.0105, 14)
    parts = [("can", "ds_p_crate", can)]
    band = Builder()
    box(band, (0.0, 0.200, 0.0), (0.472, 0.060, 0.352))
    for face in (-1.0, 1.0):
        oriented_box(band, (0.0, 0.200, face * 0.178), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     (0.0, 0.0, face), 0.232, 0.024, 0.005, 0.002, 2)
        oriented_box(band, (face * 0.238, 0.200, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     (face, 0.0, 0.0), 0.172, 0.024, 0.005, 0.002, 2)
    for face in (-1.0, 1.0):
        bolt_row(band, (-0.200, 0.216, face * 0.178), (0.200, 0.216, face * 0.178),
                 (0.0, 0.0, face), 7, 0.0034, 0.0036)
        bolt_row(band, (-0.200, 0.184, face * 0.178), (0.200, 0.184, face * 0.178),
                 (0.0, 0.0, face), 7, 0.0034, 0.0036)
        for side in (-1.0, 1.0):
            bolt_row(band, (side * 0.238, 0.216, -0.150), (side * 0.238, 0.216, 0.150),
                     (side, 0.0, 0.0), 5, 0.0034, 0.0036)
            bolt_row(band, (side * 0.238, 0.184, -0.150), (side * 0.238, 0.184, 0.150),
                     (side, 0.0, 0.0), 5, 0.0034, 0.0036)
    bolt_row(band, (-0.220, 0.224, 0.178), (0.220, 0.224, 0.178), (0.0, 0.0, 1.0), 7, 0.0034, 0.0036)
    parts.append(("band", "ds_p_accent", band))
    return parts


def build_weapon_drop():
    """An abandoned rifle: receiver, furniture, optic, magazine and sling."""
    body = Builder()
    # Receiver: a proper slab with an upper and a lower, split by a real seam.
    rounded_box(body, (0.0, 0.010, 0.0), (0.072, 0.086, 0.520), 0.010, corner_segments=4)
    rounded_box(body, (0.0, 0.056, 0.010), (0.064, 0.036, 0.470), 0.008, corner_segments=3)
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.037, 0.010, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.170, 0.026, 4, 1, 0.004, 0.6, 0.0025, 3)
        bolt_row(body, (side * 0.038, 0.052, -0.230), (side * 0.038, 0.052, 0.230),
                 (side, 0.0, 0.0), 8, 0.0030, 0.0032)
    bolt_row(body, (-0.034, -0.034, 0.040), (0.034, -0.034, 0.040), (0.0, -1.0, 0.0), 3,
             0.0032, 0.0034)
    # Handguard and barrel with a gas block and a muzzle device.
    rounded_box(body, (0.0, 0.010, -0.400), (0.062, 0.078, 0.300), 0.010, corner_segments=4)
    for index in range(5):
        for side in (-1.0, 1.0):
            oriented_box(body, (side * 0.032, 0.010 + (index - 2) * 0.024, -0.400),
                         (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (side, 0.0, 0.0),
                         0.110, 0.010, 0.005, 0.0016, 2)
    rail(body, (0.0, 0.056, -0.540), (0.0, 0.056, -0.270), 0.030, 0.012, 12, 0.005)
    rail(body, (0.0, 0.078, -0.030), (0.0, 0.078, 0.250), 0.030, 0.012, 14, 0.005)
    tube(body, (0.0, 0.010, -0.550), (0.0, 0.010, -0.720), 0.018, 18, steps=3)
    rounded_box(body, (0.0, 0.038, -0.640), (0.034, 0.048, 0.060), 0.008, corner_segments=3)
    tube(body, (0.0, 0.010, -0.720), (0.0, 0.010, -0.800), 0.024, 18, radius_end=0.022, steps=2)
    ring_collar(body, (0.0, 0.010, -0.716), (0.0, 0.010, -0.706), 0.028, 0.023, 18)
    for index in range(3):
        angle = index * HALF_PI
        ux, uy = math.cos(angle), math.sin(angle)
        tube(body, (ux * 0.020, 0.010 + uy * 0.020, -0.760),
             (ux * 0.028, 0.010 + uy * 0.028, -0.760), 0.0058, 12, cap_start=False,
             cap_end=False)
    # Stock: cheek riser, butt pad, sling slot and the adjuster.
    rounded_box(body, (0.0, -0.020, 0.380), (0.066, 0.110, 0.320), 0.012, corner_segments=4)
    rounded_box(body, (0.0, 0.040, 0.420), (0.056, 0.030, 0.220), 0.008, corner_segments=3)
    rounded_box(body, (0.0, -0.020, 0.548), (0.070, 0.126, 0.040), 0.010, corner_segments=3)
    for side in (-1.0, 1.0):
        oriented_box(body, (side * 0.036, -0.010, 0.380), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     (side, 0.0, 0.0), 0.120, 0.036, 0.005, 0.0016, 2)
        torus_arc(body, (side * 0.034, -0.040, 0.300), (0.0, 0.0, 1.0), 0.026, 0.0042, 0.0,
                  math.pi, segments=10, arc_segments=6)
    # Pistol grip with its panelling and the trigger group.
    rounded_box(body, (0.0, -0.096, -0.060), (0.058, 0.170, 0.080), 0.010, corner_segments=4)
    for index in range(4):
        oriented_box(body, (0.0, -0.040 - index * 0.032, -0.098), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, -1.0, 0.0), 0.024, 0.050, 0.004, 0.0015, 2)
    torus_arc(body, (0.0, -0.046, -0.078), (1.0, 0.0, 0.0), 0.028, 0.0045, 0.0, math.pi,
              segments=10, arc_segments=6)
    # Magazine with its floorplate, and the spare taped alongside.
    rounded_box(body, (0.0, -0.086, 0.120), (0.056, 0.180, 0.090), 0.008, corner_segments=3)
    rounded_box(body, (0.0, -0.174, 0.126), (0.064, 0.030, 0.100), 0.006, corner_segments=3)
    for index in range(5):
        oriented_box(body, (0.0, -0.050 - index * 0.030, 0.164), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.026, 0.036, 0.004, 0.0015, 2)
    parts = [("body", "ds_p_hull", body)]
    # Optic: tube, turrets, ocular bell and a rail clamp.
    optic = Builder()
    tube(optic, (0.0, 0.106, -0.030), (0.0, 0.106, 0.060), 0.028, 20, cap_start=False,
         cap_end=False, steps=3)
    tube(optic, (0.0, 0.106, -0.070), (0.0, 0.106, -0.034), 0.032, 20, radius_end=0.029, steps=2)
    ring_collar(optic, (0.0, 0.106, 0.056), (0.0, 0.106, 0.068), 0.032, 0.026, 20)
    for index in range(4):
        angle = index * TAU / 4.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        tube(optic, (ux * 0.020, 0.106 + uy * 0.020, 0.006), (ux * 0.034, 0.106 + uy * 0.034, 0.006),
             0.011, 14, steps=2)
        ring_collar(optic, (ux * 0.032, 0.106 + uy * 0.032, 0.006),
                    (ux * 0.038, 0.106 + uy * 0.038, 0.006), 0.013, 0.010, 14)
    rounded_box(optic, (0.0, 0.084, 0.020), (0.030, 0.026, 0.090), 0.006, corner_segments=3)
    parts.append(("optic", "ds_p_lens", optic))
    return parts


def build_rocket():
    """Rocket: body, four fins, nose fuze and a real exhaust nozzle bell."""
    body = Builder()
    body_of_revolution(body, [(0.340, 0.030), (0.320, 0.036), (0.280, 0.038),
                              (0.200, 0.042), (0.130, 0.046), (0.040, 0.044),
                              (-0.020, 0.038), (-0.090, 0.034), (-0.130, 0.030),
                              (-0.240, 0.030), (-0.340, 0.030)], segments=24)
    for z, r in ((0.280, 0.038), (0.130, 0.046), (-0.020, 0.038), (-0.240, 0.030)):
        ring_collar(body, (0.0, 0.0, z - 0.004), (0.0, 0.0, z + 0.004), r * 1.06, r * 0.99, 24)
    bolt_ring(body, (0.0, 0.0, 0.276), (0.0, 0.0, 1.0), 0.034, 10, 0.0035, 0.0038)
    bolt_ring(body, (0.0, 0.0, -0.022), (0.0, 0.0, 1.0), 0.034, 10, 0.0035, 0.0038)
    # Longitudinal seam strips and the warhead's own section panels.
    for index in range(6):
        angle = index * TAU / 6.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.040, uy * 0.040, 0.050), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.200, 0.004, 0.004, 0.0012, 2)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.041, uy * 0.041, -0.180), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.070, 0.005, 0.005, 0.0012, 2)
        panel_grid(body, (ux * 0.040, uy * 0.040, 0.200), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                   (ux, uy, 0.0), 0.060, 0.010, 2, 1, 0.004, 0.6, 0.0025, 3)
    # Nose: ogive with a fuze tip and four fuze vanes.
    tube(body, (0.0, 0.0, 0.340), (0.0, 0.0, 0.372), 0.030, 20, radius_end=0.026, steps=2)
    ring_collar(body, (0.0, 0.0, 0.336), (0.0, 0.0, 0.344), 0.034, 0.029, 20)
    body_of_revolution(body, [(0.372, 0.024), (0.386, 0.020), (0.398, 0.012),
                              (0.404, 0.006)], segments=20)
    for index in range(4):
        angle = index * HALF_PI
        ux, uy = math.cos(angle), math.sin(angle)
        plate(body, [(ux * 0.008, uy * 0.008, 0.376), (ux * 0.030, uy * 0.030, 0.386),
                     (ux * 0.030, uy * 0.030, 0.398), (ux * 0.008, uy * 0.008, 0.396)],
              (uy * 0.005, -ux * 0.005, 0.0))
    # Cruciform fins: one plate each, with a root fillet and rivet line.
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        planform = [(ux * 0.024, uy * 0.024, 0.140), (ux * 0.090, uy * 0.090, 0.230),
                    (ux * 0.090, uy * 0.090, 0.320), (ux * 0.024, uy * 0.024, 0.320)]
        plate(body, planform, (uy * 0.008, -ux * 0.008, 0.0))
        oriented_box(body, (ux * 0.056, uy * 0.056, 0.230), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.080, 0.008, 0.004, 0.0015, 2)
        bolt_row(body, (ux * 0.028, uy * 0.028, 0.150), (ux * 0.028, uy * 0.028, 0.315),
                 (uy, -ux, 0.0), 5, 0.0028, 0.003)
        bolt_row(body, (ux * 0.060, uy * 0.060, 0.160), (ux * 0.086, uy * 0.086, 0.300),
                 (0.0, 0.0, 1.0), 4, 0.0028, 0.003)
        # Fin root fairing.
        tube(body, (ux * 0.024, uy * 0.024, 0.150), (ux * 0.024, uy * 0.024, 0.310), 0.008,
             12, cap_start=False, cap_end=False)
    # Nozzle: a real bell with a throat, an expansion cone and gimbal lugs.
    tube(body, (0.0, 0.0, -0.340), (0.0, 0.0, -0.372), 0.026, 20, radius_end=0.022, steps=2)
    ring_collar(body, (0.0, 0.0, -0.352), (0.0, 0.0, -0.342), 0.030, 0.025, 20)
    tube(body, (0.0, 0.0, -0.372), (0.0, 0.0, -0.400), 0.022, 20, radius_end=0.036, steps=3)
    ring_collar(body, (0.0, 0.0, -0.402), (0.0, 0.0, -0.394), 0.040, 0.034, 20)
    for index in range(6):
        angle = index * TAU / 6.0
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.030, uy * 0.030, -0.384), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.012, 0.006, 0.005, 0.0015, 2)
    for index in range(2):
        angle = index * math.pi + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.030, uy * 0.030, -0.356), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.012, 0.010, 0.006, 0.002, 2)
    bolt_ring(body, (0.0, 0.0, -0.348), (0.0, 0.0, 1.0), 0.028, 8, 0.0032, 0.0034)
    parts = [("body", "ds_p_hull", body)]
    plume = Builder()
    tube(plume, (0.0, 0.0, -0.400), (0.0, 0.0, -0.470), 0.036, 18, radius_end=0.010, steps=3)
    parts.append(("plume", "ds_p_lamp", plume))
    return parts




def build_rcxd():
    """Remote-controlled demolition vehicle: tub, roll cage, four wheels."""
    body = Builder()
    # Tub: hull, panelled flanks, front skid and the rear deck.
    rounded_box(body, (0.0, 0.070, 0.0), (0.460, 0.140, 0.800), 0.020, corner_segments=4)
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.231, 0.070, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.220, 0.040, 5, 1, 0.005, 0.60, 0.003, 3)
        bolt_row(body, (side * 0.232, 0.134, -0.340), (side * 0.232, 0.134, 0.340),
                 (side, 0.0, 0.0), 12, 0.0034, 0.0036)
        bolt_row(body, (side * 0.232, 0.010, -0.340), (side * 0.232, 0.010, 0.340),
                 (side, 0.0, 0.0), 12, 0.0034, 0.0036)
    panel_grid(body, (0.0, 0.141, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.200, 0.360, 5, 6, 0.005, 0.60, 0.003, 3)
    rounded_box(body, (0.0, 0.086, -0.340), (0.400, 0.112, 0.180), 0.018, corner_segments=4)
    rounded_box(body, (0.0, 0.056, -0.416), (0.480, 0.072, 0.060), 0.014, corner_segments=3)
    for side in (-1.0, 1.0):
        oriented_box(body, (side * 0.150, 0.100, -0.436), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                     (0.0, 1.0, 0.0), 0.060, 0.030, 0.012, 0.003, 2)
        cone(body, (side * 0.190, 0.086, -0.424), (side * 0.196, 0.086, -0.452), 0.020, 14)
        tube(body, (side * 0.196, 0.086, -0.436), (side * 0.200, 0.086, -0.456), 0.014, 14,
             radius_end=0.012, steps=2)
    # Front sensor pod: housing, glazed window, rim bolts and two guard wings.
    rounded_box(body, (0.0, 0.140, -0.280), (0.180, 0.080, 0.120), 0.012, corner_segments=3)
    tube(body, (0.0, 0.150, -0.344), (0.0, 0.150, -0.360), 0.024, 18, radius_end=0.020, steps=2)
    ring_collar(body, (0.0, 0.150, -0.342), (0.0, 0.150, -0.334), 0.028, 0.024, 18)
    bolt_ring(body, (0.0, 0.150, -0.338), (0.0, 0.0, -1.0), 0.033, 6, 0.0032, 0.0034)
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.070, 0.160, -0.230), (side * 0.094, 0.190, -0.170),
                     (side * 0.094, 0.190, -0.144), (side * 0.070, 0.160, -0.190)],
              (side * 0.014, 0.0, 0.0))
    # Roll cage: a bent arch over the tub, two rear legs, their feet and gussets.
    ribbon(body, [(-0.180, 0.140, -0.120), (-0.176, 0.200, -0.040), (-0.100, 0.238, 0.010),
                  (0.100, 0.238, 0.010), (0.176, 0.200, -0.040), (0.180, 0.140, -0.120)],
           (0.0, 0.0, 1.0), 0.020, 0.020)
    for side in (-1.0, 1.0):
        ribbon(body, [(side * 0.180, 0.140, -0.120), (side * 0.180, 0.120, 0.100),
                      (side * 0.180, 0.150, 0.300)], (side, 0.0, 0.0), 0.024, 0.020)
        for z in (-0.120, 0.300):
            oriented_box(body, (side * 0.180, 0.128 if z > 0 else 0.140, z), (0.0, 0.0, 1.0),
                         (side, 0.0, 0.0), (0.0, 1.0, 0.0), 0.040, 0.020, 0.010, 0.003, 2)
            bolt_ring(body, (side * 0.180, 0.140, z), (0.0, 0.0, 1.0), 0.026, 4, 0.0034, 0.0036)
        oriented_box(body, (side * 0.150, 0.190, 0.000), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                     (side, 0.0, 0.0), 0.030, 0.030, 0.006, 0.002, 2)
    # Suspension towers and the arms out to each wheel.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x, z = sx * 0.108, sz * 0.132
            oriented_box(body, (sx * 0.150, 0.070, z), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (sx, 0.0, 0.0), 0.060, 0.028, 0.008, 0.002, 2)
            tube(body, (sx * 0.100, 0.076, z), (sx * 0.170, 0.062, z), 0.010, 12, steps=2)
            ring_collar(body, (x - sx * 0.040, 0.052, z), (x - sx * 0.026, 0.052, z), 0.014,
                        0.010, 12)
            wheel(body, (x, 0.052, z), (1.0, 0.0, 0.0), 0.052, 0.064, treads=16, spokes=5)
            tube(body, (sx * 0.070, 0.052, z), (x - sx * 0.036, 0.052, z), 0.024, 16, steps=2)
            ring_collar(body, (sx * 0.070, 0.052, z), (sx * 0.082, 0.052, z), 0.028, 0.024, 16)
            bolt_ring(body, (sx * 0.072, 0.052, z), (sx, 0.0, 0.0), 0.024, 5, 0.0032, 0.0034)
    # Antenna mast with its base insulator, ball tip and the receiver box.
    rounded_box(body, (0.070, 0.120, 0.200), (0.070, 0.060, 0.070), 0.008, corner_segments=3)
    tube(body, (0.070, 0.150, 0.200), (0.070, 0.166, 0.200), 0.012, 14, radius_end=0.009, steps=2)
    tube(body, (0.070, 0.166, 0.200), (0.076, 0.320, 0.212), 0.0035, 10, steps=3)
    tube(body, (0.076, 0.320, 0.212), (0.078, 0.350, 0.216), 0.0062, 12)
    ring_collar(body, (0.070, 0.148, 0.200), (0.070, 0.156, 0.200), 0.015, 0.012, 14)
    # Rear deck: stencil blocks, tie-down loops and the tow eyes.
    for index in range(4):
        oriented_box(body, (-0.140 + index * 0.094, 0.160, 0.310), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.040, 0.030, 0.004, 0.0015, 2)
    for side in (-1.0, 1.0):
        torus_arc(body, (side * 0.200, 0.070, 0.300), (1.0, 0.0, 0.0), 0.020, 0.0045, 0.0,
                  math.pi, segments=10, arc_segments=6)
        torus_arc(body, (side * 0.200, 0.070, -0.380), (1.0, 0.0, 0.0), 0.018, 0.0045, 0.0,
                  math.pi, segments=10, arc_segments=6)
    parts = [("body", "ds_p_hull", body)]

    # Demolition charge on the deck, with its own panelling and bolts.
    charge = Builder()
    rounded_box(charge, (0.0, 0.116, 0.140), (0.300, 0.120, 0.220), 0.014, corner_segments=4)
    panel_grid(charge, (0.0, 0.180, 0.140), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.130, 0.090, 3, 2, 0.005, 0.62, 0.003, 3)
    ring_collar(charge, (0.0, 0.160, 0.050), (0.0, 0.176, 0.050), 0.024, 0.018, 18)
    bolt_ring(charge, (0.0, 0.182, 0.140), (0.0, 1.0, 0.0), 0.120, 8, 0.004, 0.0042)
    for side in (-1.0, 1.0):
        bolt_row(charge, (side * 0.152, 0.116, 0.050), (side * 0.152, 0.116, 0.230),
                 (side, 0.0, 0.0), 4, 0.0032, 0.0034)
    parts.append(("charge", "ds_p_accent", charge))

    led = Builder()
    tube(led, (0.0, 0.176, 0.140), (0.0, 0.190, 0.140), 0.012, 16, radius_end=0.010, steps=2)
    ring_collar(led, (0.0, 0.176, 0.140), (0.0, 0.182, 0.140), 0.016, 0.012, 16)
    parts.append(("led", "ds_p_red", led))
    return parts


def build_nuke():
    """Tactical warhead: cased body, banding, nose fuze and the fin can."""
    body = Builder()
    casing = [(0.556, 0.030), (0.520, 0.070), (0.460, 0.115), (0.300, 0.136),
              (0.120, 0.140), (0.0, 0.140), (-0.200, 0.136), (-0.380, 0.128),
              (-0.480, 0.115), (-0.540, 0.080), (-0.556, 0.070)]
    body_of_revolution(body, casing, segments=24)
    # Casing seams splitting the nose, body and tail, each with a bolt ring, so
    # the joints read as assembled hardware rather than one turned part.
    for z, r in ((0.460, 0.115), (0.300, 0.136), (0.120, 0.140), (-0.200, 0.136),
                 (-0.380, 0.128), (-0.480, 0.115)):
        ring_collar(body, (0.0, 0.0, z - 0.005), (0.0, 0.0, z + 0.005), r * 1.06, r * 0.99, 24)
    for z, r in ((0.460, 0.115), (0.120, 0.140), (-0.380, 0.128)):
        bolt_ring(body, (0.0, 0.0, z + 0.008), (0.0, 0.0, 1.0), r * 1.01, 12, 0.0038, 0.004)
    # Longitudinal stringers, then the casing's own skin panels and the fastener
    # field between them.
    for index in range(8):
        angle = index * TAU / 8.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        oriented_box(body, (ux * 0.141, uy * 0.141, 0.020), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.240, 0.005, 0.004, 0.0012, 2)
    for index in range(10):
        angle = index * TAU / 10.0 + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        for cell in range(5):
            z = mix(-0.330, 0.400, (cell + 0.5) / 5.0)
            radius = 0.140 if -0.380 < z < 0.460 else 0.100
            oriented_box(body, (ux * radius, uy * radius, z), (0.0, 0.0, 1.0),
                         (uy, -ux, 0.0), (ux, uy, 0.0), 0.070, 0.0045, 0.0038, 0.0014, 2)
        for cell in range(8):
            z = mix(-0.400, 0.480, (cell + 1.0) / 9.0)
            screw(body, (ux * 0.141, uy * 0.141, z), (ux, uy, 0.0), 0.0030, 0.0032)
    panel_grid(body, (0.140, 0.0, 0.020), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
               0.150, 0.070, 3, 2, 0.005, 0.62, 0.003, 3)
    bolt_row(body, (0.141, 0.070, -0.140), (0.141, 0.070, 0.180), (1.0, 0.0, 0.0), 8,
             0.0036, 0.0038)
    # Nose fuze: a stepped spike with a vane set and three contact rings.
    tube(body, (0.0, 0.0, 0.556), (0.0, 0.0, 0.600), 0.030, 20, radius_end=0.024, steps=2)
    ring_collar(body, (0.0, 0.0, 0.596), (0.0, 0.0, 0.606), 0.036, 0.029, 20)
    body_of_revolution(body, [(0.600, 0.022), (0.620, 0.018), (0.634, 0.010),
                              (0.640, 0.005)], segments=20)
    for index in range(4):
        angle = index * HALF_PI
        ux, uy = math.cos(angle), math.sin(angle)
        plate(body, [(ux * 0.008, uy * 0.008, 0.600), (ux * 0.040, uy * 0.040, 0.612),
                     (ux * 0.040, uy * 0.040, 0.626), (ux * 0.008, uy * 0.008, 0.624)],
              (uy * 0.005, -ux * 0.005, 0.0))
    for index in range(3):
        ring_collar(body, (0.0, 0.0, 0.556 + index * 0.014), (0.0, 0.0, 0.560 + index * 0.014),
                    0.033, 0.029, 20)
    # Tail: a gimbal ring, the closure cone and the fin can.
    tube(body, (0.0, 0.0, -0.548), (0.0, 0.0, -0.576), 0.072, 22, radius_end=0.066, steps=2)
    ring_collar(body, (0.0, 0.0, -0.580), (0.0, 0.0, -0.568), 0.074, 0.066, 22)
    tube(body, (0.0, 0.0, -0.576), (0.0, 0.0, -0.596), 0.062, 22, radius_end=0.052, steps=2)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        planform = [(ux * 0.130, uy * 0.130, 0.300), (ux * 0.230, uy * 0.230, 0.120),
                    (ux * 0.230, uy * 0.230, -0.100), (ux * 0.130, uy * 0.130, -0.140)]
        plate(body, planform, (uy * 0.010, -ux * 0.010, 0.0))
        oriented_box(body, (ux * 0.180, uy * 0.180, 0.060), (0.0, 0.0, 1.0), (uy, -ux, 0.0),
                     (ux, uy, 0.0), 0.200, 0.010, 0.005, 0.0016, 2)
        bolt_row(body, (ux * 0.140, uy * 0.140, 0.280), (ux * 0.140, uy * 0.140, -0.130),
                 (uy, -ux, 0.0), 8, 0.0032, 0.0034)
        bolt_row(body, (ux * 0.150, uy * 0.150, 0.290), (ux * 0.222, uy * 0.222, 0.110),
                 (0.0, 0.0, 1.0), 5, 0.0032, 0.0034)
        # Fin skin panels on both faces with a fastener row round the edge.
        for surface in (-1.0, 1.0):
            for cell in range(3):
                span = mix(0.145, 0.222, (cell + 0.5) / 3.0)
                z = mix(0.270, -0.110, (cell + 0.5) / 3.0)
                oriented_box(body, (ux * span, uy * span + surface * 0.007, z),
                             (0.0, 0.0, 1.0), (uy * surface, -ux * surface, 0.0),
                             (ux, uy, 0.0), 0.048, 0.0045, 0.0032, 0.0012, 2)
            for cell in range(4):
                z = mix(0.290, -0.130, (cell + 0.5) / 4.0)
                screw(body, (ux * 0.208, uy * 0.208 + surface * 0.007, z),
                      (uy * surface, -ux * surface, 0.0), 0.0028, 0.0030)
    # Carrying lugs either side, on their reinforcement pads.
    for side in (-1.0, 1.0):
        oriented_box(body, (side * 0.140, 0.0, 0.230), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, 1.0, 0.0), 0.028, 0.018, 0.014, 0.004, 3)
        torus_arc(body, (side * 0.156, 0.0, 0.230), (0.0, 0.0, 1.0), 0.016, 0.0045, 0.0,
                  math.pi, segments=10, arc_segments=6)
    parts = [("body", "ds_p_steel", body)]
    # The two identification bands, each with its own bolts and strap clamps.
    band = Builder()
    for z in (-0.190, 0.120):
        ring_collar(band, (0.0, 0.0, z), (0.0, 0.0, z + 0.040), 0.143, 0.136, 24)
        bolt_ring(band, (0.0, 0.0, z + 0.020), (0.0, 0.0, 1.0), 0.140, 10, 0.0036, 0.0038)
        for index in range(6):
            angle = index * TAU / 6.0
            ux, uy = math.cos(angle), math.sin(angle)
            oriented_box(band, (ux * 0.143, uy * 0.143, z + 0.020), (0.0, 0.0, 1.0),
                         (uy, -ux, 0.0), (ux, uy, 0.0), 0.040, 0.006, 0.006, 0.0016, 2)
    parts.append(("band", "ds_p_accent", band))
    return parts


def build_care_crate(falling):
    """Supply crate. `falling` adds the marker beam the dropped crate carries.

    The crate keeps its ported envelope exactly — a 1.2 x 0.8 x 1.2 m box with
    the lid at 0.812 and the marker lamp at 0.880 — and gains the ribs, corner
    brackets, hinges, latches and stencil blocks a braced wooden crate has.
    """
    crate = Builder()
    rounded_box(crate, (0.0, 0.400, 0.0), (1.200, 0.800, 1.200), 0.030, corner_segments=4)
    # Plank skin: the faces are boarded planks with narrow gaps between them, one
    # grid per face, which is what makes a crate read as timber rather than a
    # painted cube. Each plank has its own nail heads.
    for face in (-1.0, 1.0):
        panel_grid(crate, (0.0, 0.400, face * 0.598), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                   (0.0, 0.0, face), 0.570, 0.360, 4, 6, 0.007, 0.90, 0.0028, 3)
        panel_grid(crate, (face * 0.598, 0.400, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (face, 0.0, 0.0), 0.570, 0.360, 4, 6, 0.007, 0.90, 0.0028, 3)
        for side in (-1.0, 1.0):
            for row in range(6):
                y = 0.130 + row * 0.108
                bolt_row(crate, (side * 0.560, y, face * 0.604),
                         (side * 0.120, y, face * 0.604), (0.0, 0.0, face), 3, 0.0042, 0.005)
                bolt_row(crate, (face * 0.604, y, side * 0.560),
                         (face * 0.604, y, side * 0.120), (face, 0.0, 0.0), 3, 0.0042, 0.005)
    # Banded straps round the crate with buckles where they cross.
    for offset in (-0.320, 0.320):
        for face in (-1.0, 1.0):
            oriented_box(crate, (offset, 0.400, face * 0.602), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                         (0.0, 0.0, face), 0.052, 0.380, 0.010, 0.003, 3)
            oriented_box(crate, (face * 0.602, 0.400, offset), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (face, 0.0, 0.0), 0.052, 0.380, 0.010, 0.003, 3)
        for sx in (-1.0, 1.0):
            for sz in (-1.0, 1.0):
                oriented_box(crate, (sx * 0.604, 0.400, sz * 0.602), (1.0, 0.0, 0.0),
                             (0.0, 1.0, 0.0), (0.0, 0.0, sz), 0.040, 0.026, 0.010, 0.003, 3)
        for face in (-1.0, 1.0):
            bolt_row(crate, (offset, 0.060, face * 0.606), (offset, 0.740, face * 0.606),
                     (0.0, 0.0, face), 5, 0.0045, 0.005)
            bolt_row(crate, (face * 0.606, 0.060, offset), (face * 0.606, 0.740, offset),
                     (face, 0.0, 0.0), 5, 0.0045, 0.005)
    # Ribbed sides: three horizontal and three vertical ribs per face, so every
    # face reads as a braced panel with real shadow lines between the ribs.
    for face in (-1.0, 1.0):
        for row in range(3):
            y = 0.180 + row * 0.240
            oriented_box(crate, (0.0, y, face * 0.607), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                         (0.0, 0.0, face), 0.560, 0.0275, 0.012, 0.004, 3)
            oriented_box(crate, (face * 0.607, y, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (face, 0.0, 0.0), 0.560, 0.0275, 0.012, 0.004, 3)
        for column in range(3):
            u = (column - 1) * 0.180
            oriented_box(crate, (u, 0.400, face * 0.604), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                         (0.0, 0.0, face), 0.045, 0.300, 0.010, 0.003, 3)
            oriented_box(crate, (face * 0.604, 0.400, u), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                         (face, 0.0, 0.0), 0.045, 0.300, 0.010, 0.003, 3)
        # Stencil-plate blocks low on each face.
        for index in range(5):
            oriented_box(crate, (-0.280 + index * 0.140, 0.300, face * 0.608), (1.0, 0.0, 0.0),
                         (0.0, 1.0, 0.0), (0.0, 0.0, face), 0.026, 0.030, 0.004, 0.0015, 3)
    # Corner brackets: the posts, their bolt rows and the gussets top and bottom.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            rounded_box(crate, (sx * 0.580, 0.400, sz * 0.580), (0.090, 0.820, 0.090), 0.014,
                        corner_segments=3)
            for y in (0.060, 0.740):
                oriented_box(crate, (sx * 0.580, y, sz * 0.580), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                             (0.0, 0.0, sz), 0.050, 0.036, 0.010, 0.003, 3)
                bolt_row(crate, (sx * 0.560, y - 0.030, sz * 0.626),
                         (sx * 0.600, y + 0.030, sz * 0.626), (0.0, 0.0, sz), 2, 0.0045, 0.005)
                bolt_row(crate, (sx * 0.626, y - 0.030, sz * 0.560),
                         (sx * 0.626, y + 0.030, sz * 0.600), (sx, 0.0, 0.0), 2, 0.0045, 0.005)
            bolt_row(crate, (sx * 0.580, 0.100, sz * 0.626), (sx * 0.580, 0.700, sz * 0.626),
                     (0.0, 0.0, sz), 5, 0.0045, 0.005)
    # Lid: a proud cap with panelling, four hinges down one edge and the latches
    # on the opposite edge.
    rounded_box(crate, (0.0, 0.812, 0.0), (1.180, 0.060, 1.180), 0.024, corner_segments=4)
    panel_grid(crate, (0.0, 0.842, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.556, 0.556, 6, 6, 0.006, 0.68, 0.004, 3)
    for index in range(4):
        oriented_box(crate, (-0.450 + index * 0.300, 0.842, 0.0), (1.0, 0.0, 0.0),
                     (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.090, 0.010, 0.005, 0.0018, 3)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            torus_arc(crate, (sx * 0.350, 0.770, sz * 0.590), (1.0, 0.0, 0.0), 0.028, 0.0055,
                      0.0, math.pi, segments=12, arc_segments=7)
            oriented_box(crate, (sx * 0.350, 0.780, sz * 0.582), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), 0.048, 0.036, 0.010, 0.003, 3)
    for sx in (-1.0, 1.0):
        oriented_box(crate, (sx * 0.380, 0.812, 0.596), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     (0.0, 0.0, 1.0), 0.052, 0.030, 0.010, 0.003, 3)
        bolt_row(crate, (sx * 0.380, 0.786, 0.606), (sx * 0.380, 0.838, 0.606),
                 (0.0, 0.0, 1.0), 2, 0.0045, 0.005)
    box(crate, (0.0, 0.720, -0.640), (0.240, 0.180, 0.050))
    # Plank skin on the lid's underside too, so the open crate shows boarding.
    panel_grid(crate, (0.0, 0.788, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0),
               0.556, 0.556, 4, 5, 0.007, 0.90, 0.0028, 3)
    # Lifting handles on the end faces, on their own bolted plates.
    for sx in (-1.0, 1.0):
        ribbon(crate, [(sx * 0.606, 0.500, -0.150), (sx * 0.628, 0.500, -0.075),
                       (sx * 0.628, 0.500, 0.075), (sx * 0.606, 0.500, 0.150)],
               (sx, 0.0, 0.0), 0.015, 0.009)
        for sz in (-1.0, 1.0):
            oriented_box(crate, (sx * 0.610, 0.500, sz * 0.150), (0.0, 0.0, 1.0), (sx, 0.0, 0.0),
                         (0.0, 1.0, 0.0), 0.030, 0.018, 0.008, 0.003, 3)
    parts = [("crate", "ds_p_crate", crate)]
    lamp = Builder()
    tube(lamp, (0.0, 0.880, 0.0), (0.0, 0.906, 0.0), 0.075, 20, steps=2)
    ring_collar(lamp, (0.0, 0.880, 0.0), (0.0, 0.888, 0.0), 0.084, 0.075, 20)
    bolt_ring(lamp, (0.0, 0.882, 0.0), (0.0, 1.0, 0.0), 0.078, 8, 0.0055, 0.006)
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



# --------------------------------------------------------------------------
# Assembly. Rotors are separate nodes so the gameplay can spin them.
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# The supply drop's own transport helicopter.
#
# `streak_system._tick_care_package` spins `mainRotor` about Y and `tailRotor`
# about X on the `streak_care_package` root every tick, so this asset is not the
# crate: it is the aircraft that flies in and drops one. The proportions and the
# two pivot positions match the ported export, which the gameplay was written
# against.
# --------------------------------------------------------------------------

CARE_MAIN_ROTOR_Y = 0.580
CARE_TAIL_ROTOR_Y = 0.350
CARE_TAIL_ROTOR_Z = 3.360


def build_care_heli():
    """The static half: fuselage, tail boom, fin, skids and the drop cradle."""
    body = Builder()
    # Cabin, tapering into the boom that runs back to the tail rotor.
    cabin = [(0.0, 0.520, 0.420), (0.16, 0.640, 0.500), (0.34, 0.700, 0.540),
             (0.50, 0.680, 0.520), (0.68, 0.500, 0.400), (0.82, 0.300, 0.260),
             (1.0, 0.180, 0.180)]
    sweep(body, profile_rounded_rect(1.0, 1.0, 0.5, 5),
          [((0.0, 0.0, -1.50 + t * 3.00), vmul((1.0, 0.0, 0.0), rx),
            vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, 1.0))
           for t, rx, ry in cabin], True, True)
    # Section seams with bolt rings, and the cabin's own skin panels.
    for t, scale in ((0.16, 1.04), (0.34, 1.04), (0.50, 1.04), (0.68, 1.04), (0.82, 1.04)):
        z = -1.50 + t * 3.00
        rx = mix(0.520, 0.180, t) if t > 0.68 else mix(0.520, 0.700, min(t / 0.34, 1.0))
        ring_collar(body, (0.0, 0.0, z - 0.006), (0.0, 0.0, z + 0.006), rx * scale + 0.006,
                    rx * scale - 0.006, 26)
    for side in (-1.0, 1.0):
        panel_grid(body, (side * 0.560, 0.0, -0.320), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
                   (side, 0.0, 0.0), 0.400, 0.150, 4, 2, 0.006, 0.64, 0.003, 3)
        bolt_row(body, (side * 0.580, 0.340, -0.900), (side * 0.300, 0.200, 1.300),
                 (side, 0.0, 0.0), 16, 0.0040, 0.0042)
        for z in (-0.700, -0.300, 0.100):
            tube(body, (side * 0.520, -0.470, z), (side * 0.560, -0.560, z), 0.028, 12, steps=2)
            ring_collar(body, (side * 0.548, -0.548, z), (side * 0.566, -0.566, z), 0.034,
                        0.028, 12)
    # Cockpit glazing and the nose.
    cockpit = Builder()
    sweep(cockpit, profile_circle(1.0, 22),
          [((0.0, 0.140 + t * 0.120, -1.62 + t * 0.62), vmul((1.0, 0.0, 0.0), rx),
            vmul((0.0, 1.0, 0.0), ry), (0.0, 0.0, 1.0))
           for t, rx, ry in ((0.0, 0.150, 0.130), (0.30, 0.380, 0.300),
                             (0.65, 0.520, 0.400), (1.0, 0.560, 0.420))], True, True)
    for t, rx, ry in ((0.30, 0.380, 0.300), (0.65, 0.520, 0.400)):
        ring_collar(cockpit, (0.0, 0.140 + t * 0.120, -1.62 + t * 0.62 - 0.006),
                    (0.0, 0.140 + t * 0.120, -1.62 + t * 0.62 + 0.006), rx * 1.06, rx * 0.99, 22)
    rounded_box(body, (0.0, -0.300, -1.500), (0.400, 0.240, 0.300), 0.030, corner_segments=4)
    tube(body, (0.0, -0.180, -1.640), (0.0, -0.180, -1.700), 0.090, 20, radius_end=0.070, steps=2)
    # Tail boom: a lofted spar with ring frames down it.
    tube(body, (0.0, 0.020, 1.300), (0.0, 0.060, 3.450), 0.180, 20, radius_end=0.120, steps=5)
    for index in range(5):
        t = (index + 1) / 6.0
        ring_collar(body, (0.0, mix(0.020, 0.060, t), mix(1.300, 3.450, t) - 0.006),
                    (0.0, mix(0.020, 0.060, t), mix(1.300, 3.450, t) + 0.006),
                    mix(0.180, 0.120, t) + 0.006, mix(0.180, 0.120, t) - 0.006, 20)
    for index in range(6):
        z = 1.500 + index * 0.320
        oriented_box(body, (0.0, 0.060 + 0.130, z), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
                     0.070, 0.008, 0.005, 0.0015, 2)
    # Vertical fin: a plate with a spar, bolt lines and the tail skid.
    plate(body, [(0.0, 0.120, 3.100), (0.0, 0.950, 3.500), (0.0, 0.950, 3.300),
                 (0.0, 0.120, 2.950)], (0.026, 0.0, 0.0))
    oriented_box(body, (0.0, 0.420, 3.200), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                 0.220, 0.014, 0.010, 0.003, 3)
    for side in (-1.0, 1.0):
        bolt_row(body, (side * 0.014, 0.180, 3.060), (side * 0.014, 0.920, 3.460),
                 (side, 0.0, 0.0), 7, 0.0042, 0.0044)
    swept_tube(body, [(0.0, -0.100, 3.300), (0.0, -0.260, 3.380), (0.0, -0.380, 3.400)], 0.022, 12)
    # Horizontal stabiliser with elevators.
    for side in (-1.0, 1.0):
        plate(body, [(side * 0.020, 0.300, 3.240), (side * 0.700, 0.300, 3.340),
                     (side * 0.700, 0.300, 3.200), (side * 0.020, 0.300, 3.120)],
              (0.0, 0.014, 0.0))
        bolt_row(body, (side * 0.060, 0.300, 3.230), (side * 0.660, 0.300, 3.325),
                 (0.0, 1.0, 0.0), 6, 0.0038, 0.0040)
    # Rotor mast pylon on the deck, with its own panelling and bolts.
    tube(body, (0.0, 0.560, 0.100), (0.0, 0.780, 0.100), 0.230, 24, radius_end=0.180, steps=3)
    ring_collar(body, (0.0, 0.560, 0.100), (0.0, 0.586, 0.100), 0.252, 0.230, 24)
    bolt_ring(body, (0.0, 0.564, 0.100), (0.0, 1.0, 0.0), 0.240, 12, 0.0055, 0.006)
    panel_grid(body, (0.0, 0.680, 0.100), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0),
               0.170, 0.220, 4, 4, 0.006, 0.64, 0.003, 3)
    # Engine cowlings either side of the pylon, with cooling louvres.
    for side in (-1.0, 1.0):
        rounded_box(body, (side * 0.400, 0.520, 0.320), (0.340, 0.300, 1.000), 0.030,
                    corner_segments=4)
        for index in range(6):
            oriented_box(body, (side * 0.575, 0.520 + (index - 2.5) * 0.036, 0.320),
                         (0.0, 0.0, 1.0), (side, 0.0, 0.0), (0.0, 1.0, 0.0),
                         0.030, 0.070, 0.008, 0.002, 2)
        bolt_row(body, (side * 0.575, 0.680, -0.150), (side * 0.575, 0.680, 0.780),
                 (side, 0.0, 0.0), 8, 0.0042, 0.0044)
        tube(body, (side * 0.420, 0.560, 0.840), (side * 0.520, 0.600, 1.020), 0.110, 18,
             radius_end=0.125, steps=2)
    # Skids: struts, runners, cross tubes and the step.
    for side in (-1.0, 1.0):
        swept_tube(body, [(side * 0.460, -0.640, -1.300), (side * 0.560, -0.760, -0.400),
                          (side * 0.560, -0.780, 1.300), (side * 0.560, -0.780, 1.900)],
                   0.038, 12)
        for z in (-1.200, -0.400, 0.900, 1.700):
            oriented_box(body, (side * 0.552, -0.780, z), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0),
                         (0.0, 1.0, 0.0), 0.070, 0.090, 0.010, 0.003, 3)
        for z in (-0.800, 0.700):
            tube(body, (side * 0.360, -0.300, z), (side * 0.540, -0.740, z), 0.022, 12, steps=3)
            ring_collar(body, (side * 0.446, -0.514, z), (side * 0.462, -0.536, z), 0.028,
                        0.022, 12)
            bolt_ring(body, (side * 0.372, -0.320, z), (0.0, 0.0, 1.0), 0.022, 4, 0.004, 0.004)
    # The drop cradle under the belly: rails, rollers, hook and sling lugs.
    rounded_box(body, (0.0, -0.660, -0.300), (0.800, 0.180, 1.400), 0.030, corner_segments=4)
    panel_grid(body, (0.0, -0.760, -0.300), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0),
               0.360, 0.660, 4, 5, 0.006, 0.66, 0.003, 3)
    for side in (-1.0, 1.0):
        oriented_box(body, (side * 0.290, -0.760, -0.300), (0.0, 0.0, 1.0), (side, 0.0, 0.0),
                     (0.0, -1.0, 0.0), 0.680, 0.070, 0.014, 0.004, 3)
        for z in (-0.900, -0.560, -0.220, 0.120):
            tube(body, (side * 0.380, -0.830, z), (side * 0.480, -0.830, z), 0.048, 14, steps=2)
            ring_collar(body, (side * 0.396, -0.830, z), (side * 0.416, -0.830, z), 0.056,
                        0.048, 14)
        bolt_row(body, (side * 0.400, -0.600, -0.950), (side * 0.400, -0.600, 0.330),
                 (side, 0.0, 0.0), 7, 0.0042, 0.0044)
        torus_arc(body, (side * 0.430, -0.660, 0.560), (0.0, 0.0, 1.0), 0.090, 0.018, 0.0,
                  math.pi, segments=14, arc_segments=8)
    tube(body, (0.0, -0.830, -0.300), (0.0, -0.900, -0.300), 0.045, 14, radius_end=0.036, steps=2)
    ring_collar(body, (0.0, -0.894, -0.300), (0.0, -0.906, -0.300), 0.050, 0.038, 14)
    return [("helicopter", "ds_p_hull", body)]


def build_care_heli_rotors():
    """`mainRotor` and `tailRotor`: the two pivots `_tick_care_package` spins.

    Each node carries its blades about its own local origin, so the spin stays a
    pure local rotation the way the ported pivots behaved.
    """
    my = CARE_MAIN_ROTOR_Y
    main = Builder()
    tube(main, (0.0, my, 0.0), (0.0, my + 0.220, 0.0), 0.110, 22, steps=4)
    ring_collar(main, (0.0, my + 0.020, 0.0), (0.0, my + 0.052, 0.0), 0.132, 0.110, 22)
    ring_collar(main, (0.0, my + 0.150, 0.0), (0.0, my + 0.184, 0.0), 0.144, 0.120, 22)
    bolt_ring(main, (0.0, my + 0.190, 0.0), (0.0, 1.0, 0.0), 0.116, 8, 0.006, 0.007)
    for index in range(5):
        angle = index * TAU / 5.0
        ux, uy = math.cos(angle), math.sin(angle)
        # Blade grip with its own clevis bolts.
        oriented_box(main, (ux * 0.150, my + 0.212, uy * 0.150), (-uy, 0.0, ux), (0.0, 1.0, 0.0),
                     (ux, 0.0, uy), 0.090, 0.020, 0.034, 0.004, 3)
        bolt_row(main, (ux * 0.108, my + 0.212, uy * 0.108), (ux * 0.192, my + 0.212, uy * 0.192),
                 (0.0, 1.0, 0.0), 3, 0.0045, 0.005)
        # Blade: chord-tapered with real washout twist out to the tip.
        twisted_blade(main, (ux * 0.200, my + 0.212, uy * 0.200),
                      (ux * 3.400, my + 0.190, uy * 3.400),
                      0.170, 0.024, 0.20, 0.62, 0.92, 9, corner_segments=4)
        # Spanwise spar caps and a fastener set at each blade station.
        for t in (0.28, 0.55, 0.82):
            span = 3.400 * t
            oriented_box(main, (ux * span, my + 0.206, uy * span), (-uy, 0.0, ux), (0.0, 1.0, 0.0),
                         (ux, 0.0, uy), 0.090, 0.022, 0.009, 0.002, 2)
            bolt_row(main, (ux * span, my + 0.220, uy * span - 0.090),
                     (ux * span, my + 0.220, uy * span + 0.090), (0.0, 1.0, 0.0), 3, 0.0038, 0.004)
        ring_collar(main, (ux * 3.380, my + 0.190, uy * 3.380),
                    (ux * 3.440, my + 0.188, uy * 3.440), 0.090, 0.060, 16)
    # Swashplate and pitch links below the hub.
    ring_collar(main, (0.0, my + 0.060, 0.0), (0.0, my + 0.100, 0.0), 0.190, 0.150, 22)
    for index in range(4):
        angle = index * HALF_PI + QUARTER
        ux, uy = math.cos(angle), math.sin(angle)
        tube(main, (ux * 0.110, my + 0.190, uy * 0.110), (ux * 0.170, my + 0.100, uy * 0.170),
             0.016, 10, steps=2)

    ty, tz = CARE_TAIL_ROTOR_Y, CARE_TAIL_ROTOR_Z
    tail = Builder()
    # Tail rotor gearbox hub and two twisted blades about the X pivot.
    tube(tail, (0.0, ty, tz), (0.120, ty, tz), 0.082, 20, steps=4)
    ring_collar(tail, (0.016, ty, tz), (0.048, ty, tz), 0.100, 0.082, 20)
    bolt_ring(tail, (0.112, ty, tz), (1.0, 0.0, 0.0), 0.070, 6, 0.005, 0.006)
    for index in range(2):
        angle = index * math.pi
        uz, uy = math.cos(angle), math.sin(angle)
        oriented_box(tail, (0.090, ty + uy * 0.110, tz + uz * 0.110), (0.0, uy, uz),
                     (1.0, 0.0, 0.0), (0.0, -uz, uy), 0.050, 0.024, 0.020, 0.003, 3)
        twisted_blade(tail, (0.090, ty + uy * 0.150, tz + uz * 0.150),
                      (0.090, ty + uy * 0.760, tz + uz * 0.760),
                      0.078, 0.014, 0.28, 0.64, 0.90, 7, corner_segments=4)
        for span in (0.330, 0.600):
            oriented_box(tail, (0.090, ty + uy * span, tz + uz * span), (0.0, uy, uz),
                         (1.0, 0.0, 0.0), (0.0, -uz, uy), 0.078, 0.014, 0.008, 0.002, 2)
    return [("mainRotor", "ds_p_dark", main), ("tailRotor", "ds_p_dark", tail)]


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
    # beam; `care_crate` is the plain crate body.
    if asset_id == "care_pickup":
        return build_care_crate(True)
    if asset_id == "care_crate":
        return build_care_crate(False)
    # The ported `streak_care_package` is the transport helicopter that flies the
    # crate in, not the crate: `_tick_care_package` spins its two rotor pivots
    # every tick and spawns `care_crate` when it reaches the drop point.
    if asset_id == "streak_care_package":
        return build_care_heli() + build_care_heli_rotors()
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
