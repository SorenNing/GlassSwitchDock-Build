#import "NGHarness.h"
#import <objc/message.h>

static id<MTLRenderPipelineState> NGPipeline(NGRecorder *r, id<MTLDevice> device, id<MTLLibrary> library,
                                           NSString *prefix, NSString *vertex, NSString *fragment) {
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [library newFunctionWithName:vertex]; desc.fragmentFunction = [library newFunctionWithName:fragment];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    NSError *error = nil;
    id<MTLRenderPipelineState> state = desc.vertexFunction && desc.fragmentFunction ? [device newRenderPipelineStateWithDescriptor:desc error:&error] : nil;
    [r check:state != nil name:[NSString stringWithFormat:@"resource.%@.pipeline.%@", prefix, fragment]
       evidence:@{@"vertex": vertex, @"fragment": fragment, @"error": error.description ?: @"none"}];
    return state;
}

void NGRunResourceTests(NGRecorder *r) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    [r check:device != nil name:@"resource.metal_device_required" evidence:@{@"device": device.name ?: @"unavailable"}];
    if (!device) return;
    NSArray<NSBundle *> *bundles = @[(id)NGBundleResources() ?: NSNull.null, (id)NGBundleGlassify() ?: NSNull.null];
    NSArray *names = @[@"theseus", @"glassify"];
    NSMutableArray *libraries = [NSMutableArray array];
    for (NSUInteger index = 0; index < 2; index++) {
        NSBundle *bundle = bundles[index] == (id)NSNull.null ? nil : bundles[index];
        NSURL *url = [bundle URLForResource:@"default" withExtension:@"metallib"];
        NSError *error = nil;
        id<MTLLibrary> library = url ? [device newLibraryWithURL:url error:&error] : nil;
        [r check:bundle && url && library name:[NSString stringWithFormat:@"resource.%@.load_original_metallib", names[index]]
           evidence:@{@"bundle": bundle.bundlePath ?: @"missing", @"metallib": url.path ?: @"missing", @"functions": library.functionNames ?: @[], @"error": error.description ?: @"none"}];
        [libraries addObject:library ?: (id)NSNull.null];
    }
    id<MTLLibrary> theseus = libraries[0] == NSNull.null ? nil : libraries[0];
    id<MTLLibrary> glassify = libraries[1] == NSNull.null ? nil : libraries[1];
    if (theseus) for (NSString *fragment in @[@"gaussianBlurHorizontal", @"gaussianBlurVertical", @"glassRenderFragment"])
        NGPipeline(r, device, theseus, @"theseus", @"vertexPassthrough", fragment);
    if (!glassify) return;
    NGPipeline(r, device, glassify, @"glassify", @"gls_fullscreen_vertex", @"gls_glass_background");
    // This is the vendor's intended Simulator path without framebuffer fetch.
    NGPipeline(r, device, glassify, @"glassify", @"gls_fullscreen_vertex", @"gls_glass_highlight_texture");
    id<MTLComputePipelineState> downsample = nil;
    for (NSString *name in @[@"gls_downsample13", @"gls_composite_underlay", @"gls_composite_veil"]) {
        NSError *error = nil;
        id<MTLFunction> function = [glassify newFunctionWithName:name];
        id<MTLComputePipelineState> state = function ? [device newComputePipelineStateWithFunction:function error:&error] : nil;
        [r check:state != nil name:[@"resource.glassify.compute." stringByAppendingString:name]
           evidence:@{@"function": name, @"error": error.description ?: @"none"}];
        if ([name isEqualToString:@"gls_downsample13"]) downsample = state;
    }
    if (!downsample) return;
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    desc.storageMode = MTLStorageModeShared; desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> source = [device newTextureWithDescriptor:desc];
    desc.width = 4; desc.height = 4; desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    id<MTLTexture> destination = [device newTextureWithDescriptor:desc];
    uint8_t input[8*8*4];
    for (NSUInteger pixel = 0; pixel < 64; pixel++) { input[pixel*4] = 64; input[pixel*4+1] = 128; input[pixel*4+2] = 192; input[pixel*4+3] = 255; }
    [source replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:input bytesPerRow:8*4];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer]; id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:downsample]; [encoder setTexture:source atIndex:0]; [encoder setTexture:destination atIndex:1];
    [encoder dispatchThreads:MTLSizeMake(4,4,1) threadsPerThreadgroup:MTLSizeMake(4,4,1)]; [encoder endEncoding];
    [command commit]; [command waitUntilCompleted];
    uint8_t output[4*4*4] = {0};
    [destination getBytes:output bytesPerRow:4*4 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
    BOOL pixelsCorrect = source && destination;
    NSUInteger maxError = 0;
    for (NSUInteger pixel = 0; pixel < 16; pixel++) for (NSUInteger channel = 0; channel < 4; channel++) {
        NSUInteger delta = (NSUInteger)abs((int)output[pixel*4+channel] - (int)input[channel]); maxError = MAX(maxError, delta);
        if (delta > 1) pixelsCorrect = NO;
    }
    [r check:command.status == MTLCommandBufferStatusCompleted && pixelsCorrect name:@"resource.glassify.actual_shader_execution_readback"
       evidence:@{@"kernel": @"gls_downsample13", @"commandStatus": @(command.status), @"maxChannelError": @(maxError),
                  @"firstPixel": @[@(output[0]), @(output[1]), @(output[2]), @(output[3])], @"expected": @[@64,@128,@192,@255], @"error": command.error.description ?: @"none"}];
    Class rendererClass = NSClassFromString(@"GLSRenderer");
    id renderer = rendererClass ? ((id (*)(id,SEL))objc_msgSend)(rendererClass, NSSelectorFromString(@"shared")) : nil;
    [r check:renderer != nil name:@"resource.glassify.actual_renderer_initializes" evidence:@{@"class": renderer ? NSStringFromClass([renderer class]) : @"unavailable"}];
}
