"""Procedural high-detail geometry for DeadShot's player-facing assets.

The ported models were exact rebuilds of the original Three.js primitives: an
assault rifle was 192 triangles of axis-aligned boxes. Realism is not a shading
problem alone, so this module builds dense, chamfered, hollow geometry that the
existing surface system can then shade properly.

Space is the source model space `assets/models/source/models.json` uses: metres,
Y up, weapon barrels forward along -Z, characters facing +Z. `blender_build_models.py`
applies the same up-axis conversion it already applies to the ported models.

Everything is deterministic: no randomness, no time, no external assets.
"""

from __future__ import annotations

import math

TAU = math.tau


# --------------------------------------------------------------------------
# Vector helpers. Plain tuples keep the builders allocation-light and let the
# finished buffers convert straight to `json` lists.
# --------------------------------------------------------------------------

def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vlen(a):
    return math.sqrt(vdot(a, a))


def vnorm(a):
    length = vlen(a)
    if length < 1e-12:
        return (0.0, 0.0, 1.0)
    return (a[0] / length, a[1] / length, a[2] / length)


def basis_from_w(w):
    """Right-handed (u, v, w) with w fixed, biased away from the dominant axis."""
    w = vnorm(w)
    reference = (0.0, 0.0, 1.0) if abs(w[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = vnorm(vcross(reference, w))
    v = vcross(w, u)
    return u, v, w


def lerp3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


# --------------------------------------------------------------------------
# Mesh builder. Normals are per-loop (`normals_split_custom_set`), so a single
# mesh mixes hard chamfers with smooth cylinders exactly as a real asset does.
# --------------------------------------------------------------------------

class Builder:
    __slots__ = ("positions", "normals", "indices")

    def __init__(self):
        self.positions: list = []
        self.normals: list = []
        self.indices: list = []

    def _vertex(self, point, normal):
        self.positions.append(point)
        self.normals.append(normal)
        return len(self.positions) - 1

    def triangle(self, p0, p1, p2, n0=None, n1=None, n2=None):
        if n0 is None:
            face = vnorm(vcross(vsub(p1, p0), vsub(p2, p1)))
            n0 = n1 = n2 = face
        a = self._vertex(p0, n0)
        b = self._vertex(p1, n1)
        c = self._vertex(p2, n2)
        self.indices.extend((a, b, c))

    def quad(self, p0, p1, p2, p3, n0=None, n1=None, n2=None, n3=None):
        """p0..p3 run counter-clockwise seen from the outward face."""
        if n0 is None:
            face = vnorm(vcross(vsub(p1, p0), vsub(p2, p1)))
            n0 = n1 = n2 = n3 = face
        a = self._vertex(p0, n0)
        b = self._vertex(p1, n1)
        c = self._vertex(p2, n2)
        d = self._vertex(p3, n3)
        self.indices.extend((a, b, c, a, c, d))

    def count_triangles(self):
        return len(self.indices) // 3

    def record(self):
        flat_positions = []
        for point in self.positions:
            flat_positions.extend(point)
        flat_normals = []
        for normal in self.normals:
            flat_normals.extend(normal)
        return {
            "positions": flat_positions,
            "normals": flat_normals,
            "uvs": [],
            "indices": list(self.indices),
        }

    def bbox(self):
        if not self.positions:
            return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)
        lo = [min(p[i] for p in self.positions) for i in range(3)]
        hi = [max(p[i] for p in self.positions) for i in range(3)]
        return tuple(lo), tuple(hi)


class Mesh:
    """Accumulates triangles into one geometry record without vertex normals.

    The map geometry tables carry no normals: `MapWorld._make_mesh` builds an
    `ArrayMesh` from positions and indices alone and the surface shader derives
    its shading normal in world space.
    """

    __slots__ = ("positions", "indices")

    def __init__(self):
        self.positions = []
        self.indices = []

    def triangle(self, a, b, c):
        base = len(self.positions) // 3
        self.positions.extend((a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]))
        self.indices.extend((base, base + 2, base + 1))

    def quad(self, a, b, c, d):
        self.triangle(a, b, c)
        self.triangle(a, c, d)

    def empty(self):
        return not self.indices


