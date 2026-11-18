#import "NGSystemBackdrop.h"
#import "Bridge.h"
#import "NGDockStatePath.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>

static NSString *NGStateDirectory(void) {
    return NGDockSharedStateDirectory();
}
static int64_t NGBoot(void) {struct timeval t={};size_t n=sizeof(t);int k[]={CTL_KERN,KERN_BOOTTIME};return sysctl(k,2,&t,&n,NULL,0)==0?t.tv_sec:0;}
static NSMutableIndexSet *NGSlots(void) {static NSMutableIndexSet *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSMutableIndexSet indexSet];});return s;}
static NSHashTable<NGSystemBackdrop *> *NGSurfaces(void) {static NSHashTable *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSHashTable weakObjectsHashTable];});return s;}
static void NGBackendChanged(CFNotificationCenterRef,void *,CFStringRef,const void *,CFDictionaryRef);

@interface NGSystemBackdrop ()
@property(nonatomic,readwrite) BOOL hasFrame;
@property(nonatomic,readwrite) NSUInteger slot;
@property(nonatomic,copy) NSString *token;
@property(nonatomic,copy) NSDictionary *lastPacket;
@property(nonatomic) BOOL attached;
@property(nonatomic) BOOL detached;
@property(nonatomic) BOOL reserved;
@property(nonatomic,copy) NSDictionary *geometry;
@property(nonatomic) pid_t backendPID;
@property(nonatomic) BOOL surfaceHidden;
@property(nonatomic,copy) NSString *failedToken;
@property(nonatomic) BOOL backendReadPending;
@property(nonatomic) BOOL backendReadAgain;
- (void)setSurfaceHidden:(BOOL)hidden;
- (void)scheduleBackendRead;
- (void)applyBackend:(NSDictionary *)backend ack:(NSDictionary *)ack boot:(int64_t)boot alive:(BOOL)alive;
- (void)scheduleHealthCheck;
@end
@implementation NGSystemBackdrop
+ (Class)layerClass {return NSClassFromString(@"CABackdropLayer")?:CALayer.class;}
+ (BOOL)isAvailable {return NSClassFromString(@"CABackdropLayer")!=Nil && NSClassFromString(@"CAFilter")!=Nil;}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    if (![self.class isAvailable]) return nil;
    _slot=0;while ([NGSlots() containsIndex:_slot] && _slot<8) _slot++;
    if (_slot>=8) return nil;
    [NGSlots() addIndex:_slot];_reserved=YES;_token=NSUUID.UUID.UUIDString;
    self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.backgroundColor=UIColor.clearColor;self.opaque=NO;
    self.layer.hidden=YES;
    self.layer.masksToBounds=YES;self.layer.cornerCurve=kCACornerCurveContinuous;
    self.layer.actions=@{@"bounds":NSNull.null,@"position":NSNull.null,@"filters":NSNull.null,@"opacity":NSNull.null};
    NSString *group=[@"com.ning.glassswitchdock.dock." stringByAppendingString:_token];
    @try {
        [self.layer setValue:@NO forKey:@"layerUsesCoreImageFilters"];
        [self.layer setValue:@YES forKey:@"windowServerAware"];
        [self.layer setValue:group forKey:@"groupName"];
        [self.layer setValue:@"com.ning.glassswitchdock" forKey:@"groupNamespace"];
        [self.layer setValue:@YES forKey:@"ignoresScreenClip"];
        // No downscaling of our established material parameters.
        [self.layer setValue:@1 forKey:@"scale"];
    } @catch (NSException *e) {return nil;}
    [NGSurfaces() addObject:self];
    static dispatch_once_t once;
    dispatch_once(&once,^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NGBackendChanged,CFSTR("com.ning.glassswitchdock/dock-backend-ready"),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        for (unsigned n=0;n<8;n++) {
            NSString *name=[NSString stringWithFormat:@"com.ning.glassswitchdock/dock-frame-%u",n];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NGBackendChanged,(__bridge CFStringRef)name,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        }
    });
    [self scheduleHealthCheck];
    return self;
}
- (void)scheduleHealthCheck {
    __weak NGSystemBackdrop *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NGSystemBackdrop *s=weak;
        if (!s || s.detached) return;
        // Backend death does not necessarily send a Darwin notification.
        if (s.window && !s.surfaceHidden) [s scheduleBackendRead];
        [s scheduleHealthCheck];
    });
}
- (void)dealloc {if (_reserved) [NGSlots() removeIndex:_slot];}
- (BOOL)configureWithRadius:(CGFloat)radius style:(NSInteger)style {
    if (_detached || CGRectIsEmpty(self.bounds)) return NO;
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    NSDictionary *geometry=@{@"width":@(self.bounds.size.width),@"height":@(self.bounds.size.height),@"radius":@(radius),@"scale":@(scale),@"dark":@(dark),@"style":@(style)};
    if ([_geometry isEqualToDictionary:geometry]) return _attached;
    if (self.layer.contentsScale!=scale) self.layer.contentsScale=scale;
    NSMutableDictionary *packet=nil;
    if (style==0) {
        Class c=NSClassFromString(@"NGDockMaterialParameters");id object=[c new];
        SEL s=NSSelectorFromString(@"packetWithSize:radius:scale:dark:");
        if (![object respondsToSelector:s]) return NO;
        NSDictionary *p=((id(*)(id,SEL,CGSize,CGFloat,CGFloat,BOOL))objc_msgSend)(object,s,self.bounds.size,radius,scale,dark);
        packet=[p mutableCopy];
    } else {
        UIColor *tint=[UIColor.secondarySystemFillColor resolvedColorWithTraitCollection:self.traitCollection];
        CGFloat r=0,g=0,b=0,a=0;[tint getRed:&r green:&g blue:&b alpha:&a];
        packet=[@{@"style":@1,@"width":@(self.bounds.size.width),@"height":@(self.bounds.size.height),@"scale":@(scale),@"dark":@(dark),@"tint":@[@(r),@(g),@(b),@(a)]} mutableCopy];
    }
    if (!packet) return NO;
    packet[@"radius"]=@(radius);packet[@"schema"]=@1;packet[@"slot"]=@(_slot);packet[@"active"]=@YES;
    self.layer.cornerRadius=radius;
    if (![_lastPacket isEqualToDictionary:packet]) {
        NSDictionary *published=[packet copy];NSString *token=NSUUID.UUID.UUIDString;
        packet[@"token"]=token;packet[@"pid"]=@(getpid());
        BOOL directory=NO;NSString *statePath=NGStateDirectory();
        if (!statePath.length || ![NSFileManager.defaultManager fileExistsAtPath:statePath isDirectory:&directory] || !directory) return NO;
        NSString *file=[statePath stringByAppendingPathComponent:[NSString stringWithFormat:@"slot-%lu.plist",(unsigned long)_slot]];
        if (![packet writeToFile:file atomically:YES]) return NO;
        chmod(file.fileSystemRepresentation,0644);
        _lastPacket=published;_geometry=geometry;_token=token;_hasFrame=NO;_failedToken=nil;
        self.layer.filters=nil;self.layer.hidden=YES;_attached=NO;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ning.glassswitchdock/dock-parameters"),NULL,NULL,true);
    }
    [self scheduleBackendRead];return _attached;
}
- (void)scheduleBackendRead {
    if (_detached) return;
    if (_backendReadPending) {_backendReadAgain=YES;return;}
    _backendReadPending=YES;
    NSUInteger slot=_slot;
    __weak NGSystemBackdrop *weak=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSString *statePath=NGStateDirectory();
        NSDictionary *backend=statePath.length?[NSDictionary dictionaryWithContentsOfFile:[statePath stringByAppendingPathComponent:@"backend.plist"]]:nil;
        NSDictionary *ack=statePath.length?[NSDictionary dictionaryWithContentsOfFile:[statePath stringByAppendingPathComponent:[NSString stringWithFormat:@"ack-%lu.plist",(unsigned long)slot]]]:nil;
        pid_t pid=[backend[@"pid"] intValue];int64_t boot=NGBoot();
        BOOL alive=pid>0 && (kill(pid,0)==0 || errno==EPERM);
        dispatch_async(dispatch_get_main_queue(),^{
            NGSystemBackdrop *s=weak;
            if (!s) return;
            s.backendReadPending=NO;
            [s applyBackend:backend ack:ack boot:boot alive:alive];
            if (s.backendReadAgain) {s.backendReadAgain=NO;[s scheduleBackendRead];}
        });
    });
}
- (void)applyBackend:(NSDictionary *)backend ack:(NSDictionary *)ack boot:(int64_t)boot alive:(BOOL)alive {
    if (_detached) return;
    pid_t pid=[backend[@"pid"] intValue];
    if ([backend[@"boot"] longLongValue]!=boot || ![backend[@"registered"] boolValue] || !alive) {
        _attached=NO;_hasFrame=NO;self.layer.filters=nil;self.layer.hidden=YES;if (_onFrame) _onFrame(NO);return;
    }
    if (_backendPID!=pid) {_backendPID=pid;_attached=NO;_hasFrame=NO;_failedToken=nil;self.layer.filters=nil;self.layer.hidden=YES;if (_onFrame) _onFrame(NO);}
    NSString *accepted=backend[@"tokens"][[NSString stringWithFormat:@"%lu",(unsigned long)_slot]];
    if (![accepted isEqualToString:_token]) return;
    if ([_failedToken isEqualToString:_token]) return;
    if (!_attached && !_detached && _lastPacket) {
        Class filterClass=NSClassFromString(@"CAFilter");SEL selector=NSSelectorFromString(@"filterWithType:");
        NSString *name=[NSString stringWithFormat:@"com.ning.glassswitchdock.dock.%lu",(unsigned long)_slot];
        id filter=[filterClass respondsToSelector:selector]?((id(*)(id,SEL,id))objc_msgSend)(filterClass,selector,name):nil;
        if (filter) {self.layer.filters=@[filter];_attached=YES;self.layer.hidden=_surfaceHidden;}
    }
    if ([ack[@"token"] isEqualToString:_token] && [ack[@"boot"] longLongValue]==boot && [ack[@"pid"] intValue]==_backendPID) {
        _hasFrame=[ack[@"success"] boolValue];
        if (!_hasFrame) {
            _failedToken=_token;_attached=NO;self.layer.filters=nil;self.layer.hidden=YES;
        }
        if (_onFrame) _onFrame(_hasFrame);
    }
}
- (void)setSurfaceHidden:(BOOL)hidden {_surfaceHidden=hidden;self.hidden=hidden;self.layer.hidden=hidden || !_attached;}
- (void)detach {
    if (_detached) return;_detached=YES;_attached=NO;_hasFrame=NO;self.layer.filters=nil;
    NSString *file=[NGStateDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"slot-%lu.plist",(unsigned long)_slot]];
    if (file.length) [NSFileManager.defaultManager removeItemAtPath:file error:NULL];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ning.glassswitchdock/dock-parameters"),NULL,NULL,true);
}
- (NSDictionary *)diagnostics {return @{@"slot":@(_slot),@"ready":@(_hasFrame),@"filterAttached":@(_attached),@"token":_token?:@""};}
@end
static void NGBackendChanged(CFNotificationCenterRef,void *,CFStringRef,const void *,CFDictionaryRef) {
    dispatch_async(dispatch_get_main_queue(),^{for (NGSystemBackdrop *s in NGSurfaces().allObjects) [s scheduleBackendRead];});
}
