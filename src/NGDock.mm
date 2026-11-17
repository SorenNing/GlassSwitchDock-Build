#import "Bridge.h"
#import "NGSystemBackdrop.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kNGDockBindingKey;
static NSHashTable<UIView *> *NGSeenDocks(void) {
    static NSHashTable *seen; static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSHashTable weakObjectsHashTable]; }); return seen;
}

static UIView *NGDockBackground(UIView *dock) {
    SEL getter = NSSelectorFromString(@"backgroundView");
    if ([dock respondsToSelector:getter]) {
        NSMethodSignature *signature = [dock methodSignatureForSelector:getter];
        if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@') {
            id object = ((id(*)(id,SEL))objc_msgSend)(dock,getter);
            if ([object isKindOfClass:UIView.class] && object != dock) return object;
        }
    }
    for (NSString *name in @[@"_backgroundView", @"_backgroundMaterialView"]) {
        Ivar ivar = class_getInstanceVariable(dock.class,name.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') {
            id object = object_getIvar(dock,ivar);
            if ([object isKindOfClass:UIView.class] && object != dock) return object;
        }
    }
    return nil;
}

@interface NGDockBinding : NSObject
@property(nonatomic,weak) UIView *dock;
@property(nonatomic,weak) UIView *background;
@property(nonatomic,strong) NGSystemBackdrop *glass;
@property(nonatomic) CGFloat backgroundAlpha;
@property(nonatomic) NSInteger style;
@property(nonatomic) BOOL updating;
@end
@implementation NGDockBinding
@end

static void NGDockRestore(NGDockBinding *binding) {
    if (!binding) return;
    [binding.glass detach];[binding.glass removeFromSuperview];
    binding.background.alpha=binding.backgroundAlpha;
}
void NGRemoveDock(UIView *dock) {
    NGDockBinding *binding=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    NGDockRestore(binding);
    objc_setAssociatedObject(dock,&kNGDockBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void NGDockSetVisibility(NGDockBinding *binding,BOOL frame) {
    // The backdrop stays renderable while waiting for its first GPU frame.
    // A failed/unavailable backend leaves the native background visible.
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        binding.background.alpha=frame?0:binding.backgroundAlpha;
        binding.glass.alpha=binding.backgroundAlpha;
        [CATransaction commit];
    }];
}
void NGRefreshDock(UIView *dock) {
    if (!NSThread.isMainThread || ![dock isKindOfClass:UIView.class]) return;
    [NGSeenDocks() addObject:dock];
    if (!NGDockEnabled() || !dock.window) {NGRemoveDock(dock);return;}
    UIView *background=NGDockBackground(dock);
    if (!background.superview || ![background isDescendantOfView:dock] || CGRectIsEmpty(background.bounds)) return;
    NGDockBinding *binding=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (binding.updating) return;
    NSInteger style=NGDockStyle();
    if (binding && (binding.background!=background || binding.style!=style)) {NGRemoveDock(dock);binding=nil;}
    if (!binding) {
        if (!NGBundleResources() || ![NGSystemBackdrop isAvailable]) return;
        CGRect frame=[background convertRect:background.bounds toView:background.superview];
        NGSystemBackdrop *glass=[[NGSystemBackdrop alloc] initWithFrame:frame];if (!glass) return;
        binding=[NGDockBinding new];binding.dock=dock;binding.background=background;binding.glass=glass;
        binding.backgroundAlpha=background.alpha;binding.style=style;
        glass.accessibilityIdentifier=@"NGDockGlass";glass.userInteractionEnabled=NO;glass.isAccessibilityElement=NO;
        __weak NGDockBinding *weak=binding;
        glass.onFrame=^(BOOL success) {
            NGDockBinding *b=weak;
            if (b && NGDockEnabled() && b.style==NGDockStyle() && objc_getAssociatedObject(b.dock,&kNGDockBindingKey)==b)
                NGDockSetVisibility(b,success);
        };
        objc_setAssociatedObject(dock,&kNGDockBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [background.superview insertSubview:glass aboveSubview:background];
    }
    binding.updating=YES;
    @try {
        NGSystemBackdrop *glass=binding.glass;
        if (glass.superview!=background.superview) [background.superview insertSubview:glass aboveSubview:background];
        CGRect frame=[background convertRect:background.bounds toView:background.superview];
        if (!CGRectEqualToRect(glass.frame,frame)) glass.frame=frame;
        CGFloat radius=background.layer.cornerRadius;
        if (radius<=0) for (UIView *child in background.subviews) radius=MAX(radius,child.layer.cornerRadius);
        if (radius<=0) radius=MIN(background.bounds.size.width,background.bounds.size.height)/2;
        radius=MIN(radius,MIN(background.bounds.size.width,background.bounds.size.height)/2);
        [glass setSurfaceHidden:background.hidden];
        [glass configureWithRadius:radius style:style];
        NGDockSetVisibility(binding,glass.hasFrame);
    } @finally {binding.updating=NO;}
}
void NGRefreshDocks(void) {for (UIView *dock in NGSeenDocks().allObjects) NGRefreshDock(dock);}
#ifdef NG_TESTING
NSDictionary *NGDockDiagnostics(UIView *dock) {
    NGDockBinding *binding=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    return binding?binding.glass.diagnostics:@{};
}
#endif
