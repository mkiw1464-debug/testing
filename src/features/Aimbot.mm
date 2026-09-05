#import "Aimbot.h"
#import "../utils/Memory.h"
#import <UIKit/UIKit.h>

AimbotConfig g_Aimbot;

Vector2 WorldToScreen(Vector3 world, float *m) {
    // Column-major projection
    float tx = m[0]*world.x + m[4]*world.y + m[8]*world.z  + m[12];
    float ty = m[1]*world.x + m[5]*world.y + m[9]*world.z  + m[13];
    float tw = m[3]*world.x + m[7]*world.y + m[11]*world.z + m[15];
    if (tw < 0.01f) return {-9999, -9999};
    CGSize sz = UIScreen.mainScreen.bounds.size;
    return { (tx/tw + 1.0f) * sz.width  * 0.5f,
             (1.0f - ty/tw) * sz.height * 0.5f };
}

bool IsInFov(Vector2 screen, float radius) {
    CGSize sz = UIScreen.mainScreen.bounds.size;
    float cx = sz.width  * 0.5f;
    float cy = sz.height * 0.5f;
    float dx = screen.x - cx;
    float dy = screen.y - cy;
    return sqrtf(dx*dx + dy*dy) <= radius;
}

void AimbotTick() {
    if (!g_Aimbot.enabled) return;

    uintptr_t entityList = Read<uintptr_t>(GetOffset(Offsets::EntityList));
    int count = Read<int>(GetOffset(Offsets::EntityListSize));
    float *camMatrix = (float*)GetOffset(Offsets::CameraMatrix);
    uintptr_t local = Read<uintptr_t>(GetOffset(Offsets::LocalPlayer));
    int localTeam = Read<int>(local + Offsets::PlayerTeamID);

    uintptr_t bestEnt = 0;
    float bestDist = FLT_MAX;
    Vector2 bestScreen = {0,0};

    for (int i = 0; i < count; i++) {
        uintptr_t ent = Read<uintptr_t>(entityList + i * 0x8);
        if (!ent || ent == local) continue;

        int team = Read<int>(ent + Offsets::PlayerTeamID);
        if (team == localTeam) continue; // skip teammates

        float hp = Read<float>(ent + Offsets::PlayerHealth);
        if (hp <= 0) continue;

        uintptr_t transform = Read<uintptr_t>(ent + Offsets::PlayerTransform);
        Vector3 bonePos = Read<Vector3>(transform + g_Aimbot.targetBone * 0xC);
        Vector2 screen = WorldToScreen(bonePos, camMatrix);

        if (!IsInFov(screen, g_Aimbot.fov)) continue;

        CGSize sz = UIScreen.mainScreen.bounds.size;
        float cx = sz.width * 0.5f, cy = sz.height * 0.5f;
        float dist = sqrtf((screen.x-cx)*(screen.x-cx)+(screen.y-cy)*(screen.y-cy));

        if (dist < bestDist) {
            bestDist = dist;
            bestEnt = ent;
            bestScreen = screen;
        }
    }

    if (!bestEnt) return;

    if (g_Aimbot.silent) {
        // Silent aim — redirect bullet origin vector
        // Write target bone pos into local player's aim vector
        uintptr_t transform = Read<uintptr_t>(bestEnt + Offsets::PlayerTransform);
        Vector3 targetPos = Read<Vector3>(transform + g_Aimbot.targetBone * 0xC);
        uintptr_t localTransform = Read<uintptr_t>(local + Offsets::PlayerTransform);
        Write<Vector3>(localTransform + 0x50, targetPos); // aim vector offset
    } else {
        // Smooth aimbot — move gyro/aim toward target
        // Uses IOHIDEvent injection (iOS-native, no jailbreak req)
        CGPoint target = CGPointMake(bestScreen.x, bestScreen.y);
        // Simulate touch move — approaches target in steps
        CGSize sz = UIScreen.mainScreen.bounds.size;
        CGPoint center = CGPointMake(sz.width*0.5f, sz.height*0.5f);
        float lerpX = center.x + (target.x - center.x) * 0.4f;
        float lerpY = center.y + (target.y - center.y) * 0.4f;
        // Inject via private API UIApplication sendEvent (gyro layer)
        // Actual injection handled in Menu.mm update loop
    }
}
