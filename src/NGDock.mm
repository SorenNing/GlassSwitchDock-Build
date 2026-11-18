#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Glassify/GLSGlassView.h>
#import <Metal/Metal.h>
#import "NGWallpaperBackdrop.h"
#import "GLSRenderer.h"

// The exact Objective-C accessors from the original GLSGlassSurface header.
@protocol NGDockSurface <NSObject>
@property(nonatomic) BOOL keepsOutput;
@property(nonatomic) BOOL hidden;
@property(nonatomic,readonly) id<MTLTexture> outputTexture;
@end
@interface GLSGlassView (NGDockCapture)
- (id<NGDockSurface>)gls_surface;
@end

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
@property(nonatomic,strong) UIView *glass;
@property(nonatomic,strong) NGWallpaperBackdrop *wallpaper;
@property(nonatomic) CGFloat radius;
@property(nonatomic) CGFloat backgroundAlpha;
@property(nonatomic) NSInteger style;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL queued;
@property(nonatomic) BOOL dirty;
@property(nonatomic) BOOL suspended;
@property(nonatomic) NSUInteger renderedGeneration;
@property(nonatomic) NSUInteger renderRequests;
@property(nonatomic) NSUInteger idlePolls;
@property(nonatomic) NSUInteger lastPollAttempts;
@property(nonatomic) BOOL waitingForGlassifyFrame;
@property(nonatomic,strong) UITraitCollection *lastTraits;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation NGDockBinding
- (void)dealloc { [_timer invalidate]; }
@end

static void NGDockRestore(NGDockBinding *binding) {
    if (!binding) return;
    [binding.timer invalidate]; binding.timer = nil;
    if (binding.style==0) [(id<NGGlassComponent>)binding.glass setRenderingActive:NO];
    [binding.glass removeFromSuperview];
    [binding.wallpaper removeFromSuperview];
    binding.background.alpha = binding.backgroundAlpha;
}

