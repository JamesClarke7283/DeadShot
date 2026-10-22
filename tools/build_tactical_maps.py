#!/usr/bin/env python3
"""Build two deterministic arenas, including collision, radar and bot routes.

Uses the same mesh DSL as the existing assets. Run from any directory; no
Blender or external packages are needed. Geometry stays in metres, Y up.
"""
import json
import math
from pathlib import Path

from deadshot_detail import Builder, box, rounded_box, tube

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


class Arena:
    def __init__(self, identifier, name, description, snow=False):
        self.snow = snow
        self.meshes = {}
        self.data = {
            "schema": 1, "id": identifier, "name": name, "description": description,
            "source": "tools/build_tactical_maps.py", "coordinateSystem": "Y-up metres",
            "geometries": {}, "materials": {}, "nodes": [], "collisionBoxes": [],
            "spawns": [], "waypoints": [], "terrain": {"kind": "flat"},
            "bounds": {"minX": -52, "maxX": 52, "minZ": -44, "maxZ": 44},
            "environment": {
                "skyColor": [0.57, 0.70, 0.85] if snow else [0.56, 0.69, 0.8],
                "groundColor": [0.24, 0.29, 0.34] if snow else [0.09, 0.1, 0.11],
                "sunColor": [0.85, 0.92, 1.0] if snow else [1.0, 0.88, 0.66],
                "sunDirection": [-0.5, 1.0, 0.3], "sunIntensity": 1.8 if snow else 2.2,
                "fogColor": [0.52, 0.62, 0.7], "fogNear": 85, "fogFar": 240,
                "clouds": {"cover": 0.48 if snow else 0.28, "sharpness": 1.6, "brightness": 1.2, "height": 0.18},
            },
        }
        self.material("ground", "snow" if snow else "asphalt", [0.55, 0.63, 0.7] if snow else [0.14, 0.15, 0.16])
        self.material("wall", "concrete", [0.28, 0.33, 0.38] if snow else [0.42, 0.36, 0.28])
        self.material("trim", "metal", [0.15, 0.19, 0.21], metallic=0.6)
        self.material("orange", "painted_metal", [0.48, 0.17, 0.05])
        self.material("blue", "painted_metal", [0.09, 0.23, 0.31])
        self.material("red", "painted_metal", [0.36, 0.10, 0.07])
        self.material("wood", "wood", [0.29, 0.21, 0.12])
        self.material("glass", "glass", [0.04, 0.10, 0.14], roughness=0.25)
        self.material("paint", "concrete", [0.68, 0.58, 0.26])
        self.material("light", "glass", [0.8, 0.75, 0.5], emissive=[0.6, 0.5, 0.28], emissiveEnergy=1.3)
        self.material("snow", "snow", [0.58, 0.68, 0.75])
        self.add_box("ground", (0, -0.3, 0), (106, 0.6, 90), collision=False, rounded=False)
        for center, size in [((-53, 2, 0), (2, 4, 90)), ((53, 2, 0), (2, 4, 90)),
                             ((0, 2, -45), (106, 4, 2)), ((0, 2, 45), (106, 4, 2))]:
            self.add_box("wall", center, size)
            self.add_box("trim", (center[0], 4.1, center[2]), (size[0] + 0.1, 0.2, size[2] + 0.1), False)

    def material(self, name, family, color, **extra):
        self.data["materials"][name] = {"name": name, "surface": family, "color": color,
            "opacity": 1, "transparent": False, "doubleSide": False, "depthTest": True,
            "outline": False, "roughness": 0.8, **extra}
        self.meshes[name] = Builder()

    def add_box(self, material, center, size, collision=True, rounded=True):
        if rounded:
            rounded_box(self.meshes[material], center, size, min(0.09, min(size) * 0.18), 2, 1)
        else:
            box(self.meshes[material], center, size)
        if collision:
            self.data["collisionBoxes"].append({"min": [round(center[i] - size[i] / 2, 4) for i in range(3)],
                                                "max": [round(center[i] + size[i] / 2, 4) for i in range(3)]})

    def pipe(self, start, end, radius=0.09, material="trim"):
        tube(self.meshes[material], start, end, radius, 10, steps=1)

    def building(self, x, z, width=16, depth=12, height=5, face=1):
        # Shell with a four-metre doorway, rather than an impassable solid box.
        wall = 0.5
        for sx in [-1, 1]:
            self.add_box("wall", (x + sx * (width / 2 - wall / 2), height / 2, z), (wall, height, depth))
        self.add_box("wall", (x, height / 2, z - face * (depth / 2 - wall / 2)), (width, height, wall))
        for sx in [-1, 1]:
            self.add_box("wall", (x + sx * (width / 4 + 1), height / 2, z + face * (depth / 2 - wall / 2)),
                         (width / 2 - 2, height, wall))
        self.add_box("wall", (x, height - 0.6, z + face * (depth / 2 - wall / 2)), (4, 1.2, wall))
        self.add_box("trim", (x, height + 0.15, z), (width + 0.5, 0.3, depth + 0.5))
        if self.snow:
            self.add_box("snow", (x, height + 0.36, z), (width + 0.3, 0.12, depth + 0.3), False)
        for sx in [-1, 1]:
            self.add_box("orange", (x + sx * 2.1, 1.6, z + face * (depth / 2 + 0.08)), (0.18, 3.2, 0.2), False)
            self.add_box("glass", (x + sx * (width / 4 + 1), 2.8, z + face * (depth / 2 + 0.035)), (3, 1.5, 0.05), False, False)
        self.add_box("light", (x, 3.5, z + face * (depth / 2 + 0.16)), (1.2, 0.14, 0.18), False)

    def container(self, x, z, color, width=5, depth=12):
        self.add_box(color, (x, 1.6, z), (width, 3.2, depth))
        for sx in [-1, 1]:
            for dz in range(-int(depth / 2) + 1, int(depth / 2)):
                self.add_box("trim", (x + sx * (width / 2 + 0.04), 1.6, z + dz), (0.08, 2.9, 0.10), False)
            self.pipe((x + sx * (width / 2 - 0.5), 0.25, z + depth / 2 + 0.08),
                      (x + sx * (width / 2 - 0.5), 2.95, z + depth / 2 + 0.08), 0.05)
        self.add_box("trim", (x, 3.27, z), (width + 0.12, 0.14, depth + 0.12), False)

    def crate(self, x, z):
        self.add_box("wood", (x, 0.9, z), (2.3, 1.8, 2.3))
        for sx in [-1, 1]:
            self.add_box("trim", (x + sx * 0.8, 0.9, z), (0.1, 1.84, 2.34), False)

    def segment_free(self, a, b, clearance=0.8):
        # Expanded AABB slab test also prevents diagonal corner cutting.
        for item in self.data["collisionBoxes"]:
            lo, hi = item["min"], item["max"]
            if hi[1] <= 0.3 or lo[1] >= 1.8:
                continue
            near, far = 0.0, 1.0
            for axis in [0, 2]:
                delta = b[axis] - a[axis]
                if abs(delta) < 1e-8:
                    if a[axis] < lo[axis] - clearance or a[axis] > hi[axis] + clearance:
                        near = 2.0
                        break
                else:
                    t0 = (lo[axis] - clearance - a[axis]) / delta
                    t1 = (hi[axis] + clearance - a[axis]) / delta
                    near, far = max(near, min(t0, t1)), min(far, max(t0, t1))
            if near <= far:
                return False
        return True

    def finish(self):
        points = {}
        for x in range(-48, 49, 4):
            for z in range(-40, 41, 4):
                if self.segment_free((x, 0, z), (x, 0, z)):
                    point = {"id": len(points), "position": [x, 0, z], "neighbors": []}
                    points[x, z] = point
        for (x, z), point in points.items():
            for dx, dz in [(4, 0), (-4, 0), (0, 4), (0, -4), (4, 4), (-4, 4), (4, -4), (-4, -4)]:
                other = points.get((x + dx, z + dz))
                if other and self.segment_free(point["position"], other["position"]):
                    point["neighbors"].append(other["id"])
        self.data["waypoints"] = list(points.values())
        # Each side gets nine pads across its safe staging area.
        for team, x in [("blue", -44), ("red", 44)]:
            for z in range(-32, 33, 8):
                assert (x, z) in points, (team, x, z)
                self.data["spawns"].append({"team": team, "position": [x, 0, z], "yaw": math.pi / 2 if x < 0 else -math.pi / 2})
        candidates = [(0, 36), (0, -36), (-36, 36), (36, -36), (-36, -36), (36, 36), (-36, 0), (36, 0), (0, 0)]
        for x, z in candidates:
            assert (x, z) in points, (x, z)
            self.data["spawns"].append({"team": "ffa", "position": [x, 0, z], "yaw": 0})
        visited, pending = set(), [0]
        while pending:
            ident = pending.pop()
            if ident not in visited:
                visited.add(ident)
                pending.extend(self.data["waypoints"][ident]["neighbors"])
        assert len(visited) == len(points), "All navigation points must connect"
        for material, mesh in self.meshes.items():
            if not mesh.indices:
                continue
            self.data["geometries"][material] = mesh.record()
            self.data["nodes"].append({"name": "terrain" if material == "ground" else material,
                "geometry": material, "material": material, "matrix": IDENTITY,
                "visible": True, "castShadow": material != "ground", "instanced": False})
        path = ROOT / "data" / "maps" / (self.data["id"] + ".json")
        path.write_text(json.dumps(self.data, separators=(",", ":")) + "\n")
        print(f"Built {path.name}: {len(points)} connected waypoints, {len(self.data['collisionBoxes'])} colliders")


