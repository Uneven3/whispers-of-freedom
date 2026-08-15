"""Generate the single crossed-leaf grass blade (art/blender/grass/grass_blade_single.blend).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_blade_single.py

Two crossed leaf-profile planes (see grass_blade_common.leaf_verts): 4 tris
total, the baseline blade shape used by GrassField's blade_asset_path default
(scripts/world/grass_field.gd). Godot imports the resulting .blend natively
(Editor Settings -> Filesystem -> Import -> Blender -> Blender Path must be
configured locally, see "Como trabajar en este repo" in docs/AHORA.md).

Correct outward normals + flat shading are set even though
scripts/world/grass_blade.gdshader is unshaded/cull_disabled today (it never
reads NORMAL) -- standard low-poly practice, matters if this .blend is opened
to learn from or if lighting is ever wired into the shader later.
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

NAME = "grass_blade_single"


def build_mesh() -> bpy.types.Object:
    bm = bmesh.new()
    place_leaf(bm, angle_deg=0.0)
    place_leaf(bm, angle_deg=90.0)

    mesh = bpy.data.meshes.new("GrassBladeCross")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBladeCross", mesh)
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
