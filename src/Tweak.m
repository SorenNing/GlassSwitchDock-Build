#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void (*NGHookFunction)(Class, SEL, IMP, IMP *);
static NGHookFunction gNGHook;
static void (*gSWLayout)(id,SEL), (*gSWWindow)(id,SEL), (*gSWParent)(id,SEL);
static void (*gSWOn)(id,SEL,BOOL), (*gSWEnabled)(id,SEL,BOOL), (*gSWHidden)(id,SEL,BOOL);
static void (*gSWAlpha)(id,SEL,CGFloat), (*gSWInteraction)(id,SEL,BOOL);
static void (*gSWOnAnimated)(id,SEL,BOOL,BOOL);
static void (*gSWFrame)(id,SEL,CGRect), (*gSWBounds)(id,SEL,CGRect);
static void (*gSWCenter)(id,SEL,CGPoint);
static void (*gSWTransform)(id,SEL,CGAffineTransform);
static void (*gDockLayout)(id,SEL), (*gDockWindow)(id,SEL);
static void (*gFloatingLayout)(id,SEL), (*gFloatingWindow)(id,SEL);

static void NGSwitchFrame(UISwitch *s,SEL c,CGRect v) { if (gSWFrame) gSWFrame(s,c,v); NGRefreshSwitch(s); }
static void NGSwitchBounds(UISwitch *s,SEL c,CGRect v) { if (gSWBounds) gSWBounds(s,c,v); NGRefreshSwitch(s); }
static void NGSwitchCenter(UISwitch *s,SEL c,CGPoint v) { if (gSWCenter) gSWCenter(s,c,v); NGRefreshSwitch(s); }
static void NGSwitchTransform(UISwitch *s,SEL c,CGAffineTransform v) { if (gSWTransform) gSWTransform(s,c,v); NGRefreshSwitch(s); }
static void NGSwitchLayout(UISwitch *s,SEL c) { if (gSWLayout) gSWLayout(s,c); NGRefreshSwitch(s); }
static void NGSwitchWindow(UISwitch *s,SEL c) { if (gSWWindow) gSWWindow(s,c); NGRefreshSwitch(s); }
static void NGSwitchParent(UISwitch *s,SEL c) { if (gSWParent) gSWParent(s,c); NGRefreshSwitch(s); }
static void NGSwitchOn(UISwitch *s,SEL c,BOOL v) {
    NGBeginSwitchUpdate(s,NO);
    @try { if (gSWOn) gSWOn(s,c,v); } @finally { NGEndSwitchUpdate(s); }
}
static void NGSwitchOnAnimated(UISwitch *s,SEL c,BOOL v,BOOL a) {
    NGBeginSwitchUpdate(s,a);
    @try { if (gSWOnAnimated) gSWOnAnimated(s,c,v,a); } @finally { NGEndSwitchUpdate(s); }
}
static void NGHookSwitchEnabled(UISwitch *s,SEL c,BOOL v) { if (gSWEnabled) gSWEnabled(s,c,v); NGSyncSwitch(s,NO); }
static void NGSwitchHidden(UISwitch *s,SEL c,BOOL v) { if (gSWHidden) gSWHidden(s,c,v); NGRefreshSwitch(s); }
static void NGSwitchAlpha(UISwitch *s,SEL c,CGFloat v) { BOOL replaced=NGHandleSwitchAlpha(s,v); if (gSWAlpha) gSWAlpha(s,c,replaced?0:v); }
static void NGSwitchInteraction(UISwitch *s,SEL c,BOOL v) { if (gSWInteraction) gSWInteraction(s,c,v); NGRefreshSwitch(s); }
static void NGDockLayout(UIView *s,SEL c) { if (gDockLayout) gDockLayout(s,c); NGRefreshDock(s); }
static void NGDockWindow(UIView *s,SEL c) { if (gDockWindow) gDockWindow(s,c); NGRefreshDock(s); }
static void NGFloatingLayout(UIView *s,SEL c) { if (gFloatingLayout) gFloatingLayout(s,c); NGRefreshDock(s); }
static void NGFloatingWindow(UIView *s,SEL c) { if (gFloatingWindow) gFloatingWindow(s,c); NGRefreshDock(s); }

