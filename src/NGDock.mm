#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

// Event-driven transparent GPU material; no background input or display link.
struct NGDockParams { vector_float2 size; float radius; float scale; uint32_t dark; uint32_t prominent; uint32_t corners; };
@interface NGStaticDockView : UIView
@property(nonatomic,strong) CALayer *face;
@property(nonatomic,copy) NSString *renderKey;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger renderRequests;
@property(nonatomic) BOOL ready;
@property(nonatomic,strong) NSData *pixels;
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
        _face=[CALayer layer];
        self.layer.masksToBounds=YES;
        self.opaque=NO;
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
    [self setNeedsLayout];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
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
    self.layer.cornerRadius=self.radius;
    self.layer.cornerCurve=self.cornerCurve ?: kCACornerCurveContinuous;
    self.layer.maskedCorners=self.roundedCorners;
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
    [self renderMaterial];
}
- (void)renderMaterial {
    CGFloat scale=self.window.screen.scale ?: UIScreen.mainScreen.scale;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    if (CGRectIsEmpty(self.bounds)) return;
    NSString *key=[NSString stringWithFormat:@"%@/%g/%g/%d/%ld/%lu",NSStringFromCGSize(self.bounds.size),self.radius,scale,dark,(long)self.style,(unsigned long)self.roundedCorners];
    if ([key isEqualToString:self.renderKey]) return;
    self.renderKey=key; self.ready=NO;
    NSUInteger generation=++self.generation; self.renderRequests++;
    NGDockParams params={{(float)self.bounds.size.width,(float)self.bounds.size.height},(float)self.radius,(float)scale,(uint32_t)dark,(uint32_t)(self.style==1),(uint32_t)self.roundedCorners};
    __weak NGStaticDockView *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        static id<MTLDevice> device;
        static id<MTLComputePipelineState> pipeline;
        static id<MTLCommandQueue> queue;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            device=MTLCreateSystemDefaultDevice();
            NSURL *url=[NGBundleResources() URLForResource:@"default" withExtension:@"metallib"];
            id<MTLLibrary> library=url ? [device newLibraryWithURL:url error:NULL] : nil;
            id<MTLFunction> function=[library newFunctionWithName:@"ngDockMaterial"];
            if (function) pipeline=[device newComputePipelineStateWithFunction:function error:NULL];
            queue=[device newCommandQueue];
        });
        if (!pipeline || !queue) return;
        NSUInteger width=(NSUInteger)ceil(params.size.x*params.scale), height=(NSUInteger)ceil(params.size.y*params.scale);
        MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
        descriptor.usage=MTLTextureUsageShaderWrite; descriptor.storageMode=MTLStorageModeShared;
        id<MTLTexture> texture=[device newTextureWithDescriptor:descriptor];
        id<MTLCommandBuffer> command=[queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
        if (!texture || !command || !encoder) return;
        [encoder setComputePipelineState:pipeline];
        [encoder setTexture:texture atIndex:0]; [encoder setBytes:&params length:sizeof(params) atIndex:0];
        [encoder dispatchThreads:MTLSizeMake(width,height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
        [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
        if (command.status!=MTLCommandBufferStatusCompleted) return;
        NSMutableData *data=[NSMutableData dataWithLength:width*height*4];
        [texture getBytes:data.mutableBytes bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
        CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGImageRef image=CGImageCreate(width,height,8,32,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
        CGColorSpaceRelease(space); CGDataProviderRelease(provider);
        dispatch_async(dispatch_get_main_queue(), ^{
            NGStaticDockView *view=weakSelf;
            if (view && view.generation==generation && image) {
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                view.face.contents=(__bridge id)image; view.face.contentsScale=scale;
                view.pixels=data; view.ready=YES;
                [CATransaction commit];
            }
            if (image) CGImageRelease(image);
        });
    });
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
static NSUInteger captureAttempts;
void NGRecordCaptureAttempt(void) { @synchronized (NGStaticDockView.class) { captureAttempts++; } }
NSUInteger NGCaptureAttemptCount(void) { @synchronized (NGStaticDockView.class) { return captureAttempts; } }
NSDictionary *NGDockDiagnostics(UIView *dock) {
    NGDockBinding *b=objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (!b) return @{};
    return @{@"static":@YES,@"captureAttempts":@(NGCaptureAttemptCount()),@"renderRequests":@(b.glass.renderRequests),@"timerActive":@NO,
        @"ready":@(b.glass.ready),@"style":@(b.glass.style)};
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