def freight_yard():
    arena = Arena("freight_yard", "Freight Yard", "Rail sidings, container flanks and a warehouse with a central crossfire lane.")
    arena.building(0, -29, 22, 12, 6, 1)
    for x in [-24, 24]:
        for z in [-12, 12]:
            arena.container(x, z, "orange" if x < 0 else "blue")
    for x in [-10, 10]:
        arena.container(x, 25, "red", 5, 10)
    # Parallel rails along the central lane, with sleepers below walking height.
    for z in [-3.3, 3.3]:
        arena.add_box("trim", (0, 0.08, z), (100, 0.16, 0.12), False, False)
    for x in range(-48, 49, 3):
        arena.add_box("wood", (x, 0.025, 0), (0.22, 0.05, 8), False, False)
    for x, z in [(-12, -12), (12, 12), (-32, 25), (32, -25), (-8, 13), (8, -12)]:
        arena.crate(x, z)
    # Gantry legs are solid; the beam is safely above player height.
    for x in [-17, 17]:
        arena.add_box("trim", (x, 5.5, 4), (0.7, 11, 0.7))
        arena.add_box("orange", (x, 1.0, 4), (0.76, 2, 0.76), False)
    arena.add_box("orange", (0, 10.7, 4), (35, 0.8, 1.0))
    arena.pipe((0, 10.4, 4), (0, 7.8, 4), 0.08)
    arena.add_box("trim", (0, 7.6, 4), (0.5, 0.5, 0.5), False)
    arena.finish()