static void NGInstallMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !gNGHook || !replacement || !original || *original) return;
    Method method = class_getInstanceMethod(cls,sel); if (!method) return;
    // Materialize inherited methods on this class instead of mutating UIView.
    class_addMethod(cls,sel,method_getImplementation(method),method_getTypeEncoding(method));
    gNGHook(cls,sel,replacement,original);
}

// Hook only methods a loaded UISwitch subclass actually overrides. Calling the
// inherited hook is insufficient when an app deliberately omits [super ...].
// Each block captures its own original IMP, including subclasses of subclasses.
static void NGInstallSwitchSubclassHooks(void) {
    if (!gNGHook) return;
    static NSMutableSet<NSString *> *installed;
    if (!installed) installed=[NSMutableSet new];
    int count=objc_getClassList(NULL,0);
    Class *classes=(Class *)calloc((size_t)MAX(count,1),sizeof(Class));
    if (!classes) return;
    count=MIN(count,objc_getClassList(classes,count));
    for (int i=0;i<count;i++) {
        Class cls=classes[i], parent=class_getSuperclass(cls);
        while (parent && parent!=UISwitch.class) parent=class_getSuperclass(parent);
        if (!parent) continue;
        unsigned int methodCount=0;
        Method *methods=class_copyMethodList(cls,&methodCount);
        for (unsigned int j=0;j<methodCount;j++) {
            SEL sel=method_getName(methods[j]);
            NSString *name=NSStringFromSelector(sel);
            NSString *key=[NSString stringWithFormat:@"%@/%@",NSStringFromClass(cls),name];
            if ([installed containsObject:key]) continue;
            __block IMP original=NULL;
            IMP replacement=NULL;
            if ([name isEqualToString:@"setFrame:"] || [name isEqualToString:@"setBounds:"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s,CGRect value) {
                    ((void(*)(id,SEL,CGRect))original)(s,sel,value); NGRefreshSwitch(s);
                });
            } else if ([name isEqualToString:@"setCenter:"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s,CGPoint value) {
                    ((void(*)(id,SEL,CGPoint))original)(s,sel,value); NGRefreshSwitch(s);
                });
            } else if ([name isEqualToString:@"setTransform:"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s,CGAffineTransform value) {
                    ((void(*)(id,SEL,CGAffineTransform))original)(s,sel,value); NGRefreshSwitch(s);
                });
            } else if ([name isEqualToString:@"layoutSubviews"] || [name isEqualToString:@"didMoveToWindow"] || [name isEqualToString:@"didMoveToSuperview"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s) {
                    ((void(*)(id,SEL))original)(s,sel); NGRefreshSwitch(s);
                });
            } else if ([name isEqualToString:@"setOn:animated:"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s,BOOL value,BOOL animated) {
                    NGBeginSwitchUpdate(s,animated);
                    @try { ((void(*)(id,SEL,BOOL,BOOL))original)(s,sel,value,animated); }
                    @finally { NGEndSwitchUpdate(s); }
                });
            } else if ([name isEqualToString:@"setOn:"] || [name isEqualToString:@"setEnabled:"] || [name isEqualToString:@"setHidden:"] || [name isEqualToString:@"setUserInteractionEnabled:"]) {
                replacement=imp_implementationWithBlock(^(UISwitch *s,BOOL value) {
                    NGBeginSwitchUpdate(s,NO);
                    @try { ((void(*)(id,SEL,BOOL))original)(s,sel,value); }
                    @finally { NGEndSwitchUpdate(s); }
                });
            }
            if (replacement) {
                gNGHook(cls,sel,replacement,&original);
                [installed addObject:key];
            }
        }
        free(methods);
    }
    free(classes);
}

