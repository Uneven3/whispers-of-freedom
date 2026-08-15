"""Generate the flat (uncrossed) grass blade (art/blender/grass/grass_blade_flat.blend).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_blade_flat.py

Same leaf profile as generate_grass_blade_single.py (grass_blade_common.
leaf_verts -- pointed tip, sunk base, waist row at 30% height, no tip_bend),
but only ONE plane instead of two crossed at 90 degrees. 2 tris total, half
the single variant's 4.

This exists to isolate one specific question raised after playing the
single/tuft comparison in scenes/grass_comparison.tscn: the tuft's extra
density barely read as different in motion (screenshots from
grass_density_probe.gd overstated it -- an isolated, static, close-up test
scene exaggerates gaps that get diluted at real field density; see
docs/AHORA.md), so before spending triangles on density, it's worth
checking the *other* direction -- does the single variant's own crossing
(2 perpendicular planes, there specifically so a blade never goes edge-on
invisible as the camera orbits -- see the "Crossed quads read as grass from
any angle" comment in grass_field.gd's history) actually earn its keep, or
would one flat plane look close enough for half the triangle cost?

The known risk this variant is deliberately reintroducing, so it can be
judged instead of assumed: a single flat plane vanishes to a hairline when
viewed exactly edge-on, and that angle sweeps past constantly as a
third-person camera orbits. A static screenshot can't show that -- has to
be judged walking around it with the camera actually moving.
"""

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

NAME = "grass_blade_flat"


def build_mesh() -> bpy.types.Object:
    bm = bmesh.new()
    place_leaf(bm, angle_deg=0.0)

    mesh = bpy.data.meshes.new("GrassBladeFlat")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBladeFlat", mesh)
    finish_object(obj, mesh)
    return obj


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene_units()
    build_mesh()
    save_blend(NAME)
    render_preview(
        NAME,
        mathutils.Vector((1.4, -1.4, 0.55)),
        mathutils.Vector((0.0, 0.0, 0.5)),
    )


if __name__ == "__main__":
    main()
