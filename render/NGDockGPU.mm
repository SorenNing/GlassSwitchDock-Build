#import "NGDockRender.h"
#import "NGTheseusParams.h"
#import "glassify/glass_inputs.h"
#import "glassify/pack.h"
#import <dlfcn.h>
#include <math.h>
#include <mutex>
#include <map>
#include <string>
#include <vector>
#include <limits.h>
#include <stdlib.h>

// All material code comes from the two engines already present in this project.
// This adapter only submits their pipelines to CA's command buffer.
namespace {
std::recursive_mutex &Lock(void) {static auto *value=new std::recursive_mutex;return *value;}
id<MTLDevice> Device;
id<MTLLibrary> TheseusLibrary,GlassifyLibrary,TransportLibrary;
NSMutableDictionary<NSString *,id<MTLRenderPipelineState>> *Pipelines;
struct FrameTextures {
    std::map<std::string,id<MTLTexture>> textures;
    id<MTLDevice> device=nil;
    bool busy=false;
};
static thread_local FrameTextures *CurrentFrame=nullptr;
FrameTextures *AcquireFrame(id<MTLDevice> device) {
    // Eight possible Dock surfaces, up to three CA frames in flight each.
    static auto *frames=new FrameTextures[24];
    for (unsigned n=0;n<24;n++) if (!frames[n].busy) {
        if (frames[n].device!=device) {frames[n].textures.clear();frames[n].device=device;}
        frames[n].busy=true;return &frames[n];
    }
    return nullptr;
}
void ReleaseFrame(FrameTextures *frame) {
    std::lock_guard<std::recursive_mutex> guard(Lock());
    if (frame) frame->busy=false;
}
std::map<std::string,id<MTLBuffer>> &Weights(void) {static auto *value=new std::map<std::string,id<MTLBuffer>>;return *value;}
id<MTLTexture> Empty;
static char ResourceAnchor;
NSString *ResourceDirectory(void) {
#ifdef NG_TESTING
    return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"GlassSwitchDockResources.bundle"];
#else
    Dl_info i={};char path[PATH_MAX]={};
    if (!dladdr(&ResourceAnchor,&i) || !i.dli_fname) return nil;
    NSString *full=[NSString stringWithUTF8String:realpath(i.dli_fname,path)?:i.dli_fname];
    for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries/GlassSwitchDockRender.dylib",
                               @"/usr/lib/TweakInject/GlassSwitchDockRender.dylib"]) {
        if ([full hasSuffix:suffix]) return [[full substringToIndex:full.length-suffix.length]
          stringByAppendingPathComponent:@"Library/Application Support/GlassSwitchDock/GlassSwitchDockResources.bundle"];
    }
    return nil;
