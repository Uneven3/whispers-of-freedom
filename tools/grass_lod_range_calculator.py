"""Computes candidate LOD switch distances for grass_terrain_instancer.gd
from the actual camera FOV and blade width, instead of guessing meters
from memory (docs/pasto_godot.md, Decision 7: distances get measured, not
copied from another project or picked by feel alone).

This is the theoretical half of the "herramienta de ancho-en-pantalla" that
Fase 4 of docs/pasto_godot.md called for -- it narrows down candidate
distances from geometry + camera math. It does NOT replace playing the
result: perceptual judgment of "does this LOD switch read as natural" is
still a call only a human eye makes, moving through the scene, per this
project's own established lesson (docs/AHORA.md: "un screenshot estático
puede mentir sobre geometría real"). Treat the numbers below as a starting
point to plug into grass_terrain_instancer.gd's lod0_range/lod1_range/
lod2_range exports (already live-tunable) and validate by walking around,
not as a final answer.

Run: python3 tools/grass_lod_range_calculator.py
"""

import math

# tools/blender/grass_blade_common.py::HALF_WIDTH * 2
BLADE_WIDTH_M = 0.08

# scripts/player_action_stack/camera/camera_rig.gd
FOV_FOLLOW_DEG = 75.0
FOV_AIM_DEG = 56.0

# Common reference resolution -- the actual number only matters through the
# ratio screen_height_px / tan(fov/2), so results barely change across
# common heights (720/1080/1440); pick whichever matches how the game is
# actually played most, adjust and re-run if that changes.
SCREEN_HEIGHT_PX = 1080

# Candidate switch thresholds, apparent blade width in pixels at the
# distance where the NEXT (cheaper) LOD takes over. Lower = switches later
# (closer), keeping detail longer at higher cost. These are starting
# guesses to validate by eye, not physical constants -- the antecedent
# project referenced in docs/pasto_godot.md used ~1.5px for its one
# leaf-to-card jump; we have two jumps (LOD0->LOD1, LOD1->LOD2) so a small
# spread of candidates is more useful than a single number.
CANDIDATE_THRESHOLDS_PX = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0]


def switch_distance_m(pixel_threshold: float, fov_deg: float, screen_height_px: int) -> float:
    """Distance at which a BLADE_WIDTH_M-wide object subtends exactly
    pixel_threshold pixels of vertical screen height, given a vertical FOV
    (Godot's Camera3D.fov in KEEP_HEIGHT mode, the project's default).

    Derivation: at distance D, the visible world height spans
    2 * D * tan(fov/2) meters across screen_height_px pixels, so
    pixels-per-meter = screen_height_px / (2 * D * tan(fov/2)). Solve
    pixel_threshold = BLADE_WIDTH_M * pixels-per-meter for D.
    """
    half_fov_rad = math.radians(fov_deg) / 2.0
    return (BLADE_WIDTH_M * screen_height_px) / (2.0 * pixel_threshold * math.tan(half_fov_rad))


def main() -> None:
    for label, fov in (("follow (75°)", FOV_FOLLOW_DEG), ("aim (56°)", FOV_AIM_DEG)):
        print(f"\n=== FOV {label}, blade width {BLADE_WIDTH_M}m, {SCREEN_HEIGHT_PX}px screen height ===")
        print(f"{'px threshold':>12} | {'switch distance (m)':>20}")
        for px in CANDIDATE_THRESHOLDS_PX:
            d = switch_distance_m(px, fov, SCREEN_HEIGHT_PX)
            print(f"{px:>12.1f} | {d:>20.1f}")


if __name__ == "__main__":
    main()
