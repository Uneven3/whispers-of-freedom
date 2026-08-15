"""Shared Blender scene/geometry/export helpers for grass blade generators.

This module deliberately contains no per-variant arrangement logic — each
generate_grass_blade_*.py script decides how many leaves to place and where,
and calls into these helpers for the parts that don't vary: the single-leaf
profile itself, scene setup, material, saving, and the cheap preview render.
"""

import math
from pathlib import Path

import bmesh
import bpy
import mathutils

REPO_ROOT = Path(__file__).resolve().parents[2]
GRASS_DIR = REPO_ROOT / "art" / "blender" / "grass"

# Unit leaf: height baked at 1.0 along Blender's native Z-up (Godot's .blend
# importer converts to Y-up on import, same as the glTF exporter under the
# hood). grass_field.gd rescales the Y axis at runtime to match its
# max_blade_height @export knob, so these assets never need regenerating just
# because that knob changes.
HALF_WIDTH = 0.08  # matches grass_field.gd's fallback blade half-width
WAIST_HEIGHT = 0.30  # fraction of blade height where the profile is widest
BASE_SINK = -0.06  # base point sits below z=0 so it doesn't read as
                    # infinitely thin against the ground
TIP_HEIGHT = 1.0

BLADE_COLOR = (0.22, 0.42, 0.18, 1.0)  # matches grass_blade.gdshader's default uniform


def leaf_verts(half_width: float = HALF_WIDTH) -> tuple:
    """The four corners of one leaf profile, local to a leaf standing at the
    origin facing +X, before any per-leaf rotation/translation: pointed tip,
    pointed sunk base, and a waist row at 30% height (see
    docs/AHORA.md's "Brizna modelada en Blender" entry for why the waist row
    exists — it's what lets the blade arch under the wind shader instead of
    hinging rigidly at two endpoints).
    """
    return (
        mathutils.Vector((0.0, 0.0, TIP_HEIGHT)),
        mathutils.Vector((-half_width, 0.0, WAIST_HEIGHT)),
        mathutils.Vector((half_width, 0.0, WAIST_HEIGHT)),
        mathutils.Vector((0.0, 0.0, BASE_SINK)),
    )


def place_leaf(
    bm: bmesh.types.BMesh,
    angle_deg: float,
    height_scale: float = 1.0,
    half_width: float = HALF_WIDTH,
    lean_deg: float = 0.0,
    offset: mathutils.Vector = None,
) -> None:
    """Builds one leaf (leaf_verts, height-scaled) into bm.

    leaf_verts() puts the tip and base ON the Z axis (x=y=0) -- only the
    waist corners are off-axis. Rotating a point that already sits on the
    rotation axis does nothing, so angle_deg alone (a Z rotation) never
    separates several leaves' tips/bases: it only spins which way each
    leaf's flat face points, while every leaf keeps growing from and to the
    same central point. That's fine for a single crossed blade (2 planes
    sharing one growth axis reads fine from any angle) but produces a
    bunched-up column instead of an open clump for a multi-leaf tuft.

    lean_deg tips the leaf away from vertical around its own local X axis
    (its width axis) *before* the Z rotation, so its tip genuinely moves
    away from the shared center -- angle_deg then spreads several leaned
    leaves out into different compass directions. offset adds a further,
    smaller shift of the whole leaf (still applied to all 4 vertices as one
    rigid shape, not just one corner).
    """
    if offset is None:
        offset = mathutils.Vector((0.0, 0.0, 0.0))
    lean = mathutils.Matrix.Rotation(math.radians(lean_deg), 4, "X")
    rotation = mathutils.Matrix.Rotation(math.radians(angle_deg), 4, "Z")
    verts = []
    for v in leaf_verts(half_width):
        scaled = mathutils.Vector((v.x, v.y, v.z * height_scale))
        verts.append(rotation @ (lean @ scaled) + offset)
    v_tip, v_waist_l, v_waist_r, v_base = (bm.verts.new(v) for v in verts)
    bm.faces.new((v_tip, v_waist_l, v_waist_r))
    bm.faces.new((v_base, v_waist_r, v_waist_l))


def setup_scene_units() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def finish_object(obj: bpy.types.Object, mesh: bpy.types.Mesh) -> None:
    """Links obj/mesh into the scene, recalculates outward normals, flat
    shades, and assigns a shared M_Grass material -- standard low-poly
    finishing pass, kept even though grass_blade.gdshader is unshaded today
    (see generate_grass_blade_single.py's docstring for why)."""
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_flat()

    material = bpy.data.materials.new("M_Grass")
    principled = next(
        n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"
    )
    principled.inputs["Base Color"].default_value = BLADE_COLOR
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Roughness"].default_value = 0.9
    mesh.materials.append(material)


def save_blend(name: str) -> Path:
    GRASS_DIR.mkdir(parents=True, exist_ok=True)
    output = GRASS_DIR / f"{name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    print(f"[{name}] wrote {output}")
    return output


def render_preview(
    name: str, cam_location: mathutils.Vector, target: mathutils.Vector
) -> Path:
    """Cheap visual QA: a small render so a human can check the shape without
    opening Blender or Godot."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    output = GRASS_DIR / f"{name}_preview.png"
    scene.render.filepath = str(output)
    scene.render.image_settings.file_format = "PNG"

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = cam_location
    cam_obj.rotation_euler = (target - cam_location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    light_data = bpy.data.lights.new("PreviewSun", type="SUN")
    light_data.energy = 3.0
    light_obj = bpy.data.objects.new("PreviewSun", light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(55), 0.0, math.radians(35))

    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    print(f"[{name}] wrote preview {output}")
    return output
