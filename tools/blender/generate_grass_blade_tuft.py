"""Generate the tuft grass blade (art/blender/grass/grass_blade_tuft.blend).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_blade_tuft.py

Same leaf profile as generate_grass_blade_single.py (grass_blade_common.
leaf_verts -- pointed tip, sunk base, waist row at 30% height), but 4 leaves
in an X instead of 2 crossed: each rooted at its OWN ground position (not a
shared origin), arranged so the four roots themselves form a small X, plus a
slight static bend baked into each leaf's top triangle. 8 tris total (4
leaves x 2 tris), vs. 4 for the single variant -- more silhouette per extra
triangle than just widening one blade, and each MultiMesh instance covers
more of the gaps a neighboring instance would otherwise leave (the
"density/holes" goal), instead of 4 blades pivoting from one point.

**Went through two wrong designs before this one, both caught by looking at
the result, not assumed correct on paper:**
1. First version relied on angle_deg (a Z rotation) alone to spread 4 leaves.
   leaf_verts() puts the tip and base ON the Z axis, so rotating a leaf
   still centered at the origin never moves them -- all 4 leaves grew from
   and to the same point, just facing different directions. Read as one
   thick column, not a tuft.
2. Second version added lean_deg (tip the whole leaf away from vertical
   before the Z rotation). That did separate the leaves, but it's not what
   was actually asked for: the leaves still pivoted from one shared root,
   just leaning outward from it -- not "4 or 5 blades that don't share an
   origin, like an X, covering the holes other blades leave." It also had no
   answer for "the top triangle should bend a little" -- lean tips the
   *whole* rigid leaf, not just the part above the waist.
3. This version: leaf_verts() gained tip_bend (a small sideways offset of
   just the tip, so only the top triangle kinks relative to the bottom one
   -- a static resting curve, distinct from the wind shader's dynamic arch).
   place_leaf()'s offset is now the real separator: each leaf's root sits at
   its own point, arranged in an X (see ROOT_ANGLES_DEG below), not
   pivoting from a shared center.
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

# Each leaf's root sits out along one arm of an X (not at a shared center),
# facing roughly the same direction its root is offset toward -- four
# separate little blades planted around a small clump, not one blade
# pivoting on four spokes.
ROOT_ANGLES_DEG = (45.0, 135.0, 225.0, 315.0)
ANGLE_JITTER_DEG = 12.0
ROOT_RADIUS = 0.09  # the real separator -- comparable to half_width, not a few mm
ROOT_RADIUS_JITTER = 0.02
TIP_BEND_RANGE = (0.04, 0.09)  # small kink in the top triangle only -- "no mucho"
HEIGHT_SCALE_RANGE = (0.85, 1.05)
HALF_WIDTH_RANGE = (0.06, 0.09)
RANDOM_SEED = 7  # fixed so the asset is reproducible across regenerations


def build_mesh() -> bpy.types.Object:
    rng = random.Random(RANDOM_SEED)
    bm = bmesh.new()
    for root_angle_deg in ROOT_ANGLES_DEG:
        jittered_angle_deg = root_angle_deg + rng.uniform(-ANGLE_JITTER_DEG, ANGLE_JITTER_DEG)
        jittered_angle = math.radians(jittered_angle_deg)
        radius = ROOT_RADIUS + rng.uniform(-ROOT_RADIUS_JITTER, ROOT_RADIUS_JITTER)
        offset = mathutils.Vector((
            math.cos(jittered_angle) * radius,
            math.sin(jittered_angle) * radius,
            0.0,
        ))
        height_scale = rng.uniform(*HEIGHT_SCALE_RANGE)
        half_width = rng.uniform(*HALF_WIDTH_RANGE)
        tip_bend = rng.uniform(*TIP_BEND_RANGE) * rng.choice((-1.0, 1.0))
        place_leaf(
            bm,
            angle_deg=jittered_angle_deg,
            height_scale=height_scale,
            half_width=half_width,
            tip_bend=tip_bend,
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
