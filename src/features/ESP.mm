#import "ESP.h"
#import "../utils/Memory.h"
#import <UIKit/UIKit.h>

ESPConfig g_ESP;

static ESPEntry entries[100];
static int entryCount = 0;

void ESPCollect() {
    if (!g_ESP.enabled) { entryCount = 0; return; }

    uintptr_t entityList = Read<uintptr_t>(GetOffset(Offsets::EntityList));
    int count = Read<int>(GetOffset(Offsets::EntityListSize));
    float *cam = (float*)GetOffset(Offsets::CameraMatrix);
    uintptr_t local = Read<uintptr_t>(GetOffset(Offsets::LocalPlayer));
    int localTeam = Read<int>(local + Offsets::PlayerTeamID);
    entryCount = 0;

    for (int i = 0; i < count && entryCount < 100; i++) {
        uintptr_t ent = Read<uintptr_t>(entityList + i * 0x8);
        if (!ent || ent == local) continue;
        int team = Read<int>(ent + Offsets::PlayerTeamID);
        if (team == localTeam) continue; // no teammate esp
        float hp = Read<float>(ent + Offsets::PlayerHealth);
        if (hp <= 0) continue;

        uintptr_t transform = Read<uintptr_t>(ent + Offsets::PlayerTransform);
        Vector3 headPos = Read<Vector3>(transform + Offsets::PlayerBoneHead * 0xC);
        Vector3 footPos = headPos; footPos.y -= 1.75f; // approx foot

        ESPEntry &e = entries[entryCount];
        e.screenPos  = WorldToScreen(headPos, cam);
        e.screenFoot = WorldToScreen(footPos, cam);
        e.health = hp;
        uintptr_t namePtr = Read<uintptr_t>(ent + Offsets::PlayerName);
        if (namePtr) {
            char *rawName = (char*)(namePtr + 0x10);
            strncpy(e.name, rawName, 63);
        } else {
            strcpy(e.name, "Player");
        }
        e.valid = (e.screenPos.x > 0 && e.screenPos.x < 9000);
        if (e.valid) entryCount++;
    }
}

void ESPRender(CGContextRef ctx) {
    if (!g_ESP.enabled || entryCount == 0) return;
    CGContextSaveGState(ctx);

    // Enemy counter at top
    CGContextSetRGBFillColor(ctx, 1, 0.2, 0.2, 1);
    NSString *counter = [NSString stringWithFormat:@"Enemies: %d", entryCount];
    [counter drawAtPoint:CGPointMake(20, 40)
           withAttributes:@{NSFontAttributeName:
               [UIFont boldSystemFontOfSize:14],
               NSForegroundColorAttributeName: [UIColor redColor]}];

    for (int i = 0; i < entryCount; i++) {
        ESPEntry &e = entries[i];
        if (!e.valid) continue;
        float x = e.screenPos.x, y = e.screenPos.y;
        float fx = e.screenFoot.x, fy = e.screenFoot.y;
        float h = fy - y;
        float w = h * 0.4f;

        // Box
        if (g_ESP.showBox) {
            CGContextSetRGBStrokeColor(ctx, 1, 0, 0, 0.9);
            CGContextSetLineWidth(ctx, 1.5);
            CGContextStrokeRect(ctx, CGRectMake(x-w*0.5, y, w, h));
        }
        // Name
        if (g_ESP.showName) {
            NSString *nm = [NSString stringWithUTF8String:e.name];
            [nm drawAtPoint:CGPointMake(x, y-16)
               withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11],
                                NSForegroundColorAttributeName:[UIColor whiteColor]}];
        }
        // HP bar
        if (g_ESP.showHP) {
            float pct = e.health / 200.0f;
            CGContextSetRGBFillColor(ctx, 0.2, 0.8, 0.2, 0.85);
            CGContextFillRect(ctx, CGRectMake(x-w*0.5-6, y, 4, h));
            CGContextSetRGBFillColor(ctx, 0.8, 0.2, 0.2, 0.85);
            CGContextFillRect(ctx, CGRectMake(x-w*0.5-6, y + h*(1-pct), 4, h*pct));
        }
        // Line
        if (g_ESP.showLine) {
            CGSize sz = UIScreen.mainScreen.bounds.size;
            CGContextSetRGBStrokeColor(ctx, 1, 1, 0, 0.7);
            CGContextSetLineWidth(ctx, 1);
            CGContextMoveToPoint(ctx, sz.width*0.5, sz.height);
            CGContextAddLineToPoint(ctx, fx, fy);
            CGContextStrokePath(ctx);
        }
    }
    CGContextRestoreGState(ctx);
}
