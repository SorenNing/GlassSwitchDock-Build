#import "NGWallpaperBackdrop.h"
#import <QuartzCore/QuartzCore.h>

@interface NGWallpaperBitmapLayer : CALayer
@property(nonatomic,strong) UIImage *bitmap;
@end
@implementation NGWallpaperBitmapLayer
- (void)renderInContext:(CGContextRef)context {
    // Both original engines call this method. No screen or glass is read here.
    if (!self.bitmap) return;
    UIGraphicsPushContext(context);
    [self.bitmap drawInRect:self.bounds];
    UIGraphicsPopContext();
}
@end

static void NGCollectWallpaperViews(UIView *view, UIView *dock, NSMutableArray<UIView *> *result) {
    if (!view || view == dock || view.hidden || view.alpha <= 0.01 || [view isKindOfClass:NGWallpaperBackdrop.class]) return;
    BOOL containsDock = [dock isDescendantOfView:view];
    NSString *name = NSStringFromClass(view.class);
    if (!containsDock && [name containsString:@"Wallpaper"] && view.bounds.size.width > 100 && view.bounds.size.height > 100)
        [result addObject:view];
    for (UIView *child in view.subviews) NGCollectWallpaperViews(child,dock,result);
}

static NSDictionary *NGInspectWallpaperImage(UIImage *image) {
    uint8_t pixels[16*8*4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels,16,8,8,16*4,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context || !image.CGImage) { if (context) CGContextRelease(context); return @{@"valid":@NO}; }
    CGContextDrawImage(context,CGRectMake(0,0,16,8),image.CGImage); CGContextRelease(context);
    NSUInteger opaque=0, lit=0; uint64_t checksum=14695981039346656037ULL;
    for (NSUInteger i=0;i<sizeof(pixels);i++) checksum=(checksum^pixels[i])*1099511628211ULL;
    for (NSUInteger i=0;i<128;i++) {
        if (pixels[i*4+3] >= 240) opaque++;
        if (MAX(MAX(pixels[i*4],pixels[i*4+1]),pixels[i*4+2]) > 4) lit++;
    }
    return @{@"valid":@(opaque>=120 && lit>=8),@"opaqueSamples":@(opaque),@"litSamples":@(lit),
             @"checksum":[NSString stringWithFormat:@"%llu",(unsigned long long)checksum]};
}

@implementation NGWallpaperBackdrop {
    BOOL _hasFrame;
    NSUInteger _generation;
    NSDictionary *_diagnostics;
    CFTimeInterval _lastCapture;
    __weak UIWindow *_captureWindow;
    CGRect _lastScreenRect;
    __weak UIView *_wallpaperSource;
    CFTimeInterval _lastDiscovery;
    UIGraphicsImageRenderer *_bitmapRenderer;
    CGFloat _rendererScale;
    NSData *_lastPixels;
    NSString *_lastChecksum;
    NSUInteger _attempts;
    NSUInteger _discoveries;
    NSUInteger _unchanged;
    NSUInteger _failures;
    NSTimeInterval _captureInterval;
}
+ (Class)layerClass { return NGWallpaperBitmapLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.hidden=YES; self.userInteractionEnabled=NO; self.isAccessibilityElement=NO;
        self.backgroundColor=UIColor.clearColor; self.opaque=NO;
        _captureInterval=0.25;
    }
    return self;
}
- (BOOL)hasFrame { return _hasFrame; }
- (NSUInteger)generation { return _generation; }
- (NSUInteger)captureAttempts { return _attempts; }
- (NSDictionary *)diagnostics {
    NSMutableDictionary *details=[(_diagnostics ?: @{@"valid":@NO,@"reason":@"no wallpaper frame"}) mutableCopy];
    details[@"captureAttempts"]=@(_attempts); details[@"sourceDiscoveries"]=@(_discoveries);
    details[@"unchangedFrames"]=@(_unchanged); details[@"failedAttempts"]=@(_failures);
    details[@"generation"]=@(_generation); details[@"captureInterval"]=@(_captureInterval);
    return details;
}
- (void)setCaptureInterval:(NSTimeInterval)value {
    _captureInterval=MIN(MAX(value,0.25),2.0);
}
- (NSTimeInterval)captureInterval { return _captureInterval; }