#endif
}
bool Prepare(id<MTLDevice> device) {
    if (Device==device && TheseusLibrary && GlassifyLibrary && TransportLibrary && Empty) return true;
    Device=device;Weights().clear();Pipelines=[NSMutableDictionary dictionary];Empty=nil;
    NSString *dir=ResourceDirectory();if (!dir) return false;
    TheseusLibrary=[device newLibraryWithFile:[dir stringByAppendingPathComponent:@"default.metallib"] error:NULL];
    GlassifyLibrary=[device newLibraryWithFile:[dir stringByAppendingPathComponent:@"GlassifyShaders.bundle/default.metallib"] error:NULL];
    TransportLibrary=[device newLibraryWithFile:[dir stringByAppendingPathComponent:@"DockTransport.bundle/default.metallib"] error:NULL];
    if (!TheseusLibrary || !GlassifyLibrary || !TransportLibrary) return false;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    Empty=[device newTextureWithDescriptor:d];uint32_t zero=0;
    [Empty replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&zero bytesPerRow:4];
    return Empty!=nil;
}
id<MTLRenderPipelineState> Pipeline(bool glassify,NSString *fragment,MTLPixelFormat format,bool blend=false) {
    NSString *key=[NSString stringWithFormat:@"%d-%@-%lu-%d",glassify,fragment,(unsigned long)format,blend];
    id<MTLRenderPipelineState> p=Pipelines[key];if (p) return p;
    id<MTLLibrary> lib=glassify?GlassifyLibrary:TheseusLibrary;
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.vertexFunction=[lib newFunctionWithName:glassify?@"gls_fullscreen_vertex":@"vertexPassthrough"];
    d.fragmentFunction=[lib newFunctionWithName:fragment];d.colorAttachments[0].pixelFormat=format;
    if (blend) {
        d.colorAttachments[0].blendingEnabled=YES;
        d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;
        d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
        d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
        d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    }
    if (!d.vertexFunction || !d.fragmentFunction) return nil;
    p=[Device newRenderPipelineStateWithDescriptor:d error:NULL];if (p) Pipelines[key]=p;return p;
}
id<MTLTexture> Texture(const char *name,NSUInteger w,NSUInteger h,MTLPixelFormat format,bool mip=false) {
    if (!CurrentFrame) return nil;
    id<MTLTexture> t=CurrentFrame->textures[name];
    if (t && t.width==w && t.height==h && t.pixelFormat==format && (t.mipmapLevelCount>1)==mip) return t;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:mip];
    d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget|MTLTextureUsagePixelFormatView|MTLTextureUsageShaderWrite;
    t=[Device newTextureWithDescriptor:d];CurrentFrame->textures[name]=t;return t;
}
void Quad(id<MTLRenderCommandEncoder> e) {
    const float v[]={-1,-1,0,1, 1,-1,1,1, -1,1,0,0, 1,1,1,0};
    [e setVertexBytes:v length:sizeof(v) atIndex:0];
}
id<MTLRenderCommandEncoder> Pass(id<MTLCommandBuffer> cb,id<MTLTexture> dst,id<MTLRenderPipelineState> p) {
    if (!p || !dst) return nil;
    MTLRenderPassDescriptor *d=[MTLRenderPassDescriptor renderPassDescriptor];
    d.colorAttachments[0].texture=dst;d.colorAttachments[0].loadAction=MTLLoadActionClear;
    d.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);d.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:d];[e setRenderPipelineState:p];return e;
}
id<MTLTexture> Blur(id<MTLCommandBuffer> cb,id<MTLTexture> source,float sigma,const char *tag) {
    if (!(sigma>0.01f)) return source;
    unsigned radius=(unsigned)ceilf(sigma*3);if (radius>4096) return nil;
    std::string key=std::string(tag)+"-"+std::to_string(radius)+"-"+std::to_string(sigma);
    id<MTLBuffer> weights=Weights()[key];
    if (!weights) {
        std::vector<float> values(radius+1);double sum=0;
        for (unsigned n=0;n<=radius;n++) {values[n]=expf(-(float)(n*n)/(2*sigma*sigma));sum+=values[n]*(n?2:1);}
        for (float &v:values) v/=sum;
        weights=[Device newBufferWithBytes:values.data() length:values.size()*4 options:MTLResourceStorageModeShared];
        if (Weights().size()>64) Weights().clear();Weights()[key]=weights;
    }
    std::string a=std::string(tag)+"a",b=std::string(tag)+"b";
    id<MTLTexture> scratch=Texture(a.c_str(),source.width,source.height,MTLPixelFormatBGRA8Unorm);
    id<MTLTexture> result=Texture(b.c_str(),source.width,source.height,MTLPixelFormatBGRA8Unorm,true);
    struct alignas(8) { vector_float2 texel; int32_t radius,encoded; } u={{1.f/source.width,1.f/source.height},(int32_t)radius,1};
    for (int n=0;n<2;n++) {
        id<MTLTexture> dst=n?result:scratch;
        id<MTLRenderCommandEncoder> e=Pass(cb,dst,Pipeline(false,n?@"gaussianBlurHorizontal":@"gaussianBlurVertical",dst.pixelFormat));
        if (!e) return nil;Quad(e);
        [e setFragmentTexture:n?scratch:source atIndex:0];[e setFragmentBytes:&u length:sizeof(u) atIndex:0];
        [e setFragmentBuffer:weights offset:0 atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];
    }
    return result;
}
}

