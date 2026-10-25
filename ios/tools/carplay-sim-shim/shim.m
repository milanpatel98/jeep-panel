// Simulator-only workaround for an Apple bug in the iOS 26.4/26.5 simulator's CarPlaySupport:
// CarPlayTemplateUIHost crashes with "unrecognized selector" in
// -[CPSMapTemplateViewController _updateShareButtonVisibility] whenever any app shows a
// CPMapTemplate, because CPSTemplateInstance lacks two destination-sharing methods there.
// Real iPhones and cars are not affected. This dylib is injected only into the simulator's
// CarPlay host (see install.sh); it is never part of the Forx app.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL forxNoDestinationSharing(id self, SEL _cmd) { return NO; }
static void forxIgnoreSharedDestination(id self, SEL _cmd, id destination, id completion) {}

__attribute__((constructor)) static void forxCarPlaySimShim(void) {
    Class cls = NSClassFromString(@"CPSTemplateInstance");
    if (!cls) return;
    int added = 0;
    SEL supports = NSSelectorFromString(@"vehicleSupportsDestinationSharing");
    if (!class_getInstanceMethod(cls, supports)) {
        class_addMethod(cls, supports, (IMP)forxNoDestinationSharing, "c@:");
        added++;
    }
    SEL handle = NSSelectorFromString(@"handleSharedDestination:completion:");
    if (!class_getInstanceMethod(cls, handle)) {
        class_addMethod(cls, handle, (IMP)forxIgnoreSharedDestination, "v@:@@");
        added++;
    }
    NSLog(@"forx-carplay-sim-shim: patched CPSTemplateInstance, %d methods added", added);
}