# --------------------------------------------------------------------------
# 2D profiles. A real firearm is a stack of extruded rounded rectangles and
# swept tubes; these generators are the whole vocabulary the builders need.
# --------------------------------------------------------------------------

def profile_rounded_rect(half_u, half_v, radius, corner_segments=4):
    """Chamfered rectangle, counter-clockwise in the (u, v) plane."""
    radius = min(radius, half_u * 0.999, half_v * 0.999)
    if radius <= 1e-6:
        return [(-half_u, -half_v), (half_u, -half_v), (half_u, half_v), (-half_u, half_v)]
    points = []
    cu, cv = half_u - radius, half_v - radius
    corners = (
        (cu, -cv, -math.pi / 2.0, 0.0),
        (cu, cv, 0.0, math.pi / 2.0),
        (-cu, cv, math.pi / 2.0, math.pi),
        (-cu, -cv, math.pi, math.pi * 1.5),
    )
    for origin_u, origin_v, start, end in corners:
        for step in range(corner_segments):
            angle = start + (end - start) * (step / corner_segments)
            points.append((origin_u + radius * math.cos(angle), origin_v + radius * math.sin(angle)))
    return points


def profile_circle(radius, segments=16):
    return [
        (radius * math.cos(TAU * i / segments), radius * math.sin(TAU * i / segments))
        for i in range(segments)
    ]


def profile_taper(half_u, half_v, radius, corner_segments, top_scale):
    """Rounded rectangle whose upper half is narrowed, for grips and stocks."""
    return [(u, v * (top_scale if v > 0.0 else 1.0)) for u, v in
            profile_rounded_rect(half_u, half_v, radius, corner_segments)]


# --------------------------------------------------------------------------
# Sweeping and extrusion.
# --------------------------------------------------------------------------

def _frames_straight(origin, u, v, w, start, end):
    return [(vadd(origin, vmul(w, start)), u, v, w), (vadd(origin, vmul(w, end)), u, v, w)]


def extrude(builder, profile, start, end, origin=(0.0, 0.0, 0.0), u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0),
            w=(0.0, 1.0, 0.0), cap_start=True, cap_end=True):
    """Extrudes a closed profile along `w` between `start` and `end`."""
    sweep(builder, profile, _frames_straight(origin, u, v, w, start, end), cap_start, cap_end)


def sweep(builder, profile, frames, cap_start=True, cap_end=True, smooth_normals=None):
    """Sweeps a closed profile along pre-built frames `(origin, u, v, w)`.

    `smooth_normals` optionally supplies one outward normal per profile point
    (in the local frame) so tubes read as round instead of faceted.

    Winding is normalised against the frame's handedness: `u x v` must point
    along `w` for the generated quads to face outward. Frames built from a `-Z`
    or `+Y` sweep axis are left-handed in the obvious spelling, and without this
    they produce inward-facing geometry that back-face culling then hides
    entirely.
    """
    if len(frames) < 2:
        return
    origin, u, v, w = frames[0]
    flipped = vdot(vcross(u, v), w) < 0.0
    count = len(profile)
    rings = []
    for frame_origin, frame_u, frame_v, _frame_w in frames:
        rings.append([vadd(frame_origin, vadd(vmul(frame_u, pu), vmul(frame_v, pv)))
                      for pu, pv in profile])
    for index in range(len(frames) - 1):
        lower, upper = rings[index], rings[index + 1]
        lower_axes = frames[index]
        upper_axes = frames[index + 1]
        for i in range(count):
            j = (i + 1) % count
            if flipped:
                i, j = j, i
            if smooth_normals is None:
                builder.quad(lower[i], lower[j], upper[j], upper[i])
            else:
                builder.quad(lower[i], lower[j], upper[j], upper[i],
                             _frame_normal(smooth_normals[i], lower_axes),
                             _frame_normal(smooth_normals[j], lower_axes),
                             _frame_normal(smooth_normals[j], upper_axes),
                             _frame_normal(smooth_normals[i], upper_axes))
            if flipped:
                i, j = j, i
    if cap_start:
        first = rings[0]
        for i in range(1, count - 1):
            if flipped:
                builder.triangle(first[0], first[i], first[i + 1])
            else:
                builder.triangle(first[0], first[i + 1], first[i])
    if cap_end:
        last = rings[-1]
        for i in range(1, count - 1):
            if flipped:
                builder.triangle(last[0], last[i + 1], last[i])
            else:
                builder.triangle(last[0], last[i], last[i + 1])


