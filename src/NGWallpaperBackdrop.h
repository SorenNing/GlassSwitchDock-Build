#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Hidden, capture-only sibling. Its layer explicitly draws a wallpaper bitmap;
// it never captures the Dock, icons or either glass engine.
@interface NGWallpaperBackdrop : UIView
@property(nonatomic,readonly) BOOL hasFrame;
@property(nonatomic) NSTimeInterval captureInterval;
@property(nonatomic,readonly) NSUInteger generation;
@property(nonatomic,readonly) NSUInteger captureAttempts;
@property(nonatomic,readonly) NSDictionary *diagnostics;
- (BOOL)updateForDock:(UIView *)dock background:(UIView *)background force:(BOOL)force;
@end
NS_ASSUME_NONNULL_END
