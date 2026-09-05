#import <Foundation/Foundation.h>
#import "bypass/Bypass.h"
#import "bypass/AntiDebug.h"
#import "features/Aimbot.h"
#import "features/ESP.h"
#import "ui/Menu.h"

// Game loop hook — runs every frame
static void GameTick() {
    ESPCollect();
    AimbotTick();
    if (drawView) [drawView setNeedsDisplay];
}

__attribute__((constructor))
static void Initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        InitAntiDebug();
        InitAllBypasses();
        InitMenu();

        // Hook Unity game update cycle
        // CADisplayLink — fires every frame
        CADisplayLink *link = [CADisplayLink
            displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{
                GameTick();
            }] selector:@selector(main)];
        [link addToRunLoop:[NSRunLoop mainRunLoop]
                  forMode:NSRunLoopCommonModes];
    });
}
