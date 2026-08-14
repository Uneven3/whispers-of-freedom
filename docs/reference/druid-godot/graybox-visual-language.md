# Graybox Visual Language

## Mode
3D

## Entities

| Entity | Node Type | Mesh/Shape | Color (hex) | Notes |
|--------|-----------|------------|-------------|-------|
| Player | `MeshInstance3D` | `CapsuleMesh` | `#4488FF` | Features a small `BoxMesh` "nose" to indicate forward facing direction. |
| Enemy/Target | `MeshInstance3D` | `SphereMesh` | `#FF4422` | Represents combat lock-on targets. |
| Terrain/Floor | `MeshInstance3D` | `BoxMesh` | `#555555` | Default ground. |
| Ledges/Stairs | `MeshInstance3D` | `BoxMesh` | `#888888` | Highlights climbable or vaultable geometry. |
| Interactable | `MeshInstance3D` | `CylinderMesh` | `#FFDD00` | Placeholder for future interaction points. |

## Camera
- **Type:** `Camera3D` attached to a `SpringArm3D`
- **View:** Third-Person Orbital
- **Follows player:** Yes, attached to `CameraRig` reading `Body` location.
- **Initial position:** Offset `[0, 1.5, 4.0]` behind the player.

## Scale Reference
- 1 unit = 1 meter
- Player height: 2.0 units
- Player radius: 0.5 units
- Max step height: 0.3 units