void NGRemoveDock(UIView *dock) {
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
    NGDockRestore(binding);
    objc_setAssociatedObject(dock,&kNGDockBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL NGDockVisible(NGDockBinding *binding) {
    UIView *dock=binding.dock;
    if (!dock.window || binding.background.hidden || dock.window.hidden) return NO;
    for (UIView *v=dock;v;v=v.superview) {
        CALayer *shown=v.layer.presentationLayer ?: v.layer;
        if (v.hidden || shown.opacity<=0.01) return NO;
    }
    CGRect rect=[dock convertRect:dock.bounds toView:dock.window];
    return !CGRectIsEmpty(CGRectIntersection(rect,dock.window.bounds));
}

static void NGDockSetVisibility(NGDockBinding *binding, BOOL ready) {
    [UIView performWithoutAnimation:^{
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        CGFloat nativeAlpha=ready ? 0 : binding.backgroundAlpha;
        CGFloat glassAlpha=ready ? binding.backgroundAlpha : 0;
        if (binding.background.alpha!=nativeAlpha) binding.background.alpha=nativeAlpha;
        if (binding.glass.alpha!=glassAlpha) binding.glass.alpha=glassAlpha;
        [CATransaction commit];
    }];
}

static void NGDockMarkReady(NGDockBinding *binding) {
    if (!binding || !binding.wallpaper.hasFrame || !NGDockVisible(binding) || !NGDockEnabled() || binding.style!=NGDockStyle()) return;
    if (objc_getAssociatedObject(binding.dock,&kNGDockBindingKey)!=binding) return;
    binding.ready=YES;
    NGDockSetVisibility(binding,YES);
}

static void NGDockUpdateBackdrop(NGDockBinding *binding, BOOL force) {
    if (!binding || binding.updating || objc_getAssociatedObject(binding.dock,&kNGDockBindingKey)!=binding) return;
    binding.updating=YES;
    @try {
        if (!NGDockVisible(binding)) {
            if (!binding.suspended) {
                binding.suspended=YES;
                if (binding.style==0) [(id<NGGlassComponent>)binding.glass setRenderingActive:NO];
                else [((GLSGlassView *)binding.glass) gls_surface].hidden=YES;
            }
            return;
        }
        if (binding.suspended) { binding.suspended=NO; binding.dirty=YES; binding.idlePolls=0; binding.wallpaper.captureInterval=0.25; }
        if (![binding.wallpaper updateForDock:binding.dock background:binding.background force:force]) {
            if (!binding.ready) NGDockSetVisibility(binding,NO);
            return;
        }
        NSUInteger generation=binding.wallpaper.generation;
        BOOL changed=generation!=binding.renderedGeneration;
        BOOL geometryChanged=binding.dirty;
        if (!changed && !geometryChanged) {
            NSUInteger attempts=binding.wallpaper.captureAttempts;
            if (attempts!=binding.lastPollAttempts) {
                binding.lastPollAttempts=attempts; binding.idlePolls++;
                binding.wallpaper.captureInterval=binding.idlePolls>=8 ? 1.0 : binding.idlePolls>=4 ? 0.5 : 0.25;
            }
            return;
        }
        binding.idlePolls=0; binding.wallpaper.captureInterval=0.25;
        binding.renderedGeneration=generation; binding.lastPollAttempts=binding.wallpaper.captureAttempts;
        binding.dirty=NO; binding.renderRequests++;
        if (binding.style==0) {
            id<NGGlassComponent> component=(id)binding.glass;
            if (geometryChanged) [component configureWithRadius:binding.radius source:binding.wallpaper excluded:@[]];
            [component setRenderingActive:YES];
            [component invalidateBackdrop];
        } else {
            GLSGlassView *glass=(id)binding.glass;
            [glass gls_surface].hidden=NO;
            if (glass.cornerRadius!=binding.radius) glass.cornerRadius=binding.radius;
            if (glass.backdropSourceView!=binding.wallpaper) glass.backdropSourceView=binding.wallpaper;
            [glass setNeedsBackdropUpdate];
            if (!binding.ready && !binding.waitingForGlassifyFrame) {
                [glass layoutIfNeeded];
                binding.waitingForGlassifyFrame=YES;
                // setNeedsGlassRender enqueues the draw on this same main queue.
                // Enqueue the fence after that draw, without blocking the UI.
                __weak NGDockBinding *weak=binding;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NGDockBinding *b=weak;
                    if (!b || objc_getAssociatedObject(b.dock,&kNGDockBindingKey)!=b) return;
                    id<MTLTexture> texture=[((GLSGlassView *)b.glass) gls_surface].outputTexture;
                    id<MTLCommandBuffer> fence=[[GLSRenderer shared].queue commandBuffer];
                    id<MTLBuffer> proof=texture ? [texture.device newBufferWithLength:256 options:MTLResourceStorageModeShared] : nil;
                    id<MTLBlitCommandEncoder> blit=fence && proof ? [fence blitCommandEncoder] : nil;
                    if (!texture || !texture.width || !texture.height || !blit) {
                        [blit endEncoding];
                        b.waitingForGlassifyFrame=NO; b.dirty=YES; return;
                    }
                    // Read one centre pixel once, not a frame-sized recurring copy.
                    // Texture allocation alone does not prove a draw succeeded.
                    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0
                        sourceOrigin:MTLOriginMake(texture.width/2,texture.height/2,0)
                        sourceSize:MTLSizeMake(1,1,1) toBuffer:proof destinationOffset:0
                        destinationBytesPerRow:256 destinationBytesPerImage:256];
                    [blit endEncoding];
                    [fence addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NGDockBinding *current=weak;
                            if (!current || objc_getAssociatedObject(current.dock,&kNGDockBindingKey)!=current) return;
                            current.waitingForGlassifyFrame=NO;
                            const uint8_t *pixel=(const uint8_t *)proof.contents;
                            if (completed.status==MTLCommandBufferStatusCompleted && pixel && pixel[3]>=200) {
                                NGDockMarkReady(current);
#ifndef NG_TESTING
                                // The retained texture was only needed as first-
                                // frame proof. Stop copying every later drawable.
                                if (current.ready) [((GLSGlassView *)current.glass) gls_surface].keepsOutput=NO;
#endif
                            } else current.dirty=YES;
                        });
                    }];
                    [fence commit];
                });
            }
        }
    } @finally { binding.updating=NO; }
}

static void NGDockArmPoll(NGDockBinding *binding) {
    if (!binding || binding.timer || !binding.dock.window) return;
    NSTimeInterval interval=binding.suspended ? 1.0 : binding.wallpaper.captureInterval;
    __weak NGDockBinding *weak=binding;
    binding.timer=[NSTimer timerWithTimeInterval:interval repeats:NO block:^(NSTimer *timer) {
        NGDockBinding *b=weak;
        if (!b) return;
        b.timer=nil;
        if (!b.dock.window || objc_getAssociatedObject(b.dock,&kNGDockBindingKey)!=b) return;
        if (!NGDockEnabled() || b.style!=NGDockStyle()) { NGRefreshDock(b.dock); return; }
        NGDockUpdateBackdrop(b,NO);
        NGDockArmPoll(b);
    }];
    binding.timer.tolerance=interval*0.15;
    [NSRunLoop.mainRunLoop addTimer:binding.timer forMode:NSRunLoopCommonModes];
}

static void NGDockSchedule(NGDockBinding *binding) {
    if (!binding || binding.queued) return;
    binding.queued=YES;
    __weak NGDockBinding *weak=binding;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGDockBinding *b=weak;
        if (!b || objc_getAssociatedObject(b.dock,&kNGDockBindingKey)!=b) return;
        b.queued=NO;
        NGDockUpdateBackdrop(b,NO);
        NGDockArmPoll(b);
    });
}

