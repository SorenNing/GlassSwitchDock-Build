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
    return [material valueForKey:@"pixels"];
}
// A nested RunLoop inside a main-queue block cannot drain main-queue Metal
// completions. Return to dispatch between polls and between fixture cases.
static void NGAwaitDock(NGRecorder *r, UIView *dock, NSDate *deadline, dispatch_block_t completion, dispatch_block_t next) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([NGDockDiagnostics(dock)[@"ready"] boolValue] || deadline.timeIntervalSinceNow<=0) next();
            else NGAwaitDock(r,dock,deadline,completion,next);
        } @catch (NSException *error) {
            [r check:NO name:@"dock.uncaught_exception" evidence:@{@"name":error.name,@"reason":error.reason ?: @"unknown"}];
            completion();
        }
    });
}
static void NGRunDockCase(NGRecorder *r, UIView *root, NSUInteger index, dispatch_block_t completion) {
    if (index==4) { completion(); return; }
    Class cls=index<2 ? SBDockView.class : SBFloatingDockPlatterView.class;
    NSInteger style=index%2;
    @try {
            NGPatternView *wallpaper=[[NGPatternView alloc] initWithFrame:root.bounds];
            [root insertSubview:wallpaper atIndex:0];
            SBDockView *dock=[[cls alloc] initWithFrame:CGRectMake(15,366,root.bounds.size.width-30,84)];
            [root addSubview:dock];
            NSUInteger capturesBefore=NGCaptureAttemptCount();
            CGFloat alpha=dock.backgroundView.alpha;
            NGWritePreferences(NO,YES,style); NGRefreshFixtureDock(dock);
            UIView *material=NGMaterial(dock); [material layoutIfNeeded];
            NGAwaitDock(r,dock,[NSDate dateWithTimeIntervalSinceNow:15],completion, ^{
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
            const uint8_t *bytes=before.bytes;
            NSUInteger transparent=0, translucent=0, colored=0;
            uint8_t minAlpha=255,maxAlpha=0;
            for (NSUInteger i=0;i+3<before.length;i+=4) {
                uint8_t a=bytes[i+3]; minAlpha=MIN(minAlpha,a); maxAlpha=MAX(maxAlpha,a);
                if (!a) transparent++;
                if (a>0 && a<255) translucent++;
                if (a>0 && bytes[i]>0 && bytes[i+1]>0 && bytes[i+2]>0) colored++;
            }
            [r check:before.length>0 && transparent>0 && translucent>0 && colored==translucent && maxAlpha>minAlpha+20 && maxAlpha<255
                name:NGDockID(cls,style,@"real_gpu_rgba_without_black_backing")
                evidence:@{@"bytes":@(before.length),@"transparent":@(transparent),@"translucent":@(translucent),@"minAlpha":@(minAlpha),@"maxAlpha":@(maxAlpha)}];
            NSUInteger requests=[NGDockDiagnostics(dock)[@"renderRequests"] unsignedIntegerValue];
            wallpaper.phase++; [wallpaper setNeedsDisplay];
            for (NSUInteger i=0;i<100;i++) NGRefreshFixtureDock(dock);
            [material layoutIfNeeded];
            NSData *after=NGMaterialPixels(material);
            [r check:before.length>0 && [before isEqualToData:after]
                name:NGDockID(cls,style,@"wallpaper_change_preserves_pixels") evidence:@{@"bytes":@(after.length)}];
            [r check:NGMaterial(dock)==material && NGCaptureAttemptCount()==capturesBefore &&
                [NGDockDiagnostics(dock)[@"renderRequests"] unsignedIntegerValue]==requests &&
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
            dock.backgroundView.frame=CGRectMake(0,0,260,100);
            dock.backgroundView.layer.cornerRadius=19;
            dock.backgroundView.layer.cornerCurve=kCACornerCurveCircular;
            dock.backgroundView.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMaxYCorner;
            NGRefreshFixtureDock(dock); [material layoutIfNeeded];
            NGAwaitDock(r,dock,[NSDate dateWithTimeIntervalSinceNow:15],completion, ^{
            NSData *resized=NGMaterialPixels(material);
            [r check:[NGDockDiagnostics(dock)[@"ready"] boolValue] && resized.length!=before.length && material.layer.cornerRadius==19 && [material.layer.cornerCurve isEqualToString:kCACornerCurveCircular] && material.layer.maskedCorners==dock.backgroundView.layer.maskedCorners
                name:NGDockID(cls,style,@"layout_updates_gpu_and_native_clip") evidence:@{}];
            material.overrideUserInterfaceStyle=material.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
            [material setNeedsLayout]; [material layoutIfNeeded];
            NGAwaitDock(r,dock,[NSDate dateWithTimeIntervalSinceNow:15],completion, ^{
            [r check:[NGDockDiagnostics(dock)[@"ready"] boolValue] && ![resized isEqualToData:NGMaterialPixels(material)] && NGCaptureAttemptCount()==capturesBefore
                name:NGDockID(cls,style,@"dark_mode_updates_gpu_without_capture") evidence:@{}];
            [r capture:root name:NGDockID(cls,style,@"render")];
            NGWritePreferences(NO,NO,style); NGRefreshFixtureDock(dock);
            [r check:!NGMaterial(dock) && dock.backgroundView.superview==dock && dock.subviews.firstObject==dock.backgroundView && fabs(dock.backgroundView.alpha-alpha)<0.001
                name:NGDockID(cls,style,@"disable_restores_background") evidence:@{}];
            [dock removeFromSuperview]; [wallpaper removeFromSuperview];
            dispatch_async(dispatch_get_main_queue(), ^{ NGRunDockCase(r,root,index+1,completion); });
            });
            });
            });
    } @catch (NSException *error) {
        [r check:NO name:@"dock.uncaught_exception" evidence:@{@"name":error.name,@"reason":error.reason ?: @"unknown"}];
        completion();
    }
}
void NGRunDockTests(NGRecorder *r, UIView *root, dispatch_block_t completion) {
    NGRunDockCase(r,root,0,completion);
}
