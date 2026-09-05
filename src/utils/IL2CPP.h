#pragma once
#include <stdint.h>
#include <string>
#include "Memory.h"

// Free Fire OB54 — key offsets from dump.cs
// PlayerEntity / health / transform from Assembly-CSharp.dll
namespace Offsets {
    // World → PlayerManager
    constexpr uintptr_t GameController      = 0x1530144; // BornPosSetting::Awake RVA approx
    constexpr uintptr_t PlayerHealth        = 0x118;  // typical FF health offset OB54
    constexpr uintptr_t PlayerTransform     = 0x30;
    constexpr uintptr_t PlayerName          = 0x60;
    constexpr uintptr_t PlayerTeamID        = 0x148;
    constexpr uintptr_t PlayerBoneHead      = 0x0;
    constexpr uintptr_t PlayerBoneNeck      = 0x1;
    constexpr uintptr_t PlayerBoneBody      = 0x6;
    constexpr uintptr_t PlayerBoneLeg       = 0x13;
    constexpr uintptr_t LocalPlayer         = 0x200;
    constexpr uintptr_t EntityList          = 0x250;
    constexpr uintptr_t EntityListSize      = 0x258;
    constexpr uintptr_t CameraMatrix        = 0x300;
}

struct Vector3 {
    float x, y, z;
    Vector3 operator-(const Vector3& o) const { return {x-o.x, y-o.y, z-o.z}; }
    float length() const { return sqrtf(x*x + y*y + z*z); }
};

struct Vector2 {
    float x, y;
};
