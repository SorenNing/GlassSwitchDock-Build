#import "NGHarness.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@implementation NGRecorder {
    NSDate *_started;
    NSMutableArray<NSDictionary *> *_captures;
}
- (instancetype)initWithOutput:(NSString *)output {
    if ((self = [super init])) {
        _output = [output copy]; _checks = [NSMutableArray array];
        _captures = [NSMutableArray array]; _started = [NSDate date];
        [[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}
- (void)check:(BOOL)success name:(NSString *)name evidence:(id)evidence {
    if (!success) _failures++;
    id payload = evidence ?: @{};
    if (![NSJSONSerialization isValidJSONObject:@[payload]]) payload = [payload description];
    [_checks addObject:@{@"id": name, @"passed": @(success), @"evidence": payload}];
    NSLog(@"[NGRegression] %@ %@ %@", success ? @"PASS" : @"FAIL", name, payload);
}
- (void)capture:(UIView *)view name:(NSString *)name {
    [view layoutIfNeeded]; [CATransaction flush];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    __block BOOL drew = NO;
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        drew = [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSData *png = UIImagePNGRepresentation(image);
    NSString *file = [name stringByAppendingPathExtension:@"png"];
    BOOL wrote = png.length > 0 && [png writeToFile:[_output stringByAppendingPathComponent:file] atomically:YES];
    [self check:wrote && drew name:[@"screenshot." stringByAppendingString:name]
       evidence:@{@"file": file, @"bytes": @(png.length), @"hierarchyDrawSucceeded": @(drew),
                  @"width": @(image.size.width), @"height": @(image.size.height)}];
    if (wrote) [_captures addObject:@{@"file": file, @"kind": @"UIKit drawViewHierarchy; Metal checked separately"}];
}
- (void)finish {
    NSDictionary *report = @{@"schema": @1, @"suite": @"GlassSwitchDock native UIKit regression",
        @"status": _failures == 0 ? @"passed" : @"failed", @"failures": @(_failures),
        @"started": @([_started timeIntervalSince1970]), @"finished": @([[NSDate date] timeIntervalSince1970]),
        @"environment": @{@"kind": @"iOS Simulator UIKit application", @"os": UIDevice.currentDevice.systemVersion,
            @"model": UIDevice.currentDevice.model, @"simulator": NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"] ?: @"unknown",
            @"hardwareProof": @NO, @"dockFixture": @"synthetic SpringBoard-named UIView classes"},
        @"checks": _checks, @"captures": _captures,
        @"limitations": @[@"Does not load SpringBoard or exercise real icon layout.",
            @"Synthetic UIControl tracking and vendor scripting exercise original component logic; this is not HID/XCUITest touch delivery.",
            @"PNG snapshots need visual inspection; shader execution and original rendering backends are asserted separately."]};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [json writeToFile:[_output stringByAppendingPathComponent:@"report.json"] atomically:YES];
    NSLog(@"[NGRegression] COMPLETE failures=%lu report=%@/report.json", (unsigned long)_failures, _output);
}
@end

@implementation NGEventSpy
- (instancetype)init { if ((self = [super init])) _values = [NSMutableArray array]; return self; }
- (void)changed:(UISwitch *)sender { _count++; [_values addObject:@(sender.on)]; }
@end

@implementation NGPatternView
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSArray *colors = @[UIColor.systemBlueColor, UIColor.systemOrangeColor, UIColor.systemPinkColor, UIColor.systemTealColor];
    for (NSInteger y = 0; y < (NSInteger)self.bounds.size.height; y += 16)
        for (NSInteger x = 0; x < (NSInteger)self.bounds.size.width; x += 16) {
            [colors[((x / 16) + (y / 16) + _phase) % colors.count] setFill];
            CGContextFillRect(context, CGRectMake(x, y, 16, 16));
        }
}
@end

@implementation SBDockView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _backgroundView = [[UIView alloc] initWithFrame:self.bounds];
        _backgroundView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.15];
        _backgroundView.layer.cornerRadius = 30; _backgroundView.userInteractionEnabled = NO;
        [self addSubview:_backgroundView];
        _icon = [UIButton buttonWithType:UIButtonTypeSystem];
        _icon.frame = CGRectMake(28, 15, 52, 52); _icon.backgroundColor = UIColor.systemIndigoColor;
        _icon.layer.cornerRadius = 12; [_icon setImage:[UIImage systemImageNamed:@"app.fill"] forState:UIControlStateNormal];
        [self addSubview:_icon];
    }
    return self;
}
@end
@implementation SBFloatingDockPlatterView
@end

NSArray<UIView *> *NGDescendants(UIView *root) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *child in root.subviews) { [result addObject:child]; [result addObjectsFromArray:NGDescendants(child)]; }
    return result;
}
static BOOL NGTheseusClass(UIView *view, NSString *name) {
    NSString *actual = NSStringFromClass(view.class);
    return [actual isEqualToString:name] || [actual hasSuffix:[@"." stringByAppendingString:name]];
}
NSArray<UIView *> *NGOriginalSwitches(UIView *root) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *view in NGDescendants(root))
        if (NGTheseusClass(view, @"TheseusSwitch")) [result addObject:view];
    return result;
}
UIView *NGSwitchComponent(UISwitch *source, UIView *scope, NSInteger style) {
    NSArray *candidates = NGOriginalSwitches(scope);
    UIView *best = nil; CGFloat distance = CGFLOAT_MAX;
    for (UIView *view in candidates) {
        if ((style == 0) != NGTheseusClass(view, @"TheseusSwitch")) continue;
        CGPoint a = [source convertPoint:CGPointMake(CGRectGetMidX(source.bounds), CGRectGetMidY(source.bounds)) toView:scope];
        CGPoint b = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds)) toView:scope];
        CGFloat d = hypot(a.x-b.x, a.y-b.y);
        if (d < distance) { distance = d; best = view; }
    }
    return distance < 30 ? best : nil;
}
void NGPump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do { [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]]; }
    while (until.timeIntervalSinceNow > 0);
}
BOOL NGReadOn(id control) {
    SEL getter = [control respondsToSelector:@selector(isOn)] ? @selector(isOn) : NSSelectorFromString(@"on");
    return control && [control respondsToSelector:getter] ? ((BOOL (*)(id, SEL))objc_msgSend)(control, getter) : NO;
}
void NGWritePreferences(BOOL enabledSwitch, BOOL enabledDock, NSInteger dockStyle) {
    NSString *domain = NSProcessInfo.processInfo.environment[@"NG_TEST_PREFS_DOMAIN"] ?: @"com.ning.glassswitchdock";
    NSDictionary *values = @{@"enabledSwitch": @(enabledSwitch),
                             @"enabledDock": @(enabledDock), @"dockStyle": @(dockStyle)};
    (void)domain;
    for (NSString *key in values) {
        if (!NGStorePreference(key, values[key]))
            @throw [NSException exceptionWithName:@"NGPreferenceWriteFailed" reason:key userInfo:nil];
    }
    NGPreferencesReload();
    NGPump(0.04);
}

void NGRefreshFixtureDock(UIView *dock) {
    NGRefreshDock(dock);
    NGRefreshDocks();
    [dock layoutIfNeeded];
}
