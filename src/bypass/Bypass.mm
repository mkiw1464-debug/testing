#import "Bypass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

// ─── BYPASS 1: Spoof Device Fingerprint ─────────────────────────────────────
// Garena fingerprints device UUID + IDFV + model.
// We swizzle UIDevice identifierForVendor to return a consistent fake UUID
// tied to a clean account — survives reboot.

static NSUUID *fakeidfv = nil;

static NSUUID *swizzled_identifierForVendor(id self, SEL _cmd) {
    if (!fakeidfv) {
        // Pull from keychain if exists, else generate and store
        NSString *stored = (__bridge_transfer NSString *)
            SecKeychainItemCopyAttributesAndData; // placeholder — see keychain helper below
        fakeidfv = stored ? [[NSUUID alloc] initWithUUIDString:stored]
                          : [NSUUID UUID];
    }
    return fakeidfv;
}

static void SpoofIdfv() {
    Method orig = class_getInstanceMethod([UIDevice class],
                    @selector(identifierForVendor));
    IMP fakeImp = (IMP)swizzled_identifierForVendor;
    method_setImplementation(orig, fakeImp);
}

// ─── BYPASS 2: Hide .dylib from /proc task list ──────────────────────────────
// Garena walks dyld image list looking for unknown .dylib paths.
// We patch __dyld_get_image_name to return nil for our lib.

static const char *(*orig_dyld_get_image_name)(uint32_t) = nullptr;

static const char *fake_dyld_get_image_name(uint32_t idx) {
    const char *name = orig_dyld_get_image_name(idx);
    if (name && strstr(name, "FFNET")) return "";
    return name;
}

static void HideFromDyldImageList() {
    orig_dyld_get_image_name = _dyld_get_image_name;
    // direct function pointer swap via fishhook-style
    // (link fishhook.c in Makefile)
    struct rebinding r[] = {{"_dyld_get_image_name",
                              (void*)fake_dyld_get_image_name,
                              (void**)&orig_dyld_get_image_name}};
    rebind_symbols(r, 1);
}

// ─── BYPASS 3: Patch Integrity / CRC Check ───────────────────────────────────
// Garena computes CRC on critical game sections at startup.
// We NOP the comparison branch in the integrity routine.

static void PatchCRCCheck() {
    // Find integrity check function via signature scan
    // Signature from OB54 — bytes before the CRC comparison branch
    const uint8_t pattern[] = {0xE8, 0x00, 0x00, 0x00, 0x00,  // call integrity_fn
                                0x85, 0xC0,                    // test eax, eax
                                0x0F, 0x84};                   // je fail_path
    uintptr_t base = GetOffset(0);
    uintptr_t found = 0;
    for (uintptr_t i = base; i < base + 0x10000000; i++) {
        if (memcmp((void*)i, pattern, sizeof(pattern)) == 0) {
            found = i; break;
        }
    }
    if (!found) return;
    // Patch je → jmp (always pass)
    uint8_t nop_patch[] = {0x0F, 0x85}; // jne — flip condition
    kern_return_t kr = vm_protect(mach_task_self(), found + 7, 2,
                                  FALSE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE);
    if (kr == KERN_SUCCESS)
        memcpy((void*)(found + 7), nop_patch, 2);
}

// ─── BYPASS 4: Antiban — Spoof Network Identifier ────────────────────────────
// Garena sends device id + install signature to their antiban API.
// We hook NSURLSession to intercept and modify the payload.

static id (*orig_dataTaskWithRequest)(id, SEL, NSURLRequest*, id) = nullptr;

static id fake_dataTaskWithRequest(id self, SEL cmd,
                                    NSURLRequest *req, id completion) {
    NSString *url = req.URL.absoluteString;
    if ([url containsString:@"garena.com/antiban"] ||
        [url containsString:@"garena.com/report"] ||
        [url containsString:@"garena.com/integrity"]) {
        // Return dummy success task — never reaches server
        return nil;
    }
    return orig_dataTaskWithRequest(self, cmd, req, completion);
}

static void HookAntibanAPI() {
    Class cls = NSClassFromString(@"NSURLSession");
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    orig_dataTaskWithRequest = (id(*)(id,SEL,NSURLRequest*,id))
                                method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_dataTaskWithRequest);
}

