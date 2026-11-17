#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import "Bridge.h"
#import <Glassify/GLSGlassView.h>

// Declared separately to avoid depending on generated Swift header visibility.
@interface NGTheseusProbe : NSObject
+ (NSDictionary *)inspectSwitch:(UIView *)view;
+ (NSDictionary *)inspectClear:(UIView *)view;
+ (NSDictionary *)snapshot:(UIView *)view path:(NSString *)path;
+ (BOOL)activate:(UIView *)view;
+ (BOOL)drag:(UIView *)view toOn:(BOOL)on;
+ (NSDictionary *)settings;
@end

@interface NGRecorder : NSObject
@property(nonatomic, readonly) NSMutableArray<NSDictionary *> *checks;
@property(nonatomic, readonly) NSString *output;
@property(nonatomic, readonly) NSUInteger failures;
- (instancetype)initWithOutput:(NSString *)output;
- (void)check:(BOOL)success name:(NSString *)name evidence:(id)evidence;
- (void)capture:(UIView *)view name:(NSString *)name;
- (void)finish;
@end

@interface NGEventSpy : NSObject
@property(nonatomic) NSUInteger count;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *values;
- (void)changed:(UISwitch *)sender;
@end

@interface NGPatternView : UIView
@property(nonatomic) NSUInteger phase;
@end

// No real SpringBoard framework is linked; these provide recognizable fixture identities.
@interface SBDockView : UIView
@property(nonatomic, strong) UIView *backgroundView;
@property(nonatomic, strong) UIButton *icon;
@end
@interface SBFloatingDockPlatterView : SBDockView
@end

FOUNDATION_EXPORT NSArray<UIView *> *NGDescendants(UIView *root);
FOUNDATION_EXPORT NSArray<UIView *> *NGOriginalSwitches(UIView *root);
FOUNDATION_EXPORT UIView *NGSwitchComponent(UISwitch *source, UIView *scope, NSInteger style);
FOUNDATION_EXPORT void NGPump(NSTimeInterval seconds);
FOUNDATION_EXPORT BOOL NGReadOn(id control);
FOUNDATION_EXPORT void NGWritePreferences(BOOL enabledSwitch, BOOL enabledDock, NSInteger dockStyle);
FOUNDATION_EXPORT void NGRunSwitchTests(NGRecorder *recorder, UIView *root);
FOUNDATION_EXPORT void NGRunDockTests(NGRecorder *recorder, UIView *root, dispatch_block_t completion);
FOUNDATION_EXPORT void NGRunResourceTests(NGRecorder *recorder);
FOUNDATION_EXPORT void NGRefreshFixtureDock(UIView *dock);
