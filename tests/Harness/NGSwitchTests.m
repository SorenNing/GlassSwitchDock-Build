#import "NGHarness.h"
#import <objc/runtime.h>

extern void NGTestInstallSwitchSubclassHooks(void (*installer)(Class,SEL,IMP,IMP *));
static void NGFixtureInstall(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method method=class_getInstanceMethod(cls,sel);
    *original=method_getImplementation(method);
    class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(method));
}
// Deliberately omit super, as an app subclass is allowed to do. This is a
// synthetic app fixture, not evidence of WeChat's actual control hierarchy.
@interface NGAppSwitchFixture : UISwitch
@property(nonatomic) BOOL fixtureOn;
@end
@implementation NGAppSwitchFixture
- (void)layoutSubviews {}
- (BOOL)isOn { return self.fixtureOn; }
- (void)setOn:(BOOL)value { self.fixtureOn=value; }
- (void)setOn:(BOOL)value animated:(BOOL)animated { self.on=value; [self layoutSubviews]; }
@end

static BOOL NGComponentOn(UIView *component, NSInteger style) {
    return [[NGTheseusProbe inspectSwitch:component][@"isOn"] boolValue];
}
static BOOL NGInteract(UIView *component, NSInteger style, BOOL drag, BOOL on) {
    return drag ? [NGTheseusProbe drag:component toOn:on] : [NGTheseusProbe activate:component];
}
static NSDictionary *NGState(UISwitch *source, UIView *component, NSInteger style, NGEventSpy *spy) {
    return @{@"sourceOn": @(source.on), @"componentOn": @(component && NGComponentOn(component, style)),
             @"eventCount": @(spy.count), @"eventValues": spy.values,
             @"sourceAlpha": @(source.alpha), @"sourceInteraction": @(source.userInteractionEnabled),
             @"sourceAccessibilityElement": @(source.isAccessibilityElement),
             @"componentClass": component ? NSStringFromClass(component.class) : @"missing"};
}
static NSString *NGID(NSInteger style, NSString *name) {
    return [NSString stringWithFormat:@"switch.%@.%@", @"theseus", name];
}

