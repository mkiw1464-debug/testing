#import "Menu.h"
#import "../features/Aimbot.h"
#import "../features/ESP.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// ─── Streamproof ─────────────────────────────────────────────────────────────
static bool g_Streamproof = false;
static bool g_SaveConfig  = false;

// ─── Tab state ───────────────────────────────────────────────────────────────
static int currentPage = 0; // 0=Aimbot, 1=ESP, 2=Settings

// ─── Tap counter ─────────────────────────────────────────────────────────────
static int tapCount = 0;
static NSTimeInterval lastTap = 0;

static UIWindow    *menuWindow   = nil;
static UIView      *menuView     = nil;
static bool         menuVisible  = false;

// ─── Overlay window for ESP draw ─────────────────────────────────────────────
@interface FFDrawView : UIView @end
@implementation FFDrawView
- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    ESPRender(ctx);
    if (g_Aimbot.showFov) {
        // Draw FOV circle
        CGSize sz = self.bounds.size;
        CGContextSetRGBStrokeColor(ctx, 1,1,1,0.6);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextAddEllipseInRect(ctx,
            CGRectMake(sz.width*0.5 - g_Aimbot.fov,
                       sz.height*0.5 - g_Aimbot.fov,
                       g_Aimbot.fov*2, g_Aimbot.fov*2));
        CGContextStrokePath(ctx);
    }
}
@end

static FFDrawView *drawView = nil;

// ─── Toggle helper ───────────────────────────────────────────────────────────
static UISwitch *MakeToggle(CGRect f, SEL action, id target, bool on) {
    UISwitch *s = [[UISwitch alloc] initWithFrame:f];
    s.on = on;
    s.onTintColor = [UIColor colorWithRed:0.4 green:0.4 blue:1.0 alpha:1];
    [s addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

// ─── Page builders ───────────────────────────────────────────────────────────
@interface FFMenu : NSObject
+ (UIView*)buildAimbotPage:(CGRect)bounds;
+ (UIView*)buildESPPage:(CGRect)bounds;
+ (UIView*)buildSettingsPage:(CGRect)bounds;
@end

@implementation FFMenu

+ (UIView*)buildAimbotPage:(CGRect)b {
    UIView *v = [[UIView alloc] initWithFrame:b];
    UILabel *lbl;
    float y = 10;

    auto addLabel = [&](NSString *text) {
        lbl = [[UILabel alloc] initWithFrame:CGRectMake(12,y,200,22)];
        lbl.text = text; lbl.textColor = UIColor.whiteColor;
        lbl.font = [UIFont systemFontOfSize:13]; [v addSubview:lbl]; y+=24;
    };

    // Aimbot ON/OFF
    addLabel(@"Aimbot");
    [v addSubview:MakeToggle(CGRectMake(b.size.width-60,y-24,51,31),
        @selector(toggleAimbot:), [UIApplication sharedApplication].delegate, g_Aimbot.enabled)];

    // Target bone selector
    addLabel(@"Target Bone");
    NSArray *bones = @[@"Head", @"Neck", @"Body", @"Leg"];
    UISegmentedControl *seg = [[UISegmentedControl alloc]
        initWithItems:bones];
    seg.frame = CGRectMake(12, y, b.size.width-24, 28);
    seg.selectedSegmentIndex = 0;
    seg.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    [v addSubview:seg]; y += 36;

    // FOV slider
    addLabel([NSString stringWithFormat:@"AimFov: %.0f", g_Aimbot.fov]);
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(12, y, b.size.width-24, 28)];
    sl.minimumValue = 0; sl.maximumValue = 200;
    sl.value = g_Aimbot.fov;
    sl.minimumTrackTintColor = [UIColor colorWithRed:0.5 green:0.5 blue:1 alpha:1];
    [v addSubview:sl]; y+=36;

    // Show FOV visual
    addLabel(@"Show FOV Visual");
    [v addSubview:MakeToggle(CGRectMake(b.size.width-60,y-24,51,31),
        @selector(toggleFovVisual:), [UIApplication sharedApplication].delegate, g_Aimbot.showFov)];

    // Aim Silent
    addLabel(@"Aim Silent");
    [v addSubview:MakeToggle(CGRectMake(b.size.width-60,y-24,51,31),
        @selector(toggleSilent:), [UIApplication sharedApplication].delegate, g_Aimbot.silent)];

    return v;
}

+ (UIView*)buildESPPage:(CGRect)b {
    UIView *v = [[UIView alloc] initWithFrame:b];
    float y = 10;
    NSArray *labels  = @[@"ESP", @"Esp Name", @"Esp Box", @"Esp Line", @"Health Bar"];
    NSArray *selects = @[@"toggleESP:", @"toggleESPName:", @"toggleESPBox:", @"toggleESPLine:", @"toggleESPHP:"];
    NSArray *states  = @[@(g_ESP.enabled),@(g_ESP.showName),@(g_ESP.showBox),@(g_ESP.showLine),@(g_ESP.showHP)];
    id app = [UIApplication sharedApplication].delegate;
    for (int i = 0; i < labels.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12,y+6,200,22)];
        l.text = labels[i]; l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:13]; [v addSubview:l];
        [v addSubview:MakeToggle(CGRectMake(b.size.width-60,y,51,31),
            NSSelectorFromString(selects[i]), app, [states[i] boolValue])];
        y += 44;
    }
    return v;
}

