"""Renders a horizontal atlas of grass-blade alpha-mask card textures
(art/blender/grass/grass_card_atlas.png) from the existing leaf profile,
for the classic textured-billboard grass system (docs/pasto_godot.md,
pivot session: "6 simple tips to improve grass billboards", Kammerbild).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/render_grass_card_alpha.py

Only alpha (silhouette coverage) matters -- color/lighting is discarded,
Godot's shader supplies the base/tip gradient itself via UV.y, same as it
used to via VERTEX.y. Multiple columns (slightly different half_width/
tip_bend) give the "texturas diversas" variety the video's tip 2 asks for;
generate_grass_billboard_clump.py assigns each quad a column via baked UV
offset, not a per-surface material -- keeps one shared ShaderMaterial for
the whole clump.
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grass_blade_common import (
    BASE_SINK,
    GRASS_DIR,
    TIP_HEIGHT,
    leaf_verts,
    setup_scene_units,
)

NAME = "grass_card_atlas"
COLUMN_HALF_WIDTHS = (0.035, 0.04, 0.045)
COLUMN_TIP_BENDS = (-0.04, 0.0, 0.05)
COLUMN_SPACING = 0.16
PX_PER_UNIT = 700


def build_leaf_object(name: str, half_width: float, tip_bend: float, x_offset: float) -> None:
    bm = bmesh.new()
    v_tip, v_wl, v_wr, v_base = (bm.verts.new(v) for v in leaf_verts(half_width, tip_bend))
    bm.faces.new((v_tip, v_wl, v_wr))
    bm.faces.new((v_base, v_wr, v_wl))
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = mathutils.Vector((x_offset, 0.0, 0.0))
    material = bpy.data.materials.new(name + "Mat")
    material.use_nodes = True
    mesh.materials.append(material)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene_units()

    num_columns = len(COLUMN_HALF_WIDTHS)
    for i in range(num_columns):
        x = (i - (num_columns - 1) / 2.0) * COLUMN_SPACING
        build_leaf_object(f"Card{i}", COLUMN_HALF_WIDTHS[i], COLUMN_TIP_BENDS[i], x)

    total_width = num_columns * COLUMN_SPACING
    total_height = TIP_HEIGHT - BASE_SINK
    mid_z = (TIP_HEIGHT + BASE_SINK) / 2.0

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_y = max(64, int(total_height * PX_PER_UNIT))
    scene.render.resolution_x = max(64, int(total_width * PX_PER_UNIT))
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    output = GRASS_DIR / f"{NAME}.png"
    scene.render.filepath = str(output)

    cam_data = bpy.data.cameras.new("AlphaCam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "VERTICAL"
    cam_data.ortho_scale = total_height
    cam_obj = bpy.data.objects.new("AlphaCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = mathutils.Vector((0.0, -5.0, mid_z))
    cam_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam_obj

    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    print(f"[{NAME}] wrote {output} ({scene.render.resolution_x}x{scene.render.resolution_y}, {num_columns} columns)")


if __name__ == "__main__":
    main()