def _frame_normal(local, axes):
    origin, u, v, w = axes
    return vnorm(vadd(vadd(vmul(u, local[0]), vmul(v, local[1])), vmul(w, local[2])))


def tube(builder, start, end, radius, segments=16, radius_end=None, cap_start=True, cap_end=True,
         steps=2):
    """Round tube with optional taper; smooth-shaded around the circumference.

    `u`/`v` carry the radius so the ring is `origin + u*cos(t) + v*sin(t)` and
    the radial normal is the same expression normalised, which is what makes the
    result read as round rather than faceted.
    """
    axis = vsub(end, start)
    u, v, w = basis_from_w(axis)
    radius_end = radius if radius_end is None else radius_end
    profile = profile_circle(1.0, segments)
    normals = [(p[0], p[1], 0.0) for p in profile]
    frames = []
    for step in range(steps + 1):
        t = step / steps
        r = radius + (radius_end - radius) * t
        frames.append((lerp3(start, end, t), vmul(u, r), vmul(v, r), w))
    sweep(builder, profile, frames, cap_start, cap_end, smooth_normals=normals)


def swept_tube(builder, points, radius, segments=14, cap_start=True, cap_end=True):
    """Tube through a polyline; frames follow the smoothed tangent."""
    if len(points) < 2:
        return
    profile = profile_circle(1.0, segments)
    normals = [(p[0], p[1], 0.0) for p in profile]
    frames = []
    for index, point in enumerate(points):
        if index == 0:
            tangent = vsub(points[1], points[0])
        elif index == len(points) - 1:
            tangent = vsub(points[-1], points[-2])
        else:
            tangent = vsub(points[index + 1], points[index - 1])
        u, v, w = basis_from_w(tangent)
        r = radius[index] if isinstance(radius, (list, tuple)) else radius
        frames.append((point, vmul(u, r), vmul(v, r), w))
    sweep(builder, profile, frames, cap_start, cap_end, smooth_normals=normals)


def cone(builder, base, tip, radius, segments=14, cap_start=True):
    tube(builder, base, tip, radius, segments, radius_end=radius * 0.02, cap_start=cap_start, cap_end=False)


def rounded_box(builder, centre, size, radius, corner_segments=3, segments_along=2):
    """Chamfered box: the default solid for receivers, pouches and packs."""
    cx, cy, cz = centre
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    profile = profile_rounded_rect(hx, hy, min(radius, hx * 0.9, hy * 0.9), corner_segments)
    start = (cx, cy, cz - hz)
    end = (cx, cy, cz + hz)
    extrude(builder, profile, 0.0, hz * 2.0, origin=start,
            u=(1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0), w=(0.0, 0.0, 1.0))
    del end, segments_along


def box(builder, centre, size):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cx, cy, cz = centre
    p = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    builder.quad(p[0], p[3], p[2], p[1])   # -Z
    builder.quad(p[4], p[5], p[6], p[7])   # +Z
    builder.quad(p[0], p[1], p[5], p[4])   # -Y
    builder.quad(p[2], p[3], p[7], p[6])   # +Y
    builder.quad(p[1], p[2], p[6], p[5])   # +X
    builder.quad(p[3], p[0], p[4], p[7])   # -X


