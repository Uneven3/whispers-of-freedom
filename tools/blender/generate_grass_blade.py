"""Generate the low-poly grass blade mesh for GrassField (scripts/world/grass_field.gd).

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_blade.py

Godot imports the resulting .blend natively (Editor Settings -> Filesystem ->
Import -> Blender -> Blender Path must point at the local `blender` binary;
see "Como trabajar en este repo" in docs/AHORA.md) -- no glTF export step and
no Bevy-style naming contract, unlike the sibling breath-of-freedom project.

Blade shape: two crossed leaf-profile planes (4 verts / 2 tris each, 4 tris
total -- the same triangle budget as the flat-rectangle crossed quad this
replaces in grass_field.gd). Each plane is 2 triangles joined at a horizontal
"waist" edge at 30% of the blade height, pointed at both the tip and the
(sunk) base, instead of a flat-cut rectangle. That waist row is what lets the
blade arch under the wind shader (grass_blade.gdshader bends vertices
proportional to local VERTEX.y) instead of hinging rigidly at two endpoints,
and the pointed silhouette reads as a leaf instead of a strip of paper. Shape
and the 6 cm base sink carry over measured research from the sibling
breath-of-freedom project (docs/BOTWGrass.md: "La brizna: dos triangulos
unidos por una arista horizontal").
"""

import math
from pathlib import Path

import bmesh
import bpy
import mathutils

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "art" / "blender" / "grass"
OUTPUT_BLEND = OUTPUT_DIR / "grass_blade.blend"
PREVIEW_PNG = OUTPUT_DIR / "grass_blade_preview.png"

# Unit blade: height baked at 1.0. grass_field.gd rescales the Y axis at
# runtime to match its max_blade_height @export knob, so this asset never
# needs regenerating just because that knob changes.
HALF_WIDTH = 0.08  # matches the current half-width `w` in grass_field.gd
WAIST_HEIGHT = 0.30  # fraction of blade height where the profile is widest
BASE_SINK = -0.06  # base point sits below y=0 so it doesn't read as
                    # infinitely thin against the ground
TIP_HEIGHT = 1.0

BLADE_COLOR = (0.22, 0.42, 0.18, 1.0)  # matches grass_blade.gdshader's default uniform


def leaf_plane(bm: bmesh.types.BMesh, axis: str) -> None:
    """Add one leaf-profile plane (2 tris) to bm, spanning the given axis.

    Authored in Blender's native Z-up: height runs along Z, the two crossed
    planes span X and Y. Godot's .blend importer converts to Y-up on import
    (same conversion the glTF exporter does under the hood), so this becomes
    the same "one plane along X, one along Z, height along Y" cross that
    grass_field.gd's MultiMesh already expects -- no coordinates need to be
    pre-converted here.
    """
    tip = bm.verts.new((0.0, 0.0, TIP_HEIGHT))
    base = bm.verts.new((0.0, 0.0, BASE_SINK))
    if axis == "x":
        waist_l = bm.verts.new((-HALF_WIDTH, 0.0, WAIST_HEIGHT))
        waist_r = bm.verts.new((HALF_WIDTH, 0.0, WAIST_HEIGHT))
    else:
        waist_l = bm.verts.new((0.0, -HALF_WIDTH, WAIST_HEIGHT))
        waist_r = bm.verts.new((0.0, HALF_WIDTH, WAIST_HEIGHT))
    bm.faces.new((tip, waist_l, waist_r))
    bm.faces.new((base, waist_r, waist_l))


def build_mesh() -> bpy.types.Object:
    bm = bmesh.new()
    leaf_plane(bm, "x")
    leaf_plane(bm, "z")

    mesh = bpy.data.meshes.new("GrassBladeCross")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBladeCross", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Correct outward normals + flat shading: standard low-poly modeling
    # practice. grass_blade.gdshader is unshaded/cull_disabled today (it
    # never reads NORMAL), so this has no visible effect in-game right now --
    # it matters if this .blend is opened to learn from, or if lighting is
    # ever wired into the shader later.
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

    return obj


def setup_scene_units() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def save_blend() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"[generate_grass_blade] wrote {OUTPUT_BLEND}")


def render_preview(obj: bpy.types.Object) -> None:
    """Cheap visual QA: a small render so a human can check the blade shape
    without opening Blender or Godot."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.filepath = str(PREVIEW_PNG)
    scene.render.image_settings.file_format = "PNG"

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = mathutils.Vector((1.4, -1.4, 0.55))
    target = mathutils.Vector((0.0, 0.0, 0.5))
    cam_obj.rotation_euler = (target - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    light_data = bpy.data.lights.new("PreviewSun", type="SUN")
    light_data.energy = 3.0
    light_obj = bpy.data.objects.new("PreviewSun", light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(55), 0.0, math.radians(35))

    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    print(f"[generate_grass_blade] wrote preview {PREVIEW_PNG}")


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene_units()
    obj = build_mesh()
    save_blend()
    render_preview(obj)


if __name__ == "__main__":
    main()
