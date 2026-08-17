"""Renders a horizontal atlas of grass-CLUMP alpha-mask card textures
(art/blender/grass/grass_card_atlas.png) for the classic textured-billboard
grass system (docs/pasto_godot.md, pivot session: "6 simple tips to improve
grass billboards", Kammerbild).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/render_grass_card_alpha.py

Only alpha (silhouette coverage) matters -- color/lighting is discarded,
Godot's shader supplies the base/tip gradient itself via UV.y, same as it
used to via VERTEX.y. Each atlas cell is therefore authored in the card
camera's X/Z plane, not rendered by projecting a 3D tuft: a 3D leaf can face
the camera edge-on and contribute a nearly invisible line. The 3 cells are
wide, dense, deliberately 2D grass silhouettes; each card is a convincing
view of a whole tuft rather than a sparse projection of a few leaf meshes.
generate_grass_billboard_clump.py assigns each quad a column via baked UV
offset, not a per-surface material -- keeps one shared ShaderMaterial for
the whole clump.
"""

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grass_blade_common import BASE_SINK, GRASS_DIR, TIP_HEIGHT, setup_scene_units

NAME = "grass_card_atlas"

# Each cell uses a different dense, broad silhouette. These are deliberately
# separate from the 3D card arrangement: an alpha card is judged from its one
# camera direction, so it must compose well in that view by construction.
TUFT_LEAF_COUNTS = (11, 13, 15)
TUFT_TIP_SPREADS = (0.27, 0.31, 0.35)
ROOT_SPREAD = 0.10
HEIGHT_SCALE_RANGE = (0.72, 1.05)
LOW_LEAF_HEIGHT_SCALE_RANGE = (0.30, 0.68)
LEAF_HALF_WIDTH_RANGE = (0.018, 0.036)
LOW_LEAF_HALF_WIDTH_RANGE = (0.024, 0.048)
LEAF_CURVE_RANGE = (-0.075, 0.075)
RANDOM_SEED = 7  # each column derives RANDOM_SEED + column_index -- reproducible per column

# Sized from the widest authored silhouette so cards cannot bleed into the
# adjacent atlas cell if the ranges above change.
_MAX_RADIUS_EXTENT = max(TUFT_TIP_SPREADS) + max(LEAF_HALF_WIDTH_RANGE)
_SPACING_MARGIN = 1.15
COLUMN_SPACING = 2.0 * _MAX_RADIUS_EXTENT * _SPACING_MARGIN

PX_PER_UNIT = 700


def _leaf_center(root_x: float, tip_x: float, curve: float, height: float, fraction: float) -> mathutils.Vector:
    x = root_x + (tip_x - root_x) * fraction + math.sin(fraction * math.pi) * curve
    return mathutils.Vector((x, 0.0, BASE_SINK + (height - BASE_SINK) * fraction))


def _add_silhouette_leaf(
    bm: bmesh.types.BMesh,
    root_x: float,
    tip_x: float,
    height: float,
    half_width: float,
    curve: float,
) -> None:
    fractions = (0.0, 0.22, 0.52, 0.78, 1.0)
    width_fractions = (0.30, 1.0, 0.72, 0.30, 0.0)
    centers = [_leaf_center(root_x, tip_x, curve, height, fraction) for fraction in fractions]
    left: list[mathutils.Vector] = []
    right: list[mathutils.Vector] = []
    for i, center in enumerate(centers):
        previous = centers[max(0, i - 1)]
        following = centers[min(len(centers) - 1, i + 1)]
        direction = (following - previous).normalized()
        side = mathutils.Vector((-direction.z, 0.0, direction.x)) * (half_width * width_fractions[i])
        left.append(center - side)
        right.append(center + side)
    for i in range(len(centers) - 1):
        v0 = bm.verts.new(left[i])
        v1 = bm.verts.new(left[i + 1])
        v2 = bm.verts.new(right[i + 1])
        v3 = bm.verts.new(right[i])
        bm.faces.new((v0, v1, v2, v3))


def build_tuft_object(name: str, x_offset: float, rng: random.Random, leaf_count: int, tip_spread: float) -> None:
    bm = bmesh.new()
    low_leaf_count = leaf_count // 3
    for i in range(leaf_count):
        is_low_leaf = i < low_leaf_count
        height_range = LOW_LEAF_HEIGHT_SCALE_RANGE if is_low_leaf else HEIGHT_SCALE_RANGE
        width_range = LOW_LEAF_HALF_WIDTH_RANGE if is_low_leaf else LEAF_HALF_WIDTH_RANGE
        leaf_tip_spread = tip_spread * (1.18 if is_low_leaf else 1.0)
        root_x = rng.uniform(-ROOT_SPREAD, ROOT_SPREAD)
        tip_x = rng.uniform(-leaf_tip_spread, leaf_tip_spread)
        _add_silhouette_leaf(
            bm,
            root_x,
            tip_x,
            TIP_HEIGHT * rng.uniform(*height_range),
            rng.uniform(*width_range),
            rng.uniform(*LEAF_CURVE_RANGE),
        )

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

    num_columns = len(TUFT_LEAF_COUNTS)
    for i in range(num_columns):
        x = (i - (num_columns - 1) / 2.0) * COLUMN_SPACING
        rng = random.Random(RANDOM_SEED + i)
        build_tuft_object(f"Card{i}", x, rng, TUFT_LEAF_COUNTS[i], TUFT_TIP_SPREADS[i])

    total_width = num_columns * COLUMN_SPACING
    # The tallest silhouette leaf defines the card camera's vertical extent.
    height_scale_max = max(HEIGHT_SCALE_RANGE)
    max_z = TIP_HEIGHT * height_scale_max
    min_z = BASE_SINK * height_scale_max
    total_height = max_z - min_z
    mid_z = (max_z + min_z) / 2.0

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