- (BOOL)updateForDock:(UIView *)dock background:(UIView *)background force:(BOOL)force {
    UIWindow *window=dock.window;
    if (!window || !self.superview) return _hasFrame;
    CGRect onScreen=[background convertRect:background.bounds toView:window];
    CGRect capture=CGRectIntersection(CGRectInset(onScreen,-96,-96),window.bounds);
    if (CGRectIsEmpty(capture) || CGRectIsNull(capture)) return _hasFrame;
    CGRect destination=[window convertRect:capture toView:self.superview];
    BOOL geometryChanged=window!=_captureWindow || !CGRectEqualToRect(capture,_lastScreenRect) || !CGRectEqualToRect(self.frame,destination);
    CFTimeInterval now=CACurrentMediaTime();
    // All callers, including first-frame recovery, obey the capture budget.
    if (_lastCapture>0 && now-_lastCapture<_captureInterval) return _hasFrame;
    (void)force;
    _lastCapture=now; _attempts++;
    NSMutableArray<UIView *> *candidates=[NSMutableArray array];
    UIView *cached=_wallpaperSource;
    BOOL cachedVisible=cached && cached.window && cached.window.screen==window.screen &&
        ![dock isDescendantOfView:cached];
    for (UIView *parent=cached;parent && cachedVisible;parent=parent.superview)
        cachedVisible=!parent.hidden && parent.alpha>0.01;
    if (cachedVisible) [candidates addObject:cached];
    // Cache the source identity instead of walking every window on every tick.
    if (!cachedVisible && (_lastDiscovery==0 || now-_lastDiscovery>=1.0)) {
        _lastDiscovery=now; _discoveries++;
        NSMutableOrderedSet<UIWindow *> *windows=[NSMutableOrderedSet orderedSetWithObject:window];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
        for (UIWindow *candidate in windows) {
            if (candidate.hidden || candidate.alpha<=0.01 || candidate.screen!=window.screen) continue;
            NGCollectWallpaperViews(candidate,dock,candidates);
        }
    }
    CGFloat scale=window.screen.scale;
    if (!_bitmapRenderer || !CGSizeEqualToSize(_bitmapRenderer.format.bounds.size,capture.size) || _rendererScale!=scale) {
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
        format.opaque=NO; format.scale=scale;
        _bitmapRenderer=[[UIGraphicsImageRenderer alloc] initWithSize:capture.size format:format];
        _rendererScale=scale;
    }
    for (UIView *source in candidates) {
        CGRect rect=[window convertRect:capture toView:source];
        CGRect visible=CGRectIntersection(rect,source.bounds);
        if (CGRectIsEmpty(rect) || CGRectIsNull(visible) || visible.size.width*visible.size.height<rect.size.width*rect.size.height*0.98) {
            if (source==cached) _wallpaperSource=nil;
            continue;
        }
        __block BOOL drew=NO;
        UIImage *image=[_bitmapRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextScaleCTM(ctx.CGContext,capture.size.width/rect.size.width,capture.size.height/rect.size.height);
            CGContextTranslateCTM(ctx.CGContext,-rect.origin.x,-rect.origin.y);
            drew=[source drawViewHierarchyInRect:source.bounds afterScreenUpdates:NO];
        }];
        NSDictionary *inspection=NGInspectWallpaperImage(image);
        if (!drew || ![inspection[@"valid"] boolValue]) {
            if (source==cached) _wallpaperSource=nil;
            continue;
        }
        _wallpaperSource=source;
        // Exact bytes after the small signature check: don't miss a local change
        // just because the mean colour or thumbnail happened to be the same.
        NSData *pixels=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));
        BOOL same=!geometryChanged && _lastPixels && [_lastChecksum isEqual:inspection[@"checksum"]] &&
            pixels && [pixels isEqualToData:_lastPixels];
        if (same) { _unchanged++; _lastCapture=CACurrentMediaTime(); return _hasFrame; }
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        if (!CGRectEqualToRect(self.frame,destination)) self.frame=destination;
        ((NGWallpaperBitmapLayer *)self.layer).bitmap=image;
        [CATransaction commit];
        _lastPixels=pixels; _lastChecksum=inspection[@"checksum"];
        _captureWindow=window; _lastScreenRect=capture;
        _generation++; _hasFrame=YES;
        NSMutableDictionary *details=[inspection mutableCopy]; details[@"sourceClass"]=NSStringFromClass(source.class);
        details[@"captureRect"]=NSStringFromCGRect(capture); details[@"generation"]=@(_generation);
        details[@"method"]=@"cached-source wallpaper-only UIKit hierarchy bitmap";
        details[@"lastCaptureMilliseconds"]=@((CACurrentMediaTime()-now)*1000.0); _diagnostics=details;
        _lastCapture=CACurrentMediaTime();
        return YES;
    }
    // Transitions may momentarily hide the wallpaper. Keep the last valid GPU
    // input rather than toggling back to the system background on one failure.
    _failures++; _lastCapture=CACurrentMediaTime();
    _diagnostics=@{@"valid":@(_hasFrame),@"reason":_hasFrame ? @"Transient capture failure; retained previous frame" : @"No valid wallpaper frame; native background retained",
        @"candidateCount":@(candidates.count)};
    return _hasFrame;
}
@end
