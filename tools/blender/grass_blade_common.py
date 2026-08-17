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
HALF_WIDTH = 0.04  # matches grass_field.gd's fallback blade half-width — was
                    # 0.08, thinned after live-tuning blade_width_scale in the
                    # editor and settling on 0.5 (docs/AHORA.md, 2026-08-15);
                    # baked here instead of leaving the live knob at 0.5 so
                    # grass_field.gd's blade_width_scale stays a true 1.0 =
                    # "as authored" default
WAIST_HEIGHT = 0.30  # fraction of blade height where the profile is widest
BASE_SINK = -0.06  # base point sits below z=0 so it doesn't read as
                    # infinitely thin against the ground
TIP_HEIGHT = 1.0

BLADE_COLOR = (0.22, 0.42, 0.18, 1.0)  # matches grass_blade.gdshader's default uniform


def leaf_verts(half_width: float = HALF_WIDTH, tip_bend: float = 0.0) -> tuple:
    """The four corners of one leaf profile, local to a leaf standing at the
    origin facing +X, before any per-leaf rotation/translation: pointed tip,
    pointed sunk base, and a waist row at 30% height (see
    docs/AHORA.md's "Brizna modelada en Blender" entry for why the waist row
    exists — it's what lets the blade arch under the wind shader instead of
    hinging rigidly at two endpoints).

    tip_bend offsets the tip sideways (local X) from directly-above-the-waist,
    giving the *top* triangle (tip/waist_l/waist_r) a small static kink
    relative to the bottom one (base/waist_l/waist_r) -- a resting curve
    baked into the mesh, not the dynamic wind arch. Default 0.0 keeps the
    tip centered (the single blade's straight shape).
    """
    return (
        mathutils.Vector((tip_bend, 0.0, TIP_HEIGHT)),
        mathutils.Vector((-half_width, 0.0, WAIST_HEIGHT)),
        mathutils.Vector((half_width, 0.0, WAIST_HEIGHT)),
        mathutils.Vector((0.0, 0.0, BASE_SINK)),
    )


def place_leaf(
    bm: bmesh.types.BMesh,
    angle_deg: float,
    height_scale: float = 1.0,
    half_width: float = HALF_WIDTH,
    tip_bend: float = 0.0,
    offset: mathutils.Vector = None,
) -> None:
    """Builds one leaf (leaf_verts, height-scaled and tip-bent) into bm,
    facing angle_deg (rotated around Z) and rooted at offset.

    For a multi-leaf tuft, offset is what has to do the real work of
    separating leaves: leaf_verts() puts the tip and base ON the Z axis
    (x=y=0), so rotating a leaf that's still centered at the origin only
    spins which way its flat face points -- it never moves the tip or base
    away from a shared center (confirmed by looking at the imported mesh,
    not assumed: an earlier version relied on angle_deg alone and every leaf
    still grew from and to the same point). offset must be different per
    leaf, and large enough to matter relative to half_width, or several
    leaves will still read as one bunched-up column instead of an open tuft
    with visibly separate roots.

    angle_deg still matters for which way each already-separated leaf's flat
    card faces -- keeps the "readable from any angle" property the original
    2-leaf cross has, now across N leaves rooted at different points.
    """
    if offset is None:
        offset = mathutils.Vector((0.0, 0.0, 0.0))
    rotation = mathutils.Matrix.Rotation(math.radians(angle_deg), 4, "Z")
    verts = []
    for v in leaf_verts(half_width, tip_bend):
        scaled = mathutils.Vector((v.x, v.y, v.z * height_scale))
        verts.append(rotation @ scaled + offset)
    v_tip, v_waist_l, v_waist_r, v_base = (bm.verts.new(v) for v in verts)
    bm.faces.new((v_tip, v_waist_l, v_waist_r))
    bm.faces.new((v_base, v_waist_r, v_waist_l))


def place_card_quad(
    bm: bmesh.types.BMesh,
    angle_deg: float = 0.0,
    tilt_deg: float = 0.0,
    height_scale: float = 1.0,
    half_width: float = HALF_WIDTH,
    offset: mathutils.Vector = None,
    uv_column: int = 0,
    uv_columns_total: int = 1,
) -> None:
    """Rectangular 2-triangle billboard card (UV.y: 0 base / 1 tip, UV.x
    within [uv_column, uv_column+1] of a uv_columns_total-wide atlas)."""
    if offset is None:
        offset = mathutils.Vector((0.0, 0.0, 0.0))
    base_h = BASE_SINK * height_scale
    tip_h = TIP_HEIGHT * height_scale
    local = (
        mathutils.Vector((-half_width, 0.0, base_h)),
        mathutils.Vector((half_width, 0.0, base_h)),
        mathutils.Vector((half_width, 0.0, tip_h)),
        mathutils.Vector((-half_width, 0.0, tip_h)),
    )
    rotation = mathutils.Matrix.Rotation(math.radians(angle_deg), 4, "Z") @ mathutils.Matrix.Rotation(math.radians(tilt_deg), 4, "X")
    verts = [bm.verts.new(rotation @ v + offset) for v in local]
    face = bm.faces.new(verts)
    uv_layer = bm.loops.layers.uv.verify()
    u0 = uv_column / uv_columns_total
    u1 = (uv_column + 1) / uv_columns_total
    for loop, uv in zip(face.loops, ((u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0))):
        loop[uv_layer].uv = uv


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
