#import "NGHarness.h"
#import "NGDockRender.h"
#include <math.h>

void NGRunDockProtocolTests(NGRecorder *r) {
    NSString *dir=NGDockStateDirectory();
    // NG_TESTING redirects this path to the fixture's temporary directory.
    if ([dir hasPrefix:@"/var/mobile/"]) {
        [r check:NO name:@"dock.protocol.isolated_directory" evidence:@{@"path":dir}];return;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path=[dir stringByAppendingPathComponent:@"slot-7.plist"];
    NSData *saved=[NSData dataWithContentsOfFile:path];
    NSMutableDictionary *valid=[@{@"schema":@1,@"slot":@7,@"token":@"protocol-fixture",@"active":@YES,@"width":@300,@"height":@84,@"scale":@2,@"radius":@30,@"style":@1,@"pid":@123,@"tint":@[@0.2,@0.3,@0.4,@0.5]} mutableCopy];
    BOOL wrote=[valid writeToFile:path atomically:YES];
    [r check:wrote && NGDockReadSlot(7)!=nil name:@"dock.protocol.valid_glassify_parameters" evidence:@{}];
    NSArray *invalid=@[@{@"width":@0},@{@"height":@(-1)},@{@"scale":@5},@{@"radius":@99},@{@"style":@2},@{@"slot":@6},@{@"schema":@2},@{@"active":@NO},@{@"pid":@"123"},@{@"tint":@[@0,@0,@0,@2]}];
    NSUInteger index=0;
    for (NSDictionary *mutation in invalid) {
        NSMutableDictionary *p=[valid mutableCopy];[p addEntriesFromDictionary:mutation];
        BOOL ok=[p writeToFile:path atomically:YES];
        [r check:ok && NGDockReadSlot(7)==nil name:[NSString stringWithFormat:@"dock.protocol.reject_invalid_%lu",(unsigned long)index++] evidence:mutation];
    }
    NSMutableDictionary *clear=[valid mutableCopy];clear[@"style"]=@0;clear[@"uniforms"]=[NSMutableData dataWithLength:1152];
    [clear writeToFile:path atomically:YES];
    [r check:NGDockReadSlot(7)!=nil name:@"dock.protocol.valid_theseus_uniform_layout" evidence:@{@"bytes":@1152}];
    clear[@"uniforms"]=[NSMutableData dataWithLength:1151];[clear writeToFile:path atomically:YES];
    [r check:NGDockReadSlot(7)==nil name:@"dock.protocol.reject_truncated_uniforms" evidence:@{}];
    [r check:NGDockReadSlot(8)==nil && NGDockReadSlot(UINT_MAX)==nil name:@"dock.protocol.reject_out_of_range_slots" evidence:@{}];
    if (saved) [saved writeToFile:path atomically:YES];else [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
}
