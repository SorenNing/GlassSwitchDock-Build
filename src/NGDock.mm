#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

// Static compositor layers only: no wallpaper source, timer, blur or Metal view.
@interface NGStaticDockView : UIView
@property(nonatomic,strong) CAGradientLayer *face;
@property(nonatomic,strong) CAGradientLayer *rim;
@property(nonatomic,strong) CALayer *rimMask;
@property(nonatomic) CGFloat radius;
@property(nonatomic,copy) NSString *cornerCurve;
@property(nonatomic) CACornerMask roundedCorners;
@property(nonatomic) NSInteger style;
- (void)updatePalette;
@end
@implementation NGStaticDockView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.accessibilityIdentifier=@"NGDockGlass";
        self.backgroundColor=UIColor.clearColor;
        _face=[CAGradientLayer layer];
        _face.locations=@[@0,@0.48,@1];
        [self.layer addSublayer:_face];
        _rim=[CAGradientLayer layer];
        _rim.locations=@[@0,@0.45,@1];
        _rimMask=[CALayer layer];
        _rimMask.backgroundColor=UIColor.clearColor.CGColor;
        _rimMask.borderColor=UIColor.whiteColor.CGColor;
        _rimMask.borderWidth=0.5;
        _rim.mask=_rimMask;
        [self.layer addSublayer:_rim];
        [self updatePalette];
    }
    return self;
}
- (void)updatePalette {
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    CGFloat strength=self.style==1 ? 1.2 : 1;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.face.colors=@[(id)[UIColor colorWithWhite:1 alpha:(dark ? 0.16 : 0.36)*strength].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:(dark ? 0.065 : 0.17)*strength].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:(dark ? 0.11 : 0.26)*strength].CGColor];
    self.rim.colors=@[(id)[UIColor colorWithWhite:1 alpha:dark ? 0.65 : 0.9].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0.12].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:dark ? 0.3 : 0.55].CGColor];
    [CATransaction commit];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self updatePalette];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.face.frame=self.bounds;
    self.face.cornerRadius=self.radius;
    self.face.cornerCurve=self.cornerCurve ?: kCACornerCurveContinuous;
    self.face.maskedCorners=self.roundedCorners;
    self.rim.frame=self.bounds;
    self.rimMask.frame=self.bounds;
    self.rimMask.cornerRadius=self.radius;
    self.rimMask.cornerCurve=self.face.cornerCurve;
    self.rimMask.maskedCorners=self.roundedCorners;
    [CATransaction commit];
}
@end

static char kNGDockBindingKey;
static NSHashTable<UIView *> *NGSeenDocks(void) {
    static NSHashTable *seen; static dispatch_once_t once;
    dispatch_once(&once, ^{ seen=[NSHashTable weakObjectsHashTable]; }); return seen;
}
static UIView *NGDockBackground(UIView *dock) {
    SEL getter=NSSelectorFromString(@"backgroundView");
    if ([dock respondsToSelector:getter]) {
        NSMethodSignature *signature=[dock methodSignatureForSelector:getter];
        if (signature.numberOfArguments==2 && signature.methodReturnType[0]=='@') {
            id object=((id(*)(id,SEL))objc_msgSend)(dock,getter);
            if ([object isKindOfClass:UIView.class] && object!=dock) return object;
        }
    }
    for (NSString *name in @[@"_backgroundView",@"_backgroundMaterialView"]) {
        Ivar ivar=class_getInstanceVariable(dock.class,name.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0]=='@') {
            id object=object_getIvar(dock,ivar);
            if ([object isKindOfClass:UIView.class] && object!=dock) return object;
        }
    }
    return nil;
}
@interface NGDockBinding : NSObject
@property(nonatomic,strong) UIView *background;
@property(nonatomic,weak) UIView *backgroundParent;
@property(nonatomic) NSUInteger backgroundIndex;
@property(nonatomic) BOOL backgroundHidden;
@property(nonatomic,strong) NGStaticDockView *glass;
@property(nonatomic) CGFloat backgroundAlpha;
@end
@implementation NGDockBinding
@end

void NGRemoveDock(UIView *dock) {
    NGDockBinding *binding=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (!binding) return;
    UIView *parent=binding.backgroundParent;
    if (parent && !binding.background.superview)
        [parent insertSubview:binding.background atIndex:MIN(binding.backgroundIndex,parent.subviews.count)];
    [binding.glass removeFromSuperview];
    binding.background.alpha=binding.backgroundAlpha;
    binding.background.hidden=binding.backgroundHidden;
    objc_setAssociatedObject(dock,&kNGDockBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
#ifdef NG_TESTING
NSDictionary *NGDockDiagnostics(UIView *dock) {
    NGDockBinding *b=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (!b) return @{};
    return @{@"static":@YES,@"captureAttempts":@0,@"renderRequests":@0,@"timerActive":@NO,
        @"ready":@YES,@"style":@(b.glass.style)};
}
#endif
void NGRefreshDock(UIView *dock) {
    if (!NSThread.isMainThread || ![dock isKindOfClass:UIView.class]) return;
    [NGSeenDocks() addObject:dock];
    if (!NGDockEnabled()) { NGRemoveDock(dock); return; }
    // Retain the exact same layers across app/home transitions.
    if (!dock.window) return;
    UIView *background=NGDockBackground(dock);
    NGDockBinding *binding=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (binding && binding.background!=background) { NGRemoveDock(dock); binding=nil; }
    if (!background || CGRectIsEmpty(background.bounds)) return;
    UIView *parent=background.superview ?: binding.backgroundParent;
    if (!parent || (parent!=dock && ![parent isDescendantOfView:dock])) return;
    if (!binding) {
        binding=[NGDockBinding new]; binding.background=background;
        binding.backgroundAlpha=background.alpha;
        binding.backgroundHidden=background.hidden;
        binding.glass=[[NGStaticDockView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(dock,&kNGDockBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NGStaticDockView *glass=binding.glass;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (background.superview) {
        binding.backgroundParent=parent;
        binding.backgroundHidden=background.hidden;
        [glass removeFromSuperview];
        binding.backgroundIndex=[parent.subviews indexOfObjectIdenticalTo:background];
        [parent insertSubview:glass belowSubview:background];
    }
    // The detached view retains system-owned geometry, but cannot composite.
    CGRect frame=background.frame;
    if (!CGRectEqualToRect(glass.frame,frame)) glass.frame=frame;
    CALayer *geometry=background.layer;
    if (geometry.cornerRadius<=0) {
        for (UIView *child in background.subviews)
            if (child.layer.cornerRadius>geometry.cornerRadius) geometry=child.layer;
    }
    CGFloat limit=MIN(background.bounds.size.width,background.bounds.size.height)/2;
    CGFloat radius=geometry.cornerRadius>0 ? MIN(geometry.cornerRadius,limit) : limit;
    NSString *curve=geometry.cornerCurve;
    CACornerMask corners=geometry.maskedCorners;
    if (glass.radius!=radius || ![glass.cornerCurve isEqualToString:curve] || glass.roundedCorners!=corners) {
        glass.radius=radius;
        glass.cornerCurve=curve;
        glass.roundedCorners=corners;
        [glass setNeedsLayout];
    }
    NSInteger style=NGDockStyle();
    if (glass.style!=style) { glass.style=style; [glass updatePalette]; }
    glass.hidden=binding.backgroundHidden;
    glass.alpha=binding.backgroundAlpha;
    [background removeFromSuperview];
    [CATransaction commit];
}
void NGRefreshDocks(void) {
    for (UIView *dock in NGSeenDocks().allObjects) NGRefreshDock(dock);
}
