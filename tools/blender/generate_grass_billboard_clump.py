"""Generates the classic textured-billboard grass clump
(art/blender/grass/grass_billboard_clump.blend), replacing the procedural
LOD0/LOD1/LOD2 system with the 6 techniques from Kammerbild's "6 simple
tips to improve grass billboards in CGI" (docs/pasto_godot.md, pivot
session): 4 individualized card quads (own root offset, own scale, own
atlas column) plus a tilt on top of yaw so the clump stays visible from a
top-down angle. Base-fade (technique 4) is a shader concern (UV.y-driven),
not baked here.

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_billboard_clump.py

Requires grass_card_atlas.png to already exist (run
render_grass_card_alpha.py first) -- this script only builds geometry/UVs,
it doesn't render the texture itself.
"""

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grass_blade_common import (
    finish_object,
    place_card_quad,
    render_preview,
    save_blend,
    setup_scene_units,
)

NAME = "grass_billboard_clump"
ATLAS_COLUMNS = 3
ROOT_ANGLES_DEG = (45.0, 135.0, 225.0, 315.0)
ANGLE_JITTER_DEG = 12.0
ROOT_RADIUS = 0.09
ROOT_RADIUS_JITTER = 0.02
TILT_RANGE_DEG = (8.0, 18.0)
HEIGHT_SCALE_RANGE = (0.85, 1.05)
HALF_WIDTH_RANGE = (0.06, 0.09)
RANDOM_SEED = 7


def build_mesh() -> bpy.types.Object:
    rng = random.Random(RANDOM_SEED)
    bm = bmesh.new()
    for i, root_angle_deg in enumerate(ROOT_ANGLES_DEG):
        jittered_angle_deg = root_angle_deg + rng.uniform(-ANGLE_JITTER_DEG, ANGLE_JITTER_DEG)
        jittered_angle = math.radians(jittered_angle_deg)
        radius = ROOT_RADIUS + rng.uniform(-ROOT_RADIUS_JITTER, ROOT_RADIUS_JITTER)
        offset = mathutils.Vector((
            math.cos(jittered_angle) * radius,
            math.sin(jittered_angle) * radius,
            0.0,
        ))
        place_card_quad(
            bm,
            angle_deg=jittered_angle_deg,
            tilt_deg=rng.uniform(*TILT_RANGE_DEG) * rng.choice((-1.0, 1.0)),
            height_scale=rng.uniform(*HEIGHT_SCALE_RANGE),
            half_width=rng.uniform(*HALF_WIDTH_RANGE),
            offset=offset,
            uv_column=i % ATLAS_COLUMNS,
            uv_columns_total=ATLAS_COLUMNS,
        )

    mesh = bpy.data.meshes.new("GrassBillboardClumpMesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBillboardClump", mesh)
    finish_object(obj, mesh)
    return obj


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene_units()
    build_mesh()
    save_blend(NAME)
    render_preview(
        NAME,
        mathutils.Vector((1.6, -1.6, 0.6)),
        mathutils.Vector((0.0, 0.0, 0.45)),
    )


if __name__ == "__main__":
    main()