def slab(builder, half_u, half_v, radius, start, end, origin=(0.0, 0.0, 0.0),
         u=(1.0, 0.0, 0.0), v=(0.0, 0.0, 1.0), w=(0.0, 1.0, 0.0), corner_segments=4,
         cap_start=True, cap_end=True):
    """The workhorse: a chamfered slab along `w`, which is what a receiver is."""
    extrude(builder, profile_rounded_rect(half_u, half_v, radius, corner_segments),
            start, end, origin, u, v, w, cap_start, cap_end)


def profile_rail_tooth(half_width, half_height, protrusion, radius=0.001):
    """Rounded rectangle spanning `-half_height` to `half_height + protrusion`.

    A plain `profile_rounded_rect` is centred, so using one for a rail tooth
    makes the tooth grow downward through the rail as well as upward out of it.
    """
    top = half_height + protrusion
    points = []
    corner = min(radius, half_width * 0.9, (top + half_height) * 0.45)
    if corner <= 1e-6:
        return [(-half_width, -half_height), (half_width, -half_height),
                (half_width, top), (-half_width, top)]
    cu = half_width - corner
    corners = (
        (cu, -half_height + corner, -math.pi * 0.5, 0.0),
        (cu, top - corner, 0.0, math.pi * 0.5),
        (-cu, top - corner, math.pi * 0.5, math.pi),
        (-cu, -half_height + corner, math.pi, math.pi * 1.5),
    )
    for origin_u, origin_v, start, end in corners:
        for step in range(3):
            angle = start + (end - start) * (step / 3)
            points.append((origin_u + corner * math.cos(angle),
                           origin_v + corner * math.sin(angle)))
    return points


def rail(builder, start, end, width, height, teeth, tooth_depth=0.006, top=True):
    """Picatinny-style rail: a base bar plus evenly spaced cross teeth.

    The frame is built so the profile's first coordinate runs *across* the rail
    and its second is the rail's thickness; `basis_from_w` returns an up/side
    pair for a horizontal rail, so the two are swapped when the frames are built.
    Getting this backwards makes the teeth stand up as tall spikes.
    """
    axis = vsub(end, start)
    length = vlen(axis)
    if length <= 1e-6:
        return
    w = vnorm(axis)
    up, side, _ = basis_from_w(w)
    sweep(builder, profile_rounded_rect(width * 0.5, height * 0.5, 0.0012, 2),
          _frames_straight_side_up(start, side, up, w, 0.0, length), True, True)
    pitch = length / max(1, teeth)
    tooth = profile_rail_tooth(width * 0.5, height * 0.5, tooth_depth)
    for index in range(teeth):
        origin = vadd(start, vmul(w, (index + 0.5) * pitch - pitch * 0.3))
        sweep(builder, tooth,
              _frames_straight_side_up(origin, side, up, w, 0.0, pitch * 0.6), True, True)
    del top


def _frames_straight_side_up(origin, side, up, w, start, end):
    """Frames whose profile plane is `(side, up)` rather than `(u, v)`."""
    return [(vadd(origin, vmul(w, start)), side, up, w),
            (vadd(origin, vmul(w, end)), side, up, w)]


def rail_between(builder, start, end, width, height, teeth, tooth_depth=0.006):
    rail(builder, start, end, width, height, teeth, tooth_depth)


def vents(builder, centre, axis, count, radius, spacing, depth):
    """A row of round cut-look holes rendered as recessed cylinders."""
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    for index in range(count):
        offset = (index - (count - 1) * 0.5) * spacing
        base = vadd(centre, vmul(w, offset))
        tube(builder, vadd(base, vmul(v, -depth)), vadd(base, vmul(v, radius * 0.02 + depth * 0.2)),
             radius, 10, cap_start=False)


def screw(builder, centre, axis, radius, length):
    w = vnorm(axis)
    u, v, _ = basis_from_w(w)
    del u, v
    tube(builder, centre, vadd(centre, vmul(w, length)), radius, 8, cap_start=False)
