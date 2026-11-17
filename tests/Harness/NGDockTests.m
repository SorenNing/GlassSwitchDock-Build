#import "NGHarness.h"
#import "NGSystemBackdrop.h"
#import "NGDockRender.h"
#import <objc/message.h>

static NSString *NGCase(Class cls,NSInteger style,NSString *suffix) {
    return [NSString stringWithFormat:@"dock.%@.%@.%@",NSStringFromClass(cls),style?@"glassifyProminentClear":@"theseusClear",suffix];
}
static NSDictionary *NGPacket(CGSize size,CGFloat scale,NSInteger style) {
    NSMutableDictionary *p=nil;
    if (!style) {
        id factory=[NSClassFromString(@"NGDockMaterialParameters") new];
        SEL s=NSSelectorFromString(@"packetWithSize:radius:scale:dark:");
        p=[((id(*)(id,SEL,CGSize,CGFloat,CGFloat,BOOL))objc_msgSend)(factory,s,size,30,scale,NO) mutableCopy];
    } else {
        CGFloat r=0,g=0,b=0,a=0;
        [[UIColor.secondarySystemFillColor resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]] getRed:&r green:&g blue:&b alpha:&a];
        p=[@{@"width":@(size.width),@"height":@(size.height),@"scale":@(scale),@"dark":@NO,@"style":@1,@"tint":@[@(r),@(g),@(b),@(a)]} mutableCopy];
    }
    p[@"radius"]=@30;return p;
}
static NSDictionary *NGDraw(NSDictionary *packet,id<MTLDevice> device,id<MTLCommandQueue> queue,NSUInteger phase,NSString *path) {
    NSUInteger w=(NSUInteger)ceil([packet[@"width"] doubleValue]*[packet[@"scale"] doubleValue]);
    NSUInteger h=(NSUInteger)ceil([packet[@"height"] doubleValue]*[packet[@"scale"] doubleValue]);
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> input=[device newTextureWithDescriptor:d];
    NSMutableData *pixels=[NSMutableData dataWithLength:w*h*4];uint8_t *b=(uint8_t *)pixels.mutableBytes;
    for (NSUInteger y=0;y<h;y++) for (NSUInteger x=0;x<w;x++) {
        NSUInteger i=(y*w+x)*4;BOOL check=((x/11+y/13+phase)%2)==0;
        b[i]=check?180:40;b[i+1]=check?60:160;b[i+2]=check?30:220;b[i+3]=255;
    }
    [input replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:b bytesPerRow:w*4];
    d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
    id<MTLTexture> output=[device newTextureWithDescriptor:d];
    id<MTLCommandBuffer> cb=[queue commandBuffer];BOOL encoded=NGDockEncode(cb,input,output,packet);
    [cb commit];[cb waitUntilCompleted];
    if (!encoded || cb.status!=MTLCommandBufferStatusCompleted) return @{@"ready":@NO,@"error":cb.error.description?:@"encoder rejected input"};
    [output getBytes:b bytesPerRow:w*4 fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    uint64_t hash=14695981039346656037ull;for (NSUInteger i=0;i<pixels.length;i++) hash=(hash^b[i])*1099511628211ull;
    CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context=CGBitmapContextCreate(b,w,h,8,w*4,cs,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGImageRef image=context?CGBitmapContextCreateImage(context):NULL;
    NSData *png=image?UIImagePNGRepresentation([UIImage imageWithCGImage:image]):nil;
    BOOL wrote=[png writeToFile:path atomically:YES];
    if (image) CGImageRelease(image);if (context) CGContextRelease(context);CGColorSpaceRelease(cs);
    return @{@"ready":@YES,@"checksum":[NSString stringWithFormat:@"%llu",(unsigned long long)hash],@"width":@(w),@"height":@(h),@"wrotePNG":@(wrote)};
}
extern void NGRunDockProtocolTests(NGRecorder *r);
void NGRunDockTests(NGRecorder *r,UIView *root,dispatch_block_t completion) {
    NGRunDockProtocolTests(r);
    // These tests exercise our actual encoder with supplied Metal textures.
    // Simulator cannot verify the private backboardd hookup or CA input extent.
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();id<MTLCommandQueue> queue=[device newCommandQueue];
    for (Class cls in @[SBDockView.class,SBFloatingDockPlatterView.class]) {
        for (NSInteger style=0;style<2;style++) {
            NGWritePreferences(NO,YES,style);
            SBDockView *dock=[[cls alloc] initWithFrame:CGRectMake(15,366,root.bounds.size.width-30,84)];[root addSubview:dock];
            CGFloat alpha=dock.backgroundView.alpha;NGRefreshFixtureDock(dock);
            [r check:dock.backgroundView.alpha==alpha name:NGCase(cls,style,@"unavailable_backend_preserves_native") evidence:@{@"alpha":@(dock.backgroundView.alpha)}];
            NSUInteger count=0;for (UIView *v in NGDescendants(dock)) if ([v isKindOfClass:NGSystemBackdrop.class]) count++;
            for (unsigned n=0;n<100;n++) NGRefreshFixtureDock(dock);
            NSUInteger after=0;for (UIView *v in NGDescendants(dock)) if ([v isKindOfClass:NGSystemBackdrop.class]) after++;
            [r check:count==after && count<=1 name:NGCase(cls,style,@"refresh_idempotent") evidence:@{@"before":@(count),@"after":@(after)}];
            CGPoint point=[dock.icon convertPoint:CGPointMake(10,10) toView:dock];
            [r check:[dock hitTest:point withEvent:nil]==dock.icon name:NGCase(cls,style,@"dock_icon_hit_test_preserved") evidence:@{}];
            NSDictionary *p=NGPacket(dock.backgroundView.bounds.size,1,style);
            NSString *a=[NGCase(cls,style,@"gpu_a") stringByAppendingPathExtension:@"png"];
            NSString *b=[NGCase(cls,style,@"gpu_b") stringByAppendingPathExtension:@"png"];
            NSDictionary *first=NGDraw(p,device,queue,0,[r.output stringByAppendingPathComponent:a]);
            NSDictionary *second=NGDraw(p,device,queue,1,[r.output stringByAppendingPathComponent:b]);
            [r check:[first[@"ready"] boolValue] && [second[@"ready"] boolValue] && [first[@"wrotePNG"] boolValue] && [second[@"wrotePNG"] boolValue] && ![first[@"checksum"] isEqual:second[@"checksum"]]
                 name:NGCase(cls,style,@"backdrop_change_changes_real_gpu_pixels") evidence:@{@"before":first,@"after":second,@"files":@[a,b],@"input":@"synthetic MTLTexture, no screenshots"}];
            NGRemoveDock(dock);
            [r check:dock.backgroundView.alpha==alpha name:NGCase(cls,style,@"disable_restores_background") evidence:@{}];
            [dock removeFromSuperview];
        }
    }
    completion();
}
