#pragma once
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface NGSystemBackdrop : UIView
@property(nonatomic,copy,nullable) void (^onFrame)(BOOL success);
@property(nonatomic,readonly) BOOL hasFrame;
@property(nonatomic,readonly) NSUInteger slot;
+ (BOOL)isAvailable;
- (BOOL)configureWithRadius:(CGFloat)radius style:(NSInteger)style;
- (void)setSurfaceHidden:(BOOL)hidden;
- (void)detach;
- (NSDictionary *)diagnostics;
@end
NS_ASSUME_NONNULL_END