#ifdef NG_TESTING
NSDictionary *NGDockDiagnostics(UIView *dock) {
    NGDockBinding *b=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (!b) return @{};
    return @{@"renderRequests":@(b.renderRequests),@"ready":@(b.ready),@"suspended":@(b.suspended),
        @"queued":@(b.queued),@"wallpaper":b.wallpaper.diagnostics ?: @{}};
}
#endif

void NGRefreshDock(UIView *dock) {
    if (!NSThread.isMainThread || ![dock isKindOfClass:UIView.class]) return;
    [NGSeenDocks() addObject:dock];
    if (!NGDockEnabled() || !dock.window) { NGRemoveDock(dock); return; }
    UIView *background = NGDockBackground(dock);
    if (!background.superview || ![background isDescendantOfView:dock] || CGRectIsEmpty(background.bounds)) return;
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (binding.updating) return;
    NSInteger style = NGDockStyle();
    if (binding && (binding.background != background || binding.style != style)) { NGRemoveDock(dock); binding = nil; }
    if (!binding) {
        if (!NGBundleResources()) return;
        binding = [NGDockBinding new]; binding.dock = dock; binding.background = background;
        binding.backgroundAlpha = background.alpha; binding.style = style; binding.dirty=YES;
        CGRect frame = [background convertRect:background.bounds toView:background.superview];
        binding.wallpaper=[[NGWallpaperBackdrop alloc] initWithFrame:CGRectZero];
        [background.superview insertSubview:binding.wallpaper belowSubview:background];
        if (style == 0) {
            Class cls = NSClassFromString(@"NGClearDockView");
            if (!cls) { [binding.wallpaper removeFromSuperview]; return; }
            binding.glass = [[cls alloc] initWithFrame:frame];
            [(id<NGGlassComponent>)binding.glass setRenderingActive:NO];
            __weak NGDockBinding *weak = binding;
            [(id<NGGlassComponent>)binding.glass setOnReady:^{ NGDockMarkReady(weak); }];
        } else {
            GLSGlassView *glass = [[GLSGlassView alloc] initWithFrame:frame];
            // Exact background configuration of the original Prominent Clear button.
            glass.style = GLSGlassStyleClear;
            glass.glassTintColor = UIColor.secondarySystemFillColor;
            glass.contentVibrancy = YES;
            glass.contentVibrancyStyle = GLSContentVibrancyStyleControls;
            glass.interactive = NO;
            glass.tracksBackdropMotion = NO;
            [glass gls_surface].keepsOutput = YES;
            binding.glass = glass;
        }
        if (style==1) [(GLSGlassView *)binding.glass setBackdropSourceView:binding.wallpaper];
        binding.glass.accessibilityIdentifier = @"NGDockGlass";
        binding.glass.isAccessibilityElement = NO;
        binding.glass.userInteractionEnabled = NO;
        objc_setAssociatedObject(dock,&kNGDockBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        binding.glass.alpha=0;
        [background.superview insertSubview:binding.glass aboveSubview:background];

    }
    UIView *glass = binding.glass;
    if (glass.superview != background.superview) { [glass removeFromSuperview]; [background.superview insertSubview:glass aboveSubview:background]; }
    CGRect frame=[background convertRect:background.bounds toView:background.superview];
    if (!CGRectEqualToRect(glass.frame,frame)) { glass.frame=frame; binding.dirty=YES; }
    if (!binding.lastTraits || [glass.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:binding.lastTraits]) {
        binding.lastTraits=glass.traitCollection; binding.dirty=YES;
    }
    CGFloat radius = background.layer.cornerRadius;
    if (radius <= 0) {
        for (UIView *child in background.subviews) radius = MAX(radius,child.layer.cornerRadius);
    }
    if (radius <= 0) radius = MIN(CGRectGetWidth(background.bounds),CGRectGetHeight(background.bounds))/2;
    radius = MIN(radius,MIN(CGRectGetWidth(background.bounds),CGRectGetHeight(background.bounds))/2);
    if (binding.radius!=radius) { binding.radius=radius; binding.dirty=YES; }
    glass.hidden=background.hidden;
    if (binding.wallpaper.superview!=background.superview) {
        [binding.wallpaper removeFromSuperview];
        [background.superview insertSubview:binding.wallpaper belowSubview:background];
    }
    if (binding.dirty) {
        binding.wallpaper.captureInterval=0.25; binding.idlePolls=0;
        [binding.timer invalidate]; binding.timer=nil;
    }
    if (binding.ready) NGDockSetVisibility(binding,YES);
    NGDockSchedule(binding);
}

void NGRefreshDocks(void) {
    for (UIView *dock in NGSeenDocks().allObjects) NGRefreshDock(dock);
}