namespace {
id<MTLTexture> Transport(id<MTLCommandBuffer> cb,id<MTLTexture> input,NSUInteger width,NSUInteger height) {
    id<MTLTexture> output=Texture("normalized-source",width,height,MTLPixelFormatBGRA8Unorm);
    NSString *key=@"transport-copy";id<MTLRenderPipelineState> pipeline=Pipelines[key];
    if (!pipeline) {
        MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
        d.vertexFunction=[TransportLibrary newFunctionWithName:@"ng_transport_vertex"];
        d.fragmentFunction=[TransportLibrary newFunctionWithName:@"ng_transport_copy"];
        d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        pipeline=[Device newRenderPipelineStateWithDescriptor:d error:NULL];
        if (pipeline) Pipelines[key]=pipeline;
    }
    id<MTLRenderCommandEncoder> e=Pass(cb,output,pipeline);if (!e) return nil;
    [e setFragmentTexture:input atIndex:0];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];return output;
}
bool Pyramid(id<MTLCommandBuffer> cb,id<MTLTexture> input,id<MTLTexture> output) {
    id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];if (!blit) return false;
    [blit copyFromTexture:input sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
         sourceSize:MTLSizeMake(input.width,input.height,1) toTexture:output destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[blit endEncoding];
    static NSString *key=@"glassify-downsample13";
    id<MTLComputePipelineState> pipeline=(id)Pipelines[key];
    if (!pipeline) {
        id<MTLFunction> f=[GlassifyLibrary newFunctionWithName:@"gls_downsample13"];
        if (f) pipeline=[Device newComputePipelineStateWithFunction:f error:NULL];
        if (pipeline) Pipelines[key]=(id)pipeline;
    }
    if (!pipeline) return false;
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];if (!e) return false;
    [e setComputePipelineState:pipeline];
    for (NSUInteger n=1;n<output.mipmapLevelCount;n++) {
        id<MTLTexture> a=[output newTextureViewWithPixelFormat:output.pixelFormat textureType:MTLTextureType2D levels:NSMakeRange(n-1,1) slices:NSMakeRange(0,1)];
        id<MTLTexture> b=[output newTextureViewWithPixelFormat:output.pixelFormat textureType:MTLTextureType2D levels:NSMakeRange(n,1) slices:NSMakeRange(0,1)];
        [e setTexture:a atIndex:0];[e setTexture:b atIndex:1];
        NSUInteger w=pipeline.threadExecutionWidth,h=MAX((NSUInteger)1,pipeline.maxTotalThreadsPerThreadgroup/w);
        [e dispatchThreadgroups:MTLSizeMake((b.width+w-1)/w,(b.height+h-1)/h,1) threadsPerThreadgroup:MTLSizeMake(w,h,1)];
    }
    [e endEncoding];return true;
}
bool DrawTheseus(id<MTLCommandBuffer> cb,id<MTLTexture> src,id<MTLTexture> dst,NSDictionary *p) {
    NSData *bytes=p[@"uniforms"];
    if (![bytes isKindOfClass:NSData.class] || bytes.length!=sizeof(NGTheseusParams)) return false;
    NGTheseusParams u;memcpy(&u,bytes.bytes,sizeof(u));
    if (fabsf(u.viewSize.x-dst.width)>1 || fabsf(u.viewSize.y-dst.height)>1) return false;
    float pixelsPerPoint=src.width/[p[@"width"] floatValue];
    float fine=[p[@"fineSigma"] floatValue],coarse=[p[@"coarseSigma"] floatValue],fill=[p[@"fillSigma"] floatValue];
    if (!isfinite(pixelsPerPoint) || pixelsPerPoint<=0 || !isfinite(fine) || !isfinite(coarse) || !isfinite(fill)) return false;
    id<MTLTexture> detail=Blur(cb,src,fine*pixelsPerPoint,"fine");if (!detail) return false;
    // Original coarse/fill blurs use quarter-resolution mip views when large.
    id<MTLTexture> quarter=nil;
    if (detail.mipmapLevelCount>2) {
        id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];[blit generateMipmapsForTexture:detail];[blit endEncoding];
        quarter=[detail newTextureViewWithPixelFormat:detail.pixelFormat textureType:MTLTextureType2D levels:NSMakeRange(2,1) slices:NSMakeRange(0,1)];
    }
    id<MTLTexture> coarseTexture=detail,fillTexture=detail;
    bool quarterCoarse=coarse*pixelsPerPoint>=8;
    if (coarse>fine+0.01f) {
        id<MTLTexture> base=quarterCoarse&&quarter?quarter:detail;
        coarseTexture=Blur(cb,base,sqrtf(fmaxf(coarse*coarse-fine*fine,0))*pixelsPerPoint/(base==quarter?4:1),"coarse");
    }
    if (quarter) {
        id<MTLTexture> base=quarterCoarse&&coarseTexture!=detail?coarseTexture:quarter;
        float from=base==coarseTexture?coarse:fine;
        fillTexture=Blur(cb,base,sqrtf(fmaxf(fill*fill-from*from,0))*pixelsPerPoint/4,"fill");
    }
    if (!coarseTexture || !fillTexture) return false;
    id<MTLRenderCommandEncoder> e=Pass(cb,dst,Pipeline(false,@"glassRenderFragment",dst.pixelFormat));if (!e) return false;
    Quad(e);[e setFragmentBytes:&u length:sizeof(u) atIndex:0];
    const float merged[64]={};[e setFragmentBytes:merged length:sizeof(merged) atIndex:1];
    [e setFragmentTexture:detail atIndex:0];[e setFragmentTexture:src atIndex:1];[e setFragmentTexture:Empty atIndex:2];
    [e setFragmentTexture:coarseTexture atIndex:3];[e setFragmentTexture:fillTexture atIndex:4];
    [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];return true;
}
bool DrawGlassify(id<MTLCommandBuffer> cb,id<MTLTexture> src,id<MTLTexture> dst,NSDictionary *p) {
    using namespace glassify;
    float width=[p[@"width"] floatValue],height=[p[@"height"] floatValue],scale=[p[@"scale"] floatValue],radius=[p[@"radius"] floatValue];
    if (width<=0 || height<=0 || scale<=0 || fabsf(ceilf(width*scale)-dst.width)>1 || fabsf(ceilf(height*scale)-dst.height)>1) return false;
    Appearance appearance=[p[@"dark"] boolValue]?Appearance::Dark:Appearance::Light;
    // The established Prominent Clear setup, including secondarySystemFill.
    GlassInputs inputs=glassInputsFor(GlassStyle::Clear,appearance,width,height,-1.f,Frost::Automatic);
    NSArray *tint=p[@"tint"];if (tint.count!=4) return false;
    float rgba[4];for (unsigned n=0;n<4;n++) rgba[n]=[tint[n] floatValue];setTint(inputs,appearance,rgba);
    ShapeElement element={width/2,height/2,width,height,radius,0.f};
    PackContext ctx;ctx.ptToPx=scale;ctx.elements=&element;ctx.elementCount=1;
    ctx.backdropWidth=width;ctx.backdropHeight=height;ctx.backdropPxPerPt=src.width/width;
    id<MTLTexture> pyramid=Texture("glassify-pyramid",src.width,src.height,MTLPixelFormatBGRA8Unorm,true);
    if (!pyramid || src.pixelFormat!=MTLPixelFormatBGRA8Unorm) return false;
    if (!Pyramid(cb,src,pyramid)) return false;
    ctx.backdropMaxLod=pyramid.mipmapLevelCount-1;
    GLSGlassUniforms u;GLSElement elements[GLS_MAX_ELEMENTS]={};packUniforms(inputs,ctx,u);packElements(ctx,elements);
    GlowState glow;glow.dark=appearance==Appearance::Dark;packGlow(glow,u);
    const float surface[]={width,height,0,0};
    auto bind=[&](id<MTLRenderCommandEncoder> e) {
        [e setVertexBytes:surface length:sizeof(surface) atIndex:0];
        [e setFragmentBytes:&u length:sizeof(u) atIndex:0];[e setFragmentBytes:elements length:sizeof(elements) atIndex:1];
        [e setFragmentTexture:pyramid atIndex:0];[e setFragmentTexture:Empty atIndex:2];[e setFragmentTexture:Empty atIndex:3];[e setFragmentTexture:Empty atIndex:4];
    };
    // Texture-based highlight is the vendor's own alternative to framebuffer fetch.
    id<MTLTexture> off=Texture("glassify-face",dst.width,dst.height,dst.pixelFormat);
    id<MTLRenderCommandEncoder> e=Pass(cb,off,Pipeline(true,@"gls_glass_background",dst.pixelFormat,true));if (!e) return false;
    bind(e);[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
    e=Pass(cb,dst,Pipeline(true,@"gls_glass_highlight_texture",dst.pixelFormat));if (!e) return false;
    bind(e);[e setFragmentTexture:off atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];return true;
}
}
BOOL NGDockEncode(id<MTLCommandBuffer> commands,id<MTLTexture> source,id<MTLTexture> destination,NSDictionary *packet) {
    std::lock_guard<std::recursive_mutex> guard(Lock());
    if (!commands || !source || !destination || source==destination || source.device!=destination.device || commands.device!=source.device ||
        !source.width || !source.height || !(destination.usage&MTLTextureUsageRenderTarget) || !Prepare(source.device)) return NO;
    // CA can have several command buffers in flight. Each owns all writable
    // intermediate textures until its GPU completion; CPU serialization alone
    // would allow another frame to overwrite them prematurely.
    float width=[packet[@"width"] floatValue],height=[packet[@"height"] floatValue],scale=[packet[@"scale"] floatValue];
    if (!isfinite(width) || !isfinite(height) || !isfinite(scale) || width<=0 || height<=0 || scale<=0 ||
        width*scale>8192 || height*scale>8192 || fabsf(ceilf(width*scale)-destination.width)>1 || fabsf(ceilf(height*scale)-destination.height)>1 ||
        source.width!=destination.width || source.height!=destination.height) return NO;
    FrameTextures *frame=AcquireFrame(source.device);if (!frame) return NO;
    FrameTextures *previous=CurrentFrame;CurrentFrame=frame;
    BOOL result=NO;
    @try {
        // Sampling stays in normalized texture coordinates; no screen capture.
        id<MTLTexture> input=Transport(commands,source,source.width,source.height);
        if (input && [packet[@"style"] integerValue]==0) result=DrawTheseus(commands,input,destination,packet);
        else if (input) result=DrawGlassify(commands,input,destination,packet);
    } @finally {
        CurrentFrame=previous;
        [commands addCompletedHandler:^(id<MTLCommandBuffer>){ ReleaseFrame(frame); }];
    }
    return result;
}
void NGDockRendererReset(void) {
    std::lock_guard<std::recursive_mutex> guard(Lock());
    Weights().clear();Pipelines=nil;TheseusLibrary=nil;GlassifyLibrary=nil;TransportLibrary=nil;Empty=nil;Device=nil;
}