+ (UIView*)buildSettingsPage:(CGRect)b {
    UIView *v = [[UIView alloc] initWithFrame:b];
    float y = 10;
    NSArray *labels  = @[@"Streamproof", @"Save Config"];
    NSArray *selects = @[@"toggleStreamproof:", @"toggleSaveConfig:"];
    NSArray *states  = @[@(g_Streamproof), @(g_SaveConfig)];
    id app = [UIApplication sharedApplication].delegate;
    for (int i = 0; i < labels.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12,y+6,200,22)];
        l.text = labels[i]; l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:13]; [v addSubview:l];
        [v addSubview:MakeToggle(CGRectMake(b.size.width-60,y,51,31),
            NSSelectorFromString(selects[i]), app, [states[i] boolValue])];
        y += 44;
    }
    // Version label
    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(12, b.size.height-28, 200, 22)];
    ver.text = @"FFNET iOS V1.0.0 Beta"; ver.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    ver.font = [UIFont systemFontOfSize:11]; [v addSubview:ver];
    return v;
}

@end

// ─── Build full menu window ───────────────────────────────────────────────────

void BuildMenu() {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat mw = 300, mh = 380;
    CGFloat mx = (screen.width - mw) * 0.5;
    CGFloat my = (screen.height - mh) * 0.5;

    menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    menuWindow.windowLevel = UIWindowLevelStatusBar + 200;
    menuWindow.backgroundColor = UIColor.clearColor;
    menuWindow.hidden = NO;

    menuView = [[UIView alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
    menuView.layer.cornerRadius = 18;
    menuView.clipsToBounds = YES;
    menuView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    menuView.layer.borderWidth = 1;

    // Glassmorphism blur
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc]
        initWithEffect:blur];
    blurView.frame = menuView.bounds;
    [menuView addSubview:blurView];

    // Grey tint overlay
    UIView *tint = [[UIView alloc] initWithFrame:menuView.bounds];
    tint.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.35];
    [menuView addSubview:tint];

    // Title bar
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,44)];
    titleBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.6];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14,10,mw-60,24)];
    title.text = @"FFNET iOS • V1.0.0 Beta";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:14];
    [titleBar addSubview:title];

    // X button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(mw-40, 8, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [closeBtn addTarget:nil action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:closeBtn];
    [menuView addSubview:titleBar];

    // Tab bar
    NSArray *tabs = @[@"Aimbot", @"ESP", @"Settings"];
    UISegmentedControl *tabBar = [[UISegmentedControl alloc] initWithItems:tabs];
    tabBar.frame = CGRectMake(10, 50, mw-20, 30);
    tabBar.selectedSegmentIndex = 0;
    tabBar.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
    UIColor *tabTint = [UIColor colorWithRed:0.5 green:0.5 blue:1 alpha:0.9];
    tabBar.selectedSegmentTintColor = tabTint;
    [tabBar addTarget:nil action:@selector(switchPage:)
        forControlEvents:UIControlEventValueChanged];
    [menuView addSubview:tabBar];

    // Content area
    CGRect contentRect = CGRectMake(0, 88, mw, mh-88);
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:contentRect];
    scroll.tag = 999;
    UIView *page = [FFMenu buildAimbotPage:CGRectMake(0,0,mw,mh-88)];
    [scroll addSubview:page];
    scroll.contentSize = CGSizeMake(mw, mh-88);
    [menuView addSubview:scroll];

    [menuWindow addSubview:menuView];
    menuWindow.hidden = YES;
}

void ToggleMenu() {
    menuVisible = !menuVisible;
    menuWindow.hidden = !menuVisible;
    if (g_Streamproof) {
        menuWindow.layer.allowsGroupOpacity = NO;
        // Mark as secure — won't appear in ReplayKit / screen capture
        UITextField *sec = [[UITextField alloc] initWithFrame:CGRectZero];
        sec.secureTextEntry = YES;
        [menuView addSubview:sec]; [sec becomeFirstResponder]; [sec resignFirstResponder];
        [sec removeFromSuperview];
    }
}

// ─── 3-tap trigger ────────────────────────────────────────────────────────────

void HandleTap() {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastTap > 1.0) tapCount = 0;
    lastTap = now;
    if (++tapCount >= 3) {
        tapCount = 0;
        ToggleMenu();
    }
}

void InitMenu() {
    BuildMenu();
    // Tap gesture on root window
    dispatch_async(dispatch_get_main_queue(), ^{
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:nil action:@selector(handleTap)];
        tap.numberOfTapsRequired = 3;
        [[UIApplication sharedApplication].keyWindow addGestureRecognizer:tap];

        // ESP overlay
        drawView = [[FFDrawView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        drawView.backgroundColor = UIColor.clearColor;
        drawView.userInteractionEnabled = NO;
        [[UIApplication sharedApplication].keyWindow addSubview:drawView];
    });
}
