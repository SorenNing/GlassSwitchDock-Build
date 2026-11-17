#pragma once
#include <stddef.h>

#define NG_DOCK_LOGICAL_STATE_PATH "/var/mobile/Library/Preferences/com.ning.glassswitchdock.render"
typedef const char *(*NGDockRootPathResolver)(const char *);

// Same path policy for both processes; never silently fall back to a different
// namespace if RootHide conversion fails. The resolver owns the returned bytes.
static inline const char *NGDockStateCString(int rootHide, NGDockRootPathResolver resolve) {
    if (!rootHide) return NG_DOCK_LOGICAL_STATE_PATH;
    if (!resolve) return NULL;
    const char *physical = resolve(NG_DOCK_LOGICAL_STATE_PATH);
    return physical && physical[0] == '/' ? physical : NULL;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#if defined(NG_ROOTHIDE) && !defined(NG_TESTING)
#import <roothide/roothide.h>
#endif
static inline NSString *NGDockSharedStateDirectory(void) {
#if defined(NG_TESTING)
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"glassswitchdock-render"];
#elif defined(NG_ROOTHIDE)
    const char *physical = NGDockStateCString(1, jbroot);
    return physical ? [NSString stringWithUTF8String:physical] : nil;
#else
    return [NSString stringWithUTF8String:NGDockStateCString(0, NULL)];
#endif
}
#endif
