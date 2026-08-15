"""Generate the tuft grass blade (art/blender/grass/grass_blade_tuft.blend).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_blade_tuft.py

Same leaf profile as generate_grass_blade_single.py (grass_blade_common.
leaf_verts -- pointed tip, sunk base, waist row at 30% height), but 4 leaves
arranged radially (0/90/180/270 degrees) instead of 2 crossed, each with a
small deterministic jitter (fixed seed, reproducible) in angle/height/width
plus a small random root offset -- so it reads as a little clump instead of a
symmetric pinwheel. 8 tris total (4 leaves x 2 tris), vs. 4 for the single
variant: this is the "occupies more space" alternative asked for alongside
the single blade, to compare both by eye in scenes/grass_comparison.tscn
before picking one (or before this becomes relevant again for LOD tiers).

place_leaf() rotates+translates the *whole* leaf (all 4 vertices) as one
rigid shape per call -- offsetting only the base vertex would leave a
dangling corner instead of actually shifting where the leaf roots from.
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
    place_leaf,
    render_preview,
    save_blend,
    setup_scene_units,
)

NAME = "grass_blade_tuft"

BASE_ANGLES_DEG = (0.0, 90.0, 180.0, 270.0)
ANGLE_JITTER_DEG = 10.0
HEIGHT_SCALE_RANGE = (0.82, 1.05)
HALF_WIDTH_RANGE = (0.06, 0.09)
BASE_OFFSET_RADIUS = 0.025
RANDOM_SEED = 7  # fixed so the asset is reproducible across regenerations


def build_mesh() -> bpy.types.Object:
    rng = random.Random(RANDOM_SEED)
    bm = bmesh.new()
    for base_angle in BASE_ANGLES_DEG:
        angle = base_angle + rng.uniform(-ANGLE_JITTER_DEG, ANGLE_JITTER_DEG)
        height_scale = rng.uniform(*HEIGHT_SCALE_RANGE)
        half_width = rng.uniform(*HALF_WIDTH_RANGE)
        offset_angle = rng.uniform(0.0, math.tau)
        offset_radius = rng.uniform(0.0, BASE_OFFSET_RADIUS)
        offset = mathutils.Vector((
            math.cos(offset_angle) * offset_radius,
            math.sin(offset_angle) * offset_radius,
            0.0,
        ))
        place_leaf(
            bm,
            angle_deg=angle,
            height_scale=height_scale,
            half_width=half_width,
            offset=offset,
        )

    mesh = bpy.data.meshes.new("GrassBladeTuft")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBladeTuft", mesh)
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
