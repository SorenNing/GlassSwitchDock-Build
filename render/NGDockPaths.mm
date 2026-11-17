#import "NGDockRender.h"
#import "NGDockStatePath.h"
#import <dlfcn.h>
#include <limits.h>
#include <stdlib.h>
#include <math.h>

NSString *NGDockStateDirectory(void) {
    return NGDockSharedStateDirectory();
}
NSDictionary *NGDockReadSlot(unsigned slot) {
    if (slot>=NG_DOCK_SLOTS) return nil;
    NSString *statePath=NGDockStateDirectory();if (!statePath.length) return nil;
    NSString *name=[NSString stringWithFormat:@"slot-%u.plist",slot];
    NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:[statePath stringByAppendingPathComponent:name]];
    if (![p isKindOfClass:NSDictionary.class] || [p[@"schema"] unsignedIntValue]!=1 ||
        [p[@"slot"] unsignedIntValue]!=slot || ![p[@"token"] isKindOfClass:NSString.class] ||
        [p[@"token"] length]>128 || ![p[@"active"] boolValue]) return nil;
    for (NSString *key in @[@"width",@"height",@"scale",@"radius",@"style",@"pid"])
        if (![p[key] isKindOfClass:NSNumber.class]) return nil;
    double w=[p[@"width"] doubleValue],h=[p[@"height"] doubleValue],scale=[p[@"scale"] doubleValue],radius=[p[@"radius"] doubleValue];
    NSInteger style=[p[@"style"] integerValue];
    if (!isfinite(w) || !isfinite(h) || !isfinite(scale) || !isfinite(radius) || w<=0 || h<=0 || scale<=0 || scale>4 ||
        w*scale>8192 || h*scale>8192 || radius<0 || radius>fmin(w,h)/2 || (style!=0 && style!=1)) return nil;
    if (style==0 && (![p[@"uniforms"] isKindOfClass:NSData.class] || [p[@"uniforms"] length]!=1152)) return nil;
    if (style==1) {
        NSArray *tint=p[@"tint"];if (![tint isKindOfClass:NSArray.class] || tint.count!=4) return nil;
        for (id value in tint) if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || [value doubleValue]<0 || [value doubleValue]>1) return nil;
    }
    return p;
}
