#import "NGDockRender.h"
#import "NGRenderResolver.h"
#import <CoreFoundation/CoreFoundation.h>
#import <os/lock.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <mutex>
#include <unordered_map>
#include <string>
#include <limits.h>
#include <stdlib.h>

// Our namespace, routes, state and source implementation. No SystemBox dylib,
// installation identity, preferences or shader is consulted at runtime.
namespace {
using RenderFunction=void(*)(void *,void *,uintptr_t,void *,float,void *,float,uintptr_t,uintptr_t,uintptr_t,uintptr_t);
using IdentityFunction=uintptr_t(*)(void *,void *);
using HookFunction=void(*)(void *,void *,void **);
NGRenderResolvedSymbols Symbols{};
RenderFunction OriginalRender=nullptr;
IdentityFunction OriginalIdentity=nullptr;
unsigned Major=0;
bool Attempted=false,Registered=false;
std::recursive_mutex &RouteLock(void) {static auto *lock=new std::recursive_mutex;return *lock;}
std::unordered_map<uint32_t,unsigned> &Routes(void) {static auto *routes=new std::unordered_map<uint32_t,unsigned>;return *routes;}
NSDictionary *Packets[NG_DOCK_SLOTS]={};
uint64_t NextFrame[NG_DOCK_SLOTS]={},AcceptedFrame[NG_DOCK_SLOTS]={};
std::unordered_map<unsigned,std::string> &LastAck(void) {static auto *acks=new std::unordered_map<unsigned,std::string>;return *acks;}
char Anchor;

bool WriteState(NSString *name,NSDictionary *value) {
    NSString *dir=NGDockStateDirectory();BOOL directory=NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&directory] || !directory) return false;
    NSString *path=[dir stringByAppendingPathComponent:name];
    return [value writeToFile:path atomically:YES] && chmod(path.fileSystemRepresentation,0644)==0;
}
int64_t BootTime(void) {
    timeval t={};size_t n=sizeof(t);int keys[]={CTL_KERN,KERN_BOOTTIME};
    return sysctl(keys,2,&t,&n,NULL,0)==0?t.tv_sec:0;
}
void Report(NSString *state) {
    NSMutableDictionary *tokens=[NSMutableDictionary dictionary];
    for (unsigned n=0;n<NG_DOCK_SLOTS;n++) if (Packets[n][@"token"]) tokens[[NSString stringWithFormat:@"%u",n]]=Packets[n][@"token"];
    if (!WriteState(@"backend.plist",@{@"schema":@1,@"state":state,@"pid":@(getpid()),@"boot":@(BootTime()),@"registered":@(Registered),@"tokens":tokens})) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR(NG_DOCK_BACKEND_READY),NULL,NULL,true);
}
void Ack(unsigned slot,NSDictionary *p,uint64_t frame,bool success) {
    if (slot>=NG_DOCK_SLOTS || ![p[@"token"] isKindOfClass:NSString.class]) return;
    std::string key=std::string([p[@"token"] UTF8String])+(success?"-ok":"-failed");
    std::lock_guard<std::recursive_mutex> guard(RouteLock());
    if (![Packets[slot][@"token"] isEqual:p[@"token"]] || frame<AcceptedFrame[slot]) return;
    AcceptedFrame[slot]=frame;
    if (LastAck()[slot]==key) return;
    if (!WriteState([NSString stringWithFormat:@"ack-%u.plist",slot],@{@"schema":@1,@"slot":@(slot),@"token":p[@"token"],@"success":@(success),@"boot":@(BootTime()),@"pid":@(getpid()),@"frame":@(frame)})) return;
    LastAck()[slot]=key;
    NSString *name=[NSString stringWithFormat:@"com.ning.glassswitchdock/dock-frame-%u",slot];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)name,NULL,NULL,true);
}
void Reload(void) {
    std::lock_guard<std::recursive_mutex> guard(RouteLock());
    for (unsigned n=0;n<NG_DOCK_SLOTS;n++) Packets[n]=NGDockReadSlot(n);
    if (Registered) Report(@"registered");
}
bool ReadWord(const void *source,void *out,size_t count) {
    vm_size_t read=0;
    return source && vm_read_overwrite(mach_task_self(),(vm_address_t)source,count,(vm_address_t)out,&read)==KERN_SUCCESS && read==count;
}
uintptr_t Pointer(void *object,ptrdiff_t offset) {
    uintptr_t p=0;if (!object || offset<0 || !ReadWord((char *)object+offset,&p,sizeof(p))) return 0;
    return NGRenderStripData(p);
}
int Slot(void *filter) {
    uint32_t atom=0;
    if (!filter || !ReadWord((char *)filter+0x18,&atom,4)) return -1;
    std::lock_guard<std::recursive_mutex> guard(RouteLock());
    auto i=Routes().find(atom);return i==Routes().end()?-1:(int)i->second;
}
uintptr_t Identity(void *self,void *filter) {
    return Slot(filter)>=0?0:(OriginalIdentity?OriginalIdentity(self,filter):0);
}
void Render(void *self,void *filter,uintptr_t opaque2,void *context,float opacity,void *surface,float scale,
            uintptr_t flags,uintptr_t opaque6,uintptr_t opaque7,uintptr_t opaque8) {
    int slot=Slot(filter);
    if (slot<0) {if (OriginalRender) OriginalRender(self,filter,opaque2,context,opacity,surface,scale,flags,opaque6,opaque7,opaque8);return;}
    @autoreleasepool {
        NSDictionary *packet=nil;uint64_t frame=0;
        {std::lock_guard<std::recursive_mutex> guard(RouteLock());packet=Packets[slot];frame=++NextFrame[slot];}
        uintptr_t src=Pointer(surface,Major>=17?0x60:0x58);
        id<MTLTexture> input=src?(__bridge id<MTLTexture>)(void *)src:nil;
        // Retain the CA input across its pass: allocation can rotate surfaces.
        // CA's original pass owns allocation and the destination attachment.
        if (OriginalRender) OriginalRender(self,filter,opaque2,context,opacity,surface,scale,flags,opaque6,opaque7,opaque8);
        if (!packet) return;
        ptrdiff_t destinationOffset=Major==16?0x110:Major==17?0xf8:0x108;
        uintptr_t attachment=Pointer(context,destinationOffset);
        uintptr_t dst=Pointer((void *)attachment,Major>=17?0x60:0x58);
        uintptr_t cmd=Pointer(context,Symbols.commandBufferOffset);
        if (!src || !dst || !cmd || ![packet[@"active"] boolValue]) {Ack(slot,packet,frame,false);return;}
        id<MTLTexture> output=(__bridge id<MTLTexture>)(void *)dst;
        // Finish CA's encoder before creating our encoders in its command buffer.
        Symbols.stopEncoders(context);
        cmd=Pointer(context,Symbols.commandBufferOffset);
        id<MTLCommandBuffer> commands=(__bridge id<MTLCommandBuffer>)(void *)cmd;
        if (!commands || !NGDockEncode(commands,input,output,packet)) {Ack(slot,packet,frame,false);return;}
        [commands addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            Ack((unsigned)slot,packet,frame,completed.status==MTLCommandBufferStatusCompleted);
        }];
    }
}
HookFunction HookBackend(void) {
    HookFunction hook=(HookFunction)dlsym(RTLD_DEFAULT,"MSHookFunction");
    if (hook) return hook;
    Dl_info info={};if (!dladdr(&Anchor,&info) || !info.dli_fname) return nullptr;
    char resolved[PATH_MAX]={};
    NSString *full=[NSString stringWithUTF8String:realpath(info.dli_fname,resolved)?:info.dli_fname];
    NSString *prefix=nil;
    for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries/GlassSwitchDockRender.dylib",@"/usr/lib/TweakInject/GlassSwitchDockRender.dylib"])
        if ([full hasSuffix:suffix]) prefix=[full substringToIndex:full.length-suffix.length];
    if (!prefix) return nullptr;
    for (NSString *relative in @[@"usr/lib/libellekit.dylib",@"usr/lib/libsubstrate.dylib",@"Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"]) {
        void *h=dlopen([prefix stringByAppendingPathComponent:relative].UTF8String,RTLD_NOW|RTLD_LOCAL);
        if (h) hook=(HookFunction)dlsym(h,"MSHookFunction");if (hook) return hook;
    }
    return nullptr;
}
void Register(void);
void Changed(CFNotificationCenterRef,void *,CFStringRef,const void *,CFDictionaryRef) {Reload();}
}