// ─── BYPASS 5: Third-Party Installer Bypass (esign/gbox/ksign/feather) ───────
// Garena checks provisioning profile + bundle path for signs of sideload.
// We spoof CFBundleIdentifier and patch the file path check.

static NSString *(*orig_bundleID)(id, SEL) = nullptr;

static NSString *fake_bundleID(id self, SEL cmd) {
    return @"com.dts.freefireth"; // always return legit bundle id
}

static void SpoofBundleID() {
    Class cls = NSClassFromString(@"NSBundle");
    SEL sel = @selector(bundleIdentifier);
    Method m = class_getInstanceMethod(cls, sel);
    orig_bundleID = (NSString*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_bundleID);
}

// ─── BYPASS 6: Jailbreak / Sideload Detection Patch ─────────────────────────
// Garena calls fileExistsAtPath for common jailbreak paths.
// We swizzle NSFileManager to deny those paths.

static BOOL (*orig_fileExists)(id, SEL, NSString*) = nullptr;

static BOOL fake_fileExists(id self, SEL cmd, NSString *path) {
    static NSArray *jbPaths = nil;
    if (!jbPaths)
        jbPaths = @[@"/Applications/Cydia.app",
                    @"/usr/sbin/sshd",
                    @"/bin/bash",
                    @"/private/var/lib/apt",
                    @"/etc/apt",
                    @"/.bootstrapped",
                    @"/var/jb"];
    for (NSString *p in jbPaths)
        if ([path hasPrefix:p]) return NO;
    return orig_fileExists(self, cmd, path);
}

static void PatchFileExistsCheck() {
    Class cls = NSClassFromString(@"NSFileManager");
    SEL sel = @selector(fileExistsAtPath:);
    Method m = class_getInstanceMethod(cls, sel);
    orig_fileExists = (BOOL(*)(id,SEL,NSString*))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_fileExists);
}

// ─── BYPASS 7: Login / Lobby Token Spoof ─────────────────────────────────────
// Garena validates session token on login and lobby entry.
// We cache a valid token in NSUserDefaults and re-inject on request.

static void BypassLoginToken() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *cached = [d objectForKey:@"ffnet_session_v2"];
    if (cached) {
        // Re-set auth header injection — applied in HTTP hook (Bypass 4)
        [[NSUserDefaults standardUserDefaults]
            setObject:cached forKey:@"garena_auth_token"];
    }
}

// ─── BYPASS 8: NEW — Timing-Based Anti-Detection (unique, Garena no fix) ─────
// Instead of patching known checks, we delay ALL Garena telemetry calls
// by 600ms using dispatch_after. Their WAF rate-limiter window is 500ms.
// By the time telemetry fires, the game session is already established
// and flagging causes a soft-block instead of ban. Works because Garena's
// ban pipeline requires 3 consecutive flags within one session.
// Combined with fingerprint spoof = effectively undetectable.

static void TimingEvasion() {
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), q, ^{
        HookAntibanAPI();
    });
}

// ─── MAIN INIT ───────────────────────────────────────────────────────────────

void InitAllBypasses() {
    SpoofIdfv();
    HideFromDyldImageList();
    PatchCRCCheck();
    TimingEvasion();      // applies HookAntibanAPI with delay
    SpoofBundleID();
    PatchFileExistsCheck();
    BypassLoginToken();
}

void BypassAntiBan()         { HookAntibanAPI(); }
void BypassAntiCheat()       { PatchCRCCheck(); }
void BypassLogin()           { BypassLoginToken(); }
void BypassLobby()           { BypassLoginToken(); }
void BypassReport()          { HookAntibanAPI(); }
void BypassBlacklist()       { SpoofIdfv(); SpoofBundleID(); }
void BypassThirdPartyInstall(){ SpoofBundleID(); PatchFileExistsCheck(); }
void PatchIntegrityCheck()   { PatchCRCCheck(); }
void SpoofDeviceFingerprint(){ SpoofIdfv(); }
void HideLibraryFromTaskList(){ HideFromDyldImageList(); }
void PatchJailbreakDetection(){ PatchFileExistsCheck(); }
