#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSBundle * _Nullable NGBundleResources(void);
FOUNDATION_EXPORT NSBundle * _Nullable NGBundleGlassify(void);
FOUNDATION_EXPORT NSArray<NSString *> *NGPreferencePaths(void);
FOUNDATION_EXPORT NSDictionary *NGReadPreferences(void);
FOUNDATION_EXPORT BOOL NGStorePreference(NSString *key, id value);
FOUNDATION_EXPORT void NGPreferencesReload(void);
FOUNDATION_EXPORT BOOL NGSwitchEnabled(void);
FOUNDATION_EXPORT BOOL NGDockEnabled(void);
FOUNDATION_EXPORT NSInteger NGDockStyle(void);
FOUNDATION_EXPORT void NGRefreshSwitch(UISwitch *source);
FOUNDATION_EXPORT void NGRefreshAllSwitches(void);
FOUNDATION_EXPORT void NGRemoveSwitch(UISwitch *source);
FOUNDATION_EXPORT void NGSyncSwitch(UISwitch *source, BOOL animated);
FOUNDATION_EXPORT BOOL NGHandleSwitchAlpha(UISwitch *source, CGFloat alpha);
FOUNDATION_EXPORT void NGRefreshDock(UIView *dock);
FOUNDATION_EXPORT void NGRefreshDocks(void);
FOUNDATION_EXPORT void NGRemoveDock(UIView *dock);
FOUNDATION_EXPORT void NGRefreshAll(void);
#ifdef NG_TESTING
FOUNDATION_EXPORT NSDictionary *NGDockDiagnostics(UIView *dock);
#endif

@protocol NGSwitchComponent <NSObject>
@property(nonatomic,copy,nullable) void (^onChanged)(BOOL value);
@property(nonatomic,getter=isOn) BOOL on;
- (void)setOn:(BOOL)value animated:(BOOL)animated;
@end
@protocol NGGlassComponent <NSObject>
@property(nonatomic,copy,nullable) void (^onReady)(void);
- (void)configureWithRadius:(CGFloat)radius source:(UIView *)source excluded:(NSArray<UIView *> *)excluded;
- (void)invalidateBackdrop;
- (void)setRenderingActive:(BOOL)active;
@end
NS_ASSUME_NONNULL_END
