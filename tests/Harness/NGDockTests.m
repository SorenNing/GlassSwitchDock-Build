#import "NGHarness.h"
#import <QuartzCore/QuartzCore.h>

static UIView *NGMaterial(UIView *dock) {
    for (UIView *view in NGDescendants(dock))
        if ([NSStringFromClass(view.class) isEqualToString:@"NGStaticDockView"]) return view;
    return nil;
}
static NSString *NGDockID(Class cls, NSInteger style, NSString *name) {
    return [NSString stringWithFormat:@"dock.%@.%@.%@",NSStringFromClass(cls),
        style==0 ? @"staticClear" : @"staticProminent",name];
}
static NSData *NGMaterialPixels(UIView *material) {
    if (!material || CGRectIsEmpty(material.bounds)) return nil;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:material.bounds.size];
    return UIImagePNGRepresentation([renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [material.layer renderInContext:context.CGContext];
    }]);
}
void NGRunDockTests(NGRecorder *r, UIView *root, dispatch_block_t completion) {
    for (Class cls in @[SBDockView.class,SBFloatingDockPlatterView.class]) {
        for (NSInteger style=0;style<2;style++) {
            NGPatternView *wallpaper=[[NGPatternView alloc] initWithFrame:root.bounds];
            [root insertSubview:wallpaper atIndex:0];
            SBDockView *dock=[[cls alloc] initWithFrame:CGRectMake(15,366,root.bounds.size.width-30,84)];
            [root addSubview:dock];
            CGFloat alpha=dock.backgroundView.alpha;
            NGWritePreferences(NO,YES,style); NGRefreshFixtureDock(dock);
            UIView *material=NGMaterial(dock); [material layoutIfNeeded];
            BOOL staticOnly=material!=nil && [material.layer.sublayers count]==2;
            for (UIView *v in NGDescendants(dock)) {
                NSString *name=NSStringFromClass(v.class);
                if ([name containsString:@"WallpaperBackdrop"] || [name containsString:@"Metal"] ||
                    [v isKindOfClass:GLSGlassView.class]) staticOnly=NO;
            }
            [r check:staticOnly name:NGDockID(cls,style,@"static_layers_only") evidence:NGDockDiagnostics(dock)];
            [r check:CGRectEqualToRect(material.frame,dock.backgroundView.frame) &&
                material.layer.sublayers.firstObject.cornerRadius==30
                name:NGDockID(cls,style,@"host_geometry") evidence:@{@"frame":NSStringFromCGRect(material.frame)}];
            CALayer *face=material.layer.sublayers.firstObject;
            CALayer *rim=material.layer.sublayers.lastObject.mask;
            [r check:[face.cornerCurve isEqualToString:dock.backgroundView.layer.cornerCurve] &&
                [rim.cornerCurve isEqualToString:face.cornerCurve] && rim.cornerRadius==face.cornerRadius &&
                rim.maskedCorners==face.maskedCorners && fabs(rim.borderWidth-0.5)<0.001
                name:NGDockID(cls,style,@"native_corners_and_half_point_rim") evidence:@{}];
            [r check:!material.userInteractionEnabled && !material.isAccessibilityElement
                name:NGDockID(cls,style,@"no_touch_interception") evidence:@{}];
            UIView *hit=[dock hitTest:[dock.icon convertPoint:CGPointMake(26,26) toView:dock] withEvent:nil];
            [r check:hit==dock.icon || [hit isDescendantOfView:dock.icon]
                name:NGDockID(cls,style,@"dock_icon_hit_test_preserved") evidence:@{}];
            [r check:!dock.backgroundView.superview
                name:NGDockID(cls,style,@"native_background_detached") evidence:@{}];
            [dock insertSubview:dock.backgroundView atIndex:0];
            dock.backgroundView.alpha=1;
            NGRefreshFixtureDock(dock);
            [r check:!dock.backgroundView.superview && NGMaterial(dock)==material
                name:NGDockID(cls,style,@"system_reattach_removed") evidence:@{}];
            NSData *before=NGMaterialPixels(material);
            wallpaper.phase++; [wallpaper setNeedsDisplay];
            for (NSUInteger i=0;i<100;i++) NGRefreshFixtureDock(dock);
            [material layoutIfNeeded];
            NSData *after=NGMaterialPixels(material);
            [r check:before.length>0 && [before isEqualToData:after]
                name:NGDockID(cls,style,@"wallpaper_change_preserves_pixels") evidence:@{@"bytes":@(after.length)}];
            [r check:NGMaterial(dock)==material && [NGDockDiagnostics(dock)[@"captureAttempts"] integerValue]==0 &&
                [NGDockDiagnostics(dock)[@"renderRequests"] integerValue]==0 &&
                ![NGDockDiagnostics(dock)[@"timerActive"] boolValue]
                name:NGDockID(cls,style,@"no_capture_or_polling") evidence:NGDockDiagnostics(dock)];
            [dock removeFromSuperview]; NGRefreshFixtureDock(dock);
            BOOL retained=NGMaterial(dock)==material;
            [root addSubview:dock]; NGRefreshFixtureDock(dock);
            [r check:retained && NGMaterial(dock)==material && !dock.backgroundView.superview && material.alpha==alpha
                name:NGDockID(cls,style,@"window_transition_retains_layers") evidence:@{@"retained":@(retained)}];
            dock.hidden=YES; NGRefreshFixtureDock(dock); dock.hidden=NO;
            wallpaper.hidden=YES; NGRefreshFixtureDock(dock);
            [r check:NGMaterial(dock)==material && material.alpha==alpha && !dock.backgroundView.superview
                name:NGDockID(cls,style,@"works_without_wallpaper") evidence:@{}];
            [r capture:root name:NGDockID(cls,style,@"render")];
            NGWritePreferences(NO,NO,style); NGRefreshFixtureDock(dock);
            [r check:!NGMaterial(dock) && dock.backgroundView.superview==dock && dock.subviews.firstObject==dock.backgroundView && fabs(dock.backgroundView.alpha-alpha)<0.001
                name:NGDockID(cls,style,@"disable_restores_background") evidence:@{}];
            [dock removeFromSuperview]; [wallpaper removeFromSuperview];
        }
    }
    completion();
}