void NGRunSwitchTests(NGRecorder *r, UIView *root) {
    UIView *fixture = [[UIView alloc] initWithFrame:CGRectMake(12, 60, root.bounds.size.width - 24, 190)];
    [root addSubview:fixture];
    UISwitch *a = [[UISwitch alloc] initWithFrame:CGRectMake(22, 18, 63, 28)];
    UISwitch *b = [[UISwitch alloc] initWithFrame:CGRectMake(150, 18, 63, 28)];
    UISwitch *unrelated = [[UISwitch alloc] initWithFrame:CGRectMake(22, 100, 63, 28)];
    unrelated.accessibilityLabel = @"Unrelated native switch";
    [fixture addSubview:a]; [fixture addSubview:b]; [fixture addSubview:unrelated];
    NGEventSpy *spyA = [NGEventSpy new], *spyB = [NGEventSpy new], *spyOther = [NGEventSpy new];
    [a addTarget:spyA action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [b addTarget:spyB action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [unrelated addTarget:spyOther action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    a.accessibilityLabel = @"Primary fixture switch";
    BOOL initialAccessibility = a.isAccessibilityElement;
    for (NSInteger style = 0; style == 0; style++) {
        NGWritePreferences(NO, NO, 0); NGRefreshSwitch(a); NGRefreshSwitch(b);
        [a setOn:NO animated:NO]; [b setOn:YES animated:NO]; [unrelated setOn:NO animated:NO];
        spyA.count = 0; [spyA.values removeAllObjects]; spyB.count = 0; spyOther.count = 0;
        NGWritePreferences(YES, NO, 0); NGRefreshSwitch(a); NGRefreshSwitch(b); NGPump(0.12);
        UIView *component = NGSwitchComponent(a, fixture, style);
        UIView *second = NGSwitchComponent(b, fixture, style);
        [r check:component && second && component != second && NGOriginalSwitches(fixture).count == 2
               name:NGID(style, @"original_identity")
           evidence:@{@"classes": [[NGOriginalSwitches(fixture) valueForKey:@"class"] description],
                      @"count": @(NGOriginalSwitches(fixture).count)}];
        if (!component || !second) continue;
        if (style == 0) {
            NSDictionary *identity = [NGTheseusProbe inspectSwitch:component];
            [r check:[identity[@"layoutUnmodified"] boolValue] && [identity[@"materialUnmodified"] boolValue] &&
                     [identity[@"onTintUnmodified"] boolValue] && [identity[@"offTintUnmodified"] boolValue] &&
                     [identity[@"thumbTintUnmodified"] boolValue]
                   name:NGID(style, @"original_defaults") evidence:identity];
            UIView *wrapper = component.superview;
            while (wrapper && ![NSStringFromClass(wrapper.class) isEqualToString:@"NGTheseusSwitch"]) wrapper = wrapper.superview;
            [r check:wrapper && ![wrapper isKindOfClass:UIControl.class] &&
                     [wrapper respondsToSelector:@selector(setOn:animated:)] &&
                     ([wrapper respondsToSelector:@selector(isOn)] || [wrapper respondsToSelector:NSSelectorFromString(@"on")])
                   name:NGID(style, @"uiview_bridge_contract")
               evidence:@{@"wrapperClass": wrapper ? NSStringFromClass(wrapper.class) : @"missing"}];
        }
        [r check:fabs(component.bounds.size.width-63) < 0.01 && fabs(component.bounds.size.height-28) < 0.01 && CGAffineTransformIsIdentity(component.transform)
               name:NGID(style, @"original_size_63x28")
           evidence:@{@"bounds": NSStringFromCGRect(component.bounds), @"transform": NSStringFromCGAffineTransform(component.transform)}];
        a.transform=CGAffineTransformMakeScale(0.7,0.7);
        NGRefreshSwitch(a); [component.superview layoutIfNeeded];
        CGRect visible=[component convertRect:component.bounds toView:fixture];
        [r check:fabs(visible.size.width-63)<0.01 && fabs(visible.size.height-28)<0.01
               name:NGID(style, @"scaled_host_preserves_visible_size")
           evidence:@{@"visible":NSStringFromCGRect(visible)}];
        fixture.transform=CGAffineTransformMakeScale(0.65,0.8);
        NGRefreshSwitch(a); [component.superview layoutIfNeeded];
        CGRect windowSize=[component convertRect:component.bounds toView:root.window];
        [r check:fabs(windowSize.size.width-63)<0.01 && fabs(windowSize.size.height-28)<0.01
               name:NGID(style, @"scaled_parent_preserves_window_size")
           evidence:@{@"windowBounds":NSStringFromCGRect(windowSize)}];
        CGPoint savedCenter = a.center;
        CGRect savedBounds = a.bounds;
        a.center = CGPointMake(savedCenter.x + 38, savedCenter.y + 9);
        a.bounds = CGRectOffset(savedBounds, 7, 3);
        NGRefreshSwitch(a);
        CGPoint nativeCenter = [a convertPoint:CGPointMake(CGRectGetMidX(a.bounds), CGRectGetMidY(a.bounds)) toView:root.window];
        CGPoint overlayCenter = [component convertPoint:CGPointMake(CGRectGetMidX(component.bounds), CGRectGetMidY(component.bounds)) toView:root.window];
        [r check:hypot(nativeCenter.x-overlayCenter.x,nativeCenter.y-overlayCenter.y)<0.01
               name:NGID(style, @"moved_host_center_alignment")
               evidence:@{@"native":NSStringFromCGPoint(nativeCenter), @"overlay":NSStringFromCGPoint(overlayCenter)}];
        a.bounds = savedBounds; a.center = savedCenter; NGRefreshSwitch(a);
        NSDictionary *lifecycle = [NGTheseusProbe lifecycle:component];
        [r check:[lifecycle[@"sharesContainer"] boolValue] && [lifecycle[@"coordinatesMatch"] boolValue] &&
                 [lifecycle[@"hideInvalidatesPresentation"] boolValue] &&
                 [lifecycle[@"landedThumbVisible"] boolValue] && [lifecycle[@"reusedThumbVisible"] boolValue]
               name:NGID(style, @"glass_lifecycle_scaled_parent") evidence:lifecycle];
        fixture.transform=CGAffineTransformIdentity;
        a.transform=CGAffineTransformIdentity; NGRefreshSwitch(a);
        [r check:!NGComponentOn(component, style) && NGComponentOn(second, style) && spyA.count == 0
               name:NGID(style, @"initial_sync_silent") evidence:NGState(a, component, style, spyA)];
        BOOL activated = NGInteract(component, style, NO, YES); NGPump(0.18);
        [r check:activated && a.on && NGComponentOn(component, style) && spyA.count == 1 && spyA.values.count == 1 && [spyA.values[0] boolValue]
               name:NGID(style, @"user_tap_exactly_one_native_event") evidence:NGState(a, component, style, spyA)];
        [r check:b.on && NGComponentOn(second, style) && !unrelated.on && spyB.count == 0 && spyOther.count == 0
               name:NGID(style, @"unrelated_controls_unchanged")
           evidence:@{@"secondOn": @(b.on), @"secondEvents": @(spyB.count), @"nativeOn": @(unrelated.on), @"nativeEvents": @(spyOther.count)}];
        BOOL dragged = NGInteract(component, style, YES, NO); NGPump(0.18);
        [r check:dragged && !a.on && !NGComponentOn(component, style) && spyA.count == 2 && spyA.values.count == 2 && ![spyA.values.lastObject boolValue]
               name:NGID(style, @"drag_commits_exactly_one_native_event") evidence:NGState(a, component, style, spyA)];
        // Nested native setters/layout callbacks must leave the overlay's old
        // value intact until the outer animated operation has completed.
        NGBeginSwitchUpdate(a,YES);
        [a setOn:YES animated:NO];
        NGBeginSwitchUpdate(a,NO); NGRefreshSwitch(a); NGEndSwitchUpdate(a);
        BOOL deferred = !NGComponentOn(component,style);
        NGEndSwitchUpdate(a);
        [r check:deferred && NGComponentOn(component,style) && a.on && spyA.count==2
               name:NGID(style,@"nested_setter_defers_state_sync") evidence:NGState(a,component,style,spyA)];
        [a setOn:NO animated:NO]; NGRefreshSwitch(a);
        for (NSUInteger i = 0; i < 6; i++) {
            BOOL value = i % 2 == 0;
            [a setOn:value animated:i % 2]; NGRefreshSwitch(a); NGPump(0.025);
            component = NGSwitchComponent(a, fixture, style);
            [r check:component && NGComponentOn(component, style) == value && spyA.count == 2
                   name:NGID(style, [NSString stringWithFormat:@"programmatic_sync_%lu", (unsigned long)i])
               evidence:NGState(a, component, style, spyA)];
        }
        a.enabled = NO; NGRefreshSwitch(a); component = NGSwitchComponent(a, fixture, style);
        BOOL before = a.on; NSUInteger eventsBefore = spyA.count;
        BOOL componentDisabled = !component || ([component isKindOfClass:UIControl.class] && !((UIControl *)component).enabled);
        BOOL attempted = NO;
        if (component && style == 0) attempted = [NGTheseusProbe activate:component];
        [r check:componentDisabled && !attempted && a.on == before && spyA.count == eventsBefore
               name:NGID(style, @"disabled_ignores_user_input") evidence:NGState(a, component, style, spyA)];
        a.enabled = YES; NGRefreshSwitch(a); component = NGSwitchComponent(a, fixture, style);
        [r check:component && ((UIControl *)component).enabled name:NGID(style, @"reenabled") evidence:NGState(a, component, style, spyA)];
        [r capture:root name:NGID(style, @"render_off")];
        [a setOn:YES animated:NO]; NGRefreshSwitch(a); NGPump(0.25);
        [r capture:root name:NGID(style, @"render_on")];
        // Re-enable the sole original control while preserving source state.
        NSInteger replacement = 0;
        __weak UIView *oldComponent = component;
        NGWritePreferences(NO, NO, 0); NGRefreshSwitch(a); NGRefreshSwitch(b); NGPump(0.05);
        NGWritePreferences(YES, NO, 0); NGRefreshSwitch(a); NGRefreshSwitch(b); NGPump(0.1);
        UIView *newComponent = NGSwitchComponent(a, fixture, replacement);
        [r check:newComponent && a.on && NGComponentOn(newComponent, replacement) &&
                 (!oldComponent || !oldComponent.window) && NGOriginalSwitches(fixture).count == 2 && spyA.count == eventsBefore
               name:NGID(style, @"reenable_detaches_old_preserves_state")
           evidence:@{@"newClass": newComponent ? NSStringFromClass(newComponent.class) : @"missing", @"count": @(NGOriginalSwitches(fixture).count),
                      @"oldInWindow": @(oldComponent.window != nil), @"sourceOn": @(a.on), @"events": @(spyA.count)}];
        for (NSUInteger i = 0; i < 12; i++) NGRefreshSwitch(a);
        [r check:NGOriginalSwitches(fixture).count == 2 name:NGID(style, @"refresh_is_idempotent")
           evidence:@{@"componentCount": @(NGOriginalSwitches(fixture).count)}];
        UIView *otherParent = [[UIView alloc] initWithFrame:CGRectMake(12, 260, root.bounds.size.width-24, 70)];
        [root addSubview:otherParent];
        [a removeFromSuperview]; [otherParent addSubview:a]; a.frame = CGRectMake(22, 15, 63, 28);
        NGRefreshSwitch(a); NGPump(0.08);
        UIView *reparented = NGSwitchComponent(a, otherParent, replacement);
        [r check:reparented && NGOriginalSwitches(otherParent).count == 1 && NGOriginalSwitches(fixture).count == 1 &&
                 NGComponentOn(reparented, replacement) && a.on
               name:NGID(style, @"reparent_removes_old_sibling")
           evidence:@{@"oldParentComponents": @(NGOriginalSwitches(fixture).count), @"newParentComponents": @(NGOriginalSwitches(otherParent).count)}];
        [a removeFromSuperview]; NGRefreshSwitch(a); NGPump(0.05);
        [r check:NGOriginalSwitches(otherParent).count == 0 name:NGID(style, @"source_detach_removes_overlay")
           evidence:@{@"oldParentComponents": @(NGOriginalSwitches(otherParent).count)}];
        [fixture addSubview:a]; a.frame = CGRectMake(22, 18, 63, 28); NGRefreshSwitch(a);
        [otherParent removeFromSuperview];
        NGWritePreferences(NO, NO, 0); NGRefreshSwitch(a); NGRefreshSwitch(b); NGPump(0.05);
        [r check:NGOriginalSwitches(fixture).count == 0 && fabs(a.alpha-1) < 0.001 && a.userInteractionEnabled && a.isAccessibilityElement == initialAccessibility && a.on
               name:NGID(style, @"disable_restores_native_state")
           evidence:@{@"overlays": @(NGOriginalSwitches(fixture).count), @"alpha": @(a.alpha),
                      @"interaction": @(a.userInteractionEnabled), @"accessibilityElement": @(a.isAccessibilityElement), @"on": @(a.on)}];
        // Regression: original non-default host properties must survive installation/removal.
        a.alpha = 0.37; a.userInteractionEnabled = NO; a.isAccessibilityElement = NO;
        NGWritePreferences(YES, NO, 0); NGRefreshSwitch(a); NGPump(0.04);
        NGWritePreferences(NO, NO, 0); NGRefreshSwitch(a); NGPump(0.04);
        [r check:fabs(a.alpha-0.37) < 0.001 && !a.userInteractionEnabled && !a.isAccessibilityElement
               name:NGID(style, @"restore_saved_nondefault_host_properties")
           evidence:@{@"alpha": @(a.alpha), @"interaction": @(a.userInteractionEnabled), @"accessibilityElement": @(a.isAccessibilityElement)}];
        a.alpha = 1; a.userInteractionEnabled = YES; a.isAccessibilityElement = YES;
    }
    NGWritePreferences(YES, NO, 0);
    NGTestInstallSwitchSubclassHooks(NGFixtureInstall);
    NGAppSwitchFixture *appSwitch=[[NGAppSwitchFixture alloc] initWithFrame:CGRectMake(22,100,63,28)];
    [fixture addSubview:appSwitch]; [appSwitch layoutSubviews];
    UIView *appComponent=NGSwitchComponent(appSwitch,fixture,0);
    [appSwitch setOn:YES animated:YES];
    [r check:appComponent && NGComponentOn(appComponent,0) && appSwitch.on
           name:@"switch.theseus.subclass_override_without_super"
           evidence:@{@"sourceClass":NSStringFromClass(appSwitch.class),@"componentFound":@(appComponent!=nil),@"on":@(appSwitch.on)}];
    NGRemoveSwitch(appSwitch); [appSwitch removeFromSuperview];
    NGWritePreferences(NO, NO, 0); NGRemoveSwitch(a); NGRemoveSwitch(b);
    [fixture removeFromSuperview];
}