namespace {
void Register(void) {
    std::lock_guard<std::recursive_mutex> guard(RouteLock());
    static unsigned retries=0;
    if (Registered || Attempted) return;
    if (!Symbols.filterTableSlot || !*Symbols.filterTableSlot) {
        if (++retries<=40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250000000),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{Register();});
        return;
    }
    HookFunction hook=HookBackend();
    if (!hook) {Report(@"hook-unavailable");return;}
    // The original slots are never overwritten on a second install attempt.
    Attempted=true;
    uintptr_t render=Symbols.gaussianVtable[Symbols.renderSlot];
    uintptr_t identity=Symbols.gaussianVtable[0];
    void *original=nullptr;
    hook((void *)NGRenderStripCode(render),(void *)NGRenderStripCode((uintptr_t)&Render),&original);
    OriginalRender=(RenderFunction)NGRenderMakeCallable((uintptr_t)original);
    if (!OriginalRender) {Report(@"render-hook-failed");return;}
    original=nullptr;
    hook((void *)NGRenderStripCode(identity),(void *)NGRenderStripCode((uintptr_t)&Identity),&original);
    OriginalIdentity=(IdentityFunction)NGRenderMakeCallable((uintptr_t)original);
    if (!OriginalIdentity) {Report(@"identity-hook-failed");return;}
    for (unsigned n=0;n<NG_DOCK_SLOTS;n++) {
        NSString *name=[NSString stringWithFormat:@"%s%u",NG_DOCK_FILTER_PREFIX,n];
        uint32_t atom=Symbols.internAtom(name.UTF8String);if (!atom) continue;
        {std::lock_guard<std::recursive_mutex> guard(RouteLock());Routes()[atom]=n;}
        Symbols.addFilter(atom,Symbols.gaussianDescriptor);
    }
    Registered=Routes().size()==NG_DOCK_SLOTS;
    Reload();Report(Registered?@"registered":@"filter-registration-failed");
}
bool RapidStartGuard(void) {
    NSString *path=[NGDockStateDirectory() stringByAppendingPathComponent:@"starts.plist"];
    NSDictionary *old=[NSDictionary dictionaryWithContentsOfFile:path];
    int64_t now=(int64_t)time(NULL),boot=BootTime();
    unsigned count=([old[@"boot"] longLongValue]==boot && now>=[old[@"time"] longLongValue] && now-[old[@"time"] longLongValue]<60)?[old[@"count"] unsignedIntValue]+1:1;
    if ([old[@"boot"] longLongValue]==boot && [old[@"disabled"] boolValue]) return false;
    if (!WriteState(@"starts.plist",@{@"boot":@(boot),@"time":@(now),@"count":@(count),@"disabled":@(count>=3)})) return false;
    if (count>=3) return false;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45000000000ll),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *current=[NSDictionary dictionaryWithContentsOfFile:path];
        if ([current[@"boot"] longLongValue]==boot && ![current[@"disabled"] boolValue])
            WriteState(@"starts.plist",@{@"boot":@(boot),@"time":@0,@"count":@0,@"disabled":@NO});
    });
    return true;
}
}
#ifndef NG_TESTING
__attribute__((constructor)) static void NGDockBackendInitialize(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"backboardd"]) return;
        Major=(unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (Major<15 || Major>18) {Report(@"unsupported-render-abi");return;}
        if (!RapidStartGuard()) {Report(@"rapid-start-guard");return;}
        if (!NGRenderResolveSymbols(&Symbols,Major) || Symbols.commandBufferOffset<0) {Report(@"unresolved-render-abi");return;}
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,Changed,CFSTR(NG_DOCK_PARAMETERS_CHANGED),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        Register();
    }
}
#endif
