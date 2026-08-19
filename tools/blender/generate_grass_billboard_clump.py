"""Generates the classic textured-billboard grass clump
(art/blender/grass/grass_billboard_clump.blend), replacing the procedural
LOD0/LOD1/LOD2 system with the 6 techniques from Kammerbild's "6 simple
tips to improve grass billboards in CGI" (docs/pasto_godot.md, pivot
session). Base-fade is a shader concern (UV.y-driven), not baked here.

Run headless from the repo root:
  blender --background --factory-startup --python tools/blender/generate_grass_billboard_clump.py

Requires grass_card_atlas.png to already exist (run
render_grass_card_alpha.py first) -- this script only builds geometry/UVs,
it doesn't render the texture itself.

4 cards, each 2 EXPLICIT triangle faces (not one quad face) sharing the
bottom-left/top-right diagonal -- same triangle budget as a quad (always 2
tris on the GPU anyway), but 1-2 corners of each card are nudged off their
flat rectangle position, bending a triangle relative to the other and
giving each card a slight curve instead of reading as a perfectly rigid
flat plane.

CARD_TRANSFORMS is HAND-AUTHORED, not procedural, and not decomposed into
a formula (half_width/height_scale/tl_offset, etc.) -- it's the literal
per-card object transform (location, rotation, non-uniform scale) and the
4 raw local vertex positions, read back byte-for-byte from the user's
hand-tuned art/blender/grass/grass_clump_tuning.blend. Earlier sessions
(docs/pasto_godot.md, decimotercera/decimocuarta/decimoquinta sesiones)
tried a shared-axis asterisk, then a single tl_offset, then a global
CARD_WIDTH_SCALE/CARD_HEIGHT_SCALE multiplier to fix cards that felt too
tall/narrow in Godot -- all superseded once the user tuned each card's
scale non-uniformly (different X/Y/Z factors) and per-vertex by hand,
which is both more precise and does not need a decomposition formula to
reproduce: storing the raw vertices is simpler AND more general, since it
survives edits that move more than one corner (see decimosexta sesion).
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grass_blade_common import (
    BLADE_COLOR,
    GRASS_DIR,
    finish_object,
    render_preview,
    save_blend,
    setup_scene_units,
)

NAME = "grass_billboard_clump"
ATLAS_COLUMNS = 3

# One entry per card, read back from the user's hand-tuned
# art/blender/grass/grass_clump_tuning.blend (docs/pasto_godot.md,
# decimosexta sesion):
#   location: (x, y) root offset, world units.
#   tilt_deg / yaw_deg: object rotation, applied Z-then-X (matches
#     Blender's own XYZ-order Euler with rotation.y always 0).
#   scale: (x, y, z) object scale -- NON-uniform, one factor per axis
#     (this is what makes each card independently wider/shorter, not a
#     single shared multiplier).
#   verts: the 4 raw local mesh vertex coordinates, in the order Blender
#     stores them (bottom-left, bottom-right, top-right, top-left), exactly
#     as authored -- a flat rectangle would have all 4 corners exactly on
#     (+-half_width, 0, base_h/tip_h); any deviation is the user's
#     hand-authored fold/curve, on whichever corner(s) they moved.
CARD_TRANSFORMS = (
    dict(
        location=(0.0, 0.0),
        tilt_deg=10.0,
        yaw_deg=0.0,
        scale=(1.358340859413147, 0.9484071135520935, 0.6102825999259949),
        verts=(
            (-0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, -0.05999999865889549),
            (0.40625157952308655, 0.06784491240978241, 1.0017672777175903),
            (-0.4171246290206909, -0.1660708785057068, 0.9722384810447693),
        ),
    ),
    dict(
        location=(0.09339403361082077, -0.0914069190621376),
        tilt_deg=-10.0,
        yaw_deg=45.0,
        scale=(1.2050080299377441, 1.1930935382843018, 0.8215733170509338),
        verts=(
            (-0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, 1.0),
            (-0.430237352848053, 0.10118743777275085, 0.9888525605201721),
        ),
    ),
    dict(
        location=(-0.09538114070892334, 0.007948427461087704),
        tilt_deg=0.0,
        yaw_deg=90.0,
        scale=(1.149999976158142, 1.149999976158142, 0.9298169612884521),
        verts=(
            (-0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, 1.0),
            (-0.4583500623703003, -0.14204277098178864, 1.0454010963439941),
        ),
    ),
    dict(
        location=(0.0, 0.0),
        tilt_deg=-5.0,
        yaw_deg=135.0,
        scale=(1.299999713897705, 1.2900344133377075, 0.9794642925262451),
        verts=(
            (-0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, -0.05999999865889549),
            (0.4227619171142578, 0.0, 1.0),
            (-0.3893549144268036, 0.14367254078388214, 1.0203475952148438),
        ),
    ),
)


def apply_preview_card_material(mesh: bpy.types.Mesh) -> None:
    material = mesh.materials[0]
    material.use_nodes = True
    nodes = material.node_tree.nodes
    principled = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(GRASS_DIR / "grass_card_atlas.png"), check_existing=True)
    principled.inputs["Base Color"].default_value = BLADE_COLOR
    material.node_tree.links.new(texture.outputs["Alpha"], principled.inputs["Alpha"])
    material.surface_render_method = "DITHERED"


def _place_hand_tuned_card(bm: bmesh.types.BMesh, transform: dict, uv_column: int, uv_columns_total: int) -> None:
    scale = mathutils.Vector(transform["scale"])
    rotation = mathutils.Matrix.Rotation(math.radians(transform["yaw_deg"]), 4, "Z") @ mathutils.Matrix.Rotation(
        math.radians(transform["tilt_deg"]), 4, "X"
    )
    location = mathutils.Vector((transform["location"][0], transform["location"][1], 0.0))

    def to_world(local: mathutils.Vector) -> mathutils.Vector:
        scaled = mathutils.Vector((local.x * scale.x, local.y * scale.y, local.z * scale.z))
        return rotation @ scaled + location

    bl = bm.verts.new(to_world(mathutils.Vector(transform["verts"][0])))
    br = bm.verts.new(to_world(mathutils.Vector(transform["verts"][1])))
    tr = bm.verts.new(to_world(mathutils.Vector(transform["verts"][2])))
    tl = bm.verts.new(to_world(mathutils.Vector(transform["verts"][3])))
    f1 = bm.faces.new((bl, br, tr))
    f2 = bm.faces.new((bl, tr, tl))

    uv_layer = bm.loops.layers.uv.verify()
    u0 = uv_column / uv_columns_total
    u1 = (uv_column + 1) / uv_columns_total
    uv_by_vert = {bl: (u0, 0.0), br: (u1, 0.0), tr: (u1, 1.0), tl: (u0, 1.0)}
    for face in (f1, f2):
        for loop in face.loops:
            loop[uv_layer].uv = uv_by_vert[loop.vert]


def build_mesh() -> bpy.types.Object:
    bm = bmesh.new()
    for i, transform in enumerate(CARD_TRANSFORMS):
        _place_hand_tuned_card(bm, transform, uv_column=i % ATLAS_COLUMNS, uv_columns_total=ATLAS_COLUMNS)

    mesh = bpy.data.meshes.new("GrassBillboardClumpMesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new("GrassBillboardClump", mesh)
    finish_object(obj, mesh)
    apply_preview_card_material(mesh)
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