def snow_outpost():
    arena = Arena("snow_outpost", "Snow Outpost", "Snowbound communications base with enterable bunkers and open perimeter routes.", True)
    for x, z in [(-24, -23), (24, 23), (-24, 23), (24, -23)]:
        arena.building(x, z, 14, 12, 4.5, 1 if z < 0 else -1)
    for x, z in [(-11, -8), (11, 8), (-28, 0), (28, 0)]:
        arena.add_box("wall", (x, 0.8, z), (6, 1.6, 1.2))
        arena.add_box("snow", (x, 1.65, z), (6.1, 0.1, 1.3), False)
    # Communications tower: a landmark above low cover north of the courtyard.
    arena.add_box("wall", (0, 0.65, -28), (4, 1.3, 4))
    for x in [-1.2, 1.2]:
        for z in [-29.2, -26.8]:
            arena.pipe((x, 1.3, z), (0, 12, -28), 0.14)
    for y in [4, 7, 10]:
        arena.pipe((-1.2, y, -28), (1.2, y + 2, -28), 0.08)
        arena.pipe((1.2, y, -28), (-1.2, y + 2, -28), 0.08)
    arena.pipe((0, 11, -28), (0, 15, -28), 0.1)
    arena.add_box("light", (0, 15, -28), (0.3, 0.3, 0.3), False)
    for x, z in [(-9, 21), (9, -29), (-17, 5), (17, -5)]:
        arena.crate(x, z)
        arena.add_box("snow", (x, 1.85, z), (2.4, 0.1, 2.4), False)
    for x in [-39, 39]:
        for z in [-16, 16]:
            arena.pipe((x, 0, z), (x, 7, z), 0.12)
            arena.add_box("light", (x, 7, z), (1.0, 0.2, 0.4), False)
    arena.finish()


if __name__ == "__main__":
    freight_yard()
    snow_outpost()
