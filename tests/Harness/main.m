#import "NGHarness.h"
#import <TargetConditionals.h>

@interface NGAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation NGAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [UIViewController new];
    NGPatternView *root = [[NGPatternView alloc] initWithFrame:self.window.bounds];
    controller.view = root; self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self run:root]; });
    return YES;
}
- (void)run:(UIView *)root {
    NSString *output = NSProcessInfo.processInfo.environment[@"NG_TEST_OUTPUT"];
    if (!output.length) output = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"NGRegression"];
    NGRecorder *r = [[NGRecorder alloc] initWithOutput:output];
    NSString *domain = NSProcessInfo.processInfo.environment[@"NG_TEST_PREFS_DOMAIN"] ?: @"com.ning.glassswitchdock";
    NSArray *keys = @[@"enabledSwitch",@"enabledDock",@"dockStyle"];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary], *files = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)domain)) ?: NSNull.null;
    for (NSString *path in NGPreferencePaths()) files[path] = [NSData dataWithContentsOfFile:path] ?: (id)NSNull.null;
    NSDictionary *settings=[NGTheseusProbe settings];
    dispatch_block_t finish=^{
        [r check:[[NGTheseusProbe settings] isEqual:settings] name:@"theseus.no_global_style_quality_or_accessibility_side_effects" evidence:[NGTheseusProbe settings]];
        for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key,saved[key]==NSNull.null ? NULL : (__bridge CFPropertyListRef)saved[key],(__bridge CFStringRef)domain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
        for (NSString *path in files) {
            if (files[path]==NSNull.null) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            else [(NSData *)files[path] writeToFile:path atomically:YES];
        }
        NGPreferencesReload(); [r finish];
    };
    @try {
        [r check:TARGET_OS_SIMULATOR name:@"environment.simulator_only" evidence:@{@"isSimulator":@(TARGET_OS_SIMULATOR)}];
        BOOL isolated=YES;
        for (NSString *path in NGPreferencePaths()) if ([path hasPrefix:@"/var/mobile/Library/Preferences/"]) isolated=NO;
        [r check:isolated name:@"preferences.isolated_test_path" evidence:NGPreferencePaths()];
        if (!isolated) @throw [NSException exceptionWithName:@"UnsafeFixture" reason:@"NG_TESTING test path missing" userInfo:nil];
        [r check:[settings[@"glassStyle"] isEqual:@"automatic"] && settings[@"iosVersionOverride"]==NSNull.null &&
            settings[@"tierOverride"]==NSNull.null && settings[@"refractionPolicyOverride"]==NSNull.null &&
            settings[@"refractionQualityOverride"]==NSNull.null && [settings[@"respectsReduceMotion"] boolValue] &&
            [settings[@"respectsReduceTransparency"] boolValue] name:@"theseus.original_global_defaults" evidence:settings];
        NGRunResourceTests(r); NGRunSwitchTests(r,root);
        // Return to the main queue between phases so Metal completion blocks execute.
        dispatch_async(dispatch_get_main_queue(), ^{ NGRunDockTests(r,root,finish); });
    } @catch (NSException *error) {
        [r check:NO name:@"uncaught_exception" evidence:@{@"name":error.name,@"reason":error.reason ?: @"unknown"}];
        finish();
    }
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(NGAppDelegate.class)); }
}