#ifdef NG_TESTING
// The simulator has no substrate injection runtime. Supply its method installer
// so the exact production subclass discovery/wrappers can still be exercised.
void NGTestInstallSwitchSubclassHooks(void (*installer)(Class,SEL,IMP,IMP *)) {
    gNGHook=installer; NGInstallSwitchSubclassHooks();
}
#endif

static void NGChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ NGPreferencesReload(); NGRefreshAll(); });
}

#ifndef NG_TESTING
__attribute__((constructor)) static void NGInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NGPreferencesReload();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NGChanged,
            CFSTR("com.ning.glassswitchdock/changed"),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        gNGHook = (NGHookFunction)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
        if (!gNGHook) {
            for (NSString *path in @[@"/usr/lib/libsubstrate.dylib",@"/var/jb/usr/lib/libsubstrate.dylib"]) {
                void *handle=dlopen(path.UTF8String,RTLD_NOW|RTLD_LOCAL);
                if (handle) gNGHook=(NGHookFunction)dlsym(handle,"MSHookMessageEx");
                if (gNGHook) break;
            }
        }
        Class sw = UISwitch.class;
        NGInstallMethod(sw,@selector(setFrame:),(IMP)NGSwitchFrame,(IMP *)&gSWFrame);
        NGInstallMethod(sw,@selector(setBounds:),(IMP)NGSwitchBounds,(IMP *)&gSWBounds);
        NGInstallMethod(sw,@selector(setCenter:),(IMP)NGSwitchCenter,(IMP *)&gSWCenter);
        NGInstallMethod(sw,@selector(setTransform:),(IMP)NGSwitchTransform,(IMP *)&gSWTransform);
        NGInstallMethod(sw,@selector(layoutSubviews),(IMP)NGSwitchLayout,(IMP *)&gSWLayout);
        NGInstallMethod(sw,@selector(didMoveToWindow),(IMP)NGSwitchWindow,(IMP *)&gSWWindow);
        NGInstallMethod(sw,@selector(didMoveToSuperview),(IMP)NGSwitchParent,(IMP *)&gSWParent);
        NGInstallMethod(sw,@selector(setOn:),(IMP)NGSwitchOn,(IMP *)&gSWOn);
        NGInstallMethod(sw,@selector(setOn:animated:),(IMP)NGSwitchOnAnimated,(IMP *)&gSWOnAnimated);
        NGInstallMethod(sw,@selector(setEnabled:),(IMP)NGHookSwitchEnabled,(IMP *)&gSWEnabled);
        NGInstallMethod(sw,@selector(setHidden:),(IMP)NGSwitchHidden,(IMP *)&gSWHidden);
        NGInstallMethod(sw,@selector(setAlpha:),(IMP)NGSwitchAlpha,(IMP *)&gSWAlpha);
        NGInstallMethod(sw,@selector(setUserInteractionEnabled:),(IMP)NGSwitchInteraction,(IMP *)&gSWInteraction);
        // App classes are normally registered before constructors; repeat at
        // launch/activation to include classes loaded by later app frameworks.
        NGInstallSwitchSubclassHooks();
        for (NSNotificationName name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NGInstallSwitchSubclassHooks(); NGRefreshAllSwitches();
            }];
        }
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            Class dock=NSClassFromString(@"SBDockView");
            NGInstallMethod(dock,@selector(layoutSubviews),(IMP)NGDockLayout,(IMP *)&gDockLayout);
            NGInstallMethod(dock,@selector(didMoveToWindow),(IMP)NGDockWindow,(IMP *)&gDockWindow);
            Class floating=NSClassFromString(@"SBFloatingDockPlatterView");
            NGInstallMethod(floating,@selector(layoutSubviews),(IMP)NGFloatingLayout,(IMP *)&gFloatingLayout);
            NGInstallMethod(floating,@selector(didMoveToWindow),(IMP)NGFloatingWindow,(IMP *)&gFloatingWindow);
        }
    });
}
#endif
