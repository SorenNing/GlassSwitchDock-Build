#pragma once
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdint.h>
#define NG_DOCK_FILTER_PREFIX "com.ning.glassswitchdock.dock."
#define NG_DOCK_PARAMETERS_CHANGED "com.ning.glassswitchdock/dock-parameters"
#define NG_DOCK_BACKEND_READY "com.ning.glassswitchdock/dock-backend-ready"
#define NG_DOCK_SLOTS 8

// Only small material parameters cross processes. No image, screenshot or
// foreign library is shared; source and destination textures belong to CA.
FOUNDATION_EXPORT NSString *NGDockStateDirectory(void);
FOUNDATION_EXPORT NSDictionary *NGDockReadSlot(unsigned slot);
FOUNDATION_EXPORT BOOL NGDockEncode(id<MTLCommandBuffer> commands, id<MTLTexture> source,
                                   id<MTLTexture> destination, NSDictionary *packet);
FOUNDATION_EXPORT void NGDockRendererReset(void);
