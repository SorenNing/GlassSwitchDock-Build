#include "NGRenderResolver.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#include <dlfcn.h>
#include <string.h>
#include <ptrauth.h>

// Original arm64: de8c..f2e8; arm64e: e04c..f538.
// Constants below are instruction encodings/window sizes, never image offsets.
namespace {
struct Range { uintptr_t begin, end; vm_prot_t protection; };
Range gRanges[32] = {};
size_t gRangeCount = 0;
uintptr_t gText = 0, gTextEnd = 0;
bool gInitialized = false, gScannedCluster = false;
uintptr_t gAdd = 0, gGaussian = 0, gTable = 0;
const char *gError = "not initialized";
static bool Fail(const char *error) { gError = error; return false; }
static bool InRange(uintptr_t a, size_t n, const Range &r) {
    return a >= r.begin && a < r.end && n <= r.end - a;
}
static bool Readable(uintptr_t a, size_t n) {
    for (size_t i = 0; i < gRangeCount; ++i)
        if ((gRanges[i].protection & VM_PROT_READ) && InRange(a,n,gRanges[i])) return true;
    return false;
}
static bool Code(uintptr_t a, size_t n = 4) {
    for (size_t i = 0; i < gRangeCount; ++i)
        if ((gRanges[i].protection & VM_PROT_EXECUTE) && InRange(a,n,gRanges[i])) return true;
    return false;
}
static uint32_t Word(uintptr_t a) { uint32_t w; memcpy(&w,(const void *)a,4); return w; }
static uintptr_t Pointer(uintptr_t a) { uintptr_t p; memcpy(&p,(const void *)a,8); return p; }
static int64_t SignExtend(uint64_t value, unsigned bits) {
    return (int64_t)(value << (64-bits)) >> (64-bits);
}
static uintptr_t AdrpPage(uintptr_t pc, uint32_t a) {
    uint64_t imm = ((a >> 5) & 0x7ffffu) * 4u + ((a >> 29) & 3u);
    return (pc & ~(uintptr_t)0xfff) + SignExtend(imm,21) * 4096;
}
// e19c/e240 (arm64e e3a4/e44c). Keep the sample's ADD/LDR masks.
static uintptr_t AdrpAdd(uintptr_t pc) {
    if (!Readable(pc,8)) return 0;
    uint32_t a=Word(pc), b=Word(pc+4);
    if ((a&0x9f000000u)!=0x90000000u || (b&0x7f800000u)!=0x11000000u) return 0;
    uintptr_t imm=(b>>10)&0xfff;
    if (b&0x400000) imm <<= 12;
    return AdrpPage(pc,a)+imm;
}
static uintptr_t AdrpLdr(uintptr_t pc) {
    if (!Readable(pc,8)) return 0;
    uint32_t a=Word(pc), b=Word(pc+4);
    if ((a&0x9f000000u)!=0x90000000u || (b>>22)!=0x3e5) return 0;
    return AdrpPage(pc,a)+((b>>7)&0x7ff8);
}
static uintptr_t FindCString(const char *s) {
    size_t n=strlen(s)+1;
    if (!gInitialized || n>gTextEnd-gText) return 0;
    const char *p=(const char *)gText, *end=(const char *)(gTextEnd-n);
    while (p<=end) {
        p=(const char *)memchr(p,*s,(size_t)(end-p)+1);
        if (!p) break;
        if (!memcmp(p,s,n)) return (uintptr_t)p;
        ++p;
    }
    return 0;
}
static uintptr_t FindXref(uintptr_t target) {
    if (!target) return 0;
    for (uintptr_t p=gText; p+8<=gTextEnd; p+=4)
        if (AdrpAdd(p)==target) return p;
    return 0;
}
static uintptr_t FindPrologue(uintptr_t site, unsigned words) {
    uintptr_t start=site-gText>words*4u ? site-words*4u : gText;
    for (uintptr_t p=site;;p-=4) {
        uint32_t w=Word(p);
        if (w==0xd503237f) return p; // PACIBSP
        if ((w&0xffe003e0u)==0xa9a003e0u || (w&0xff8003ffu)==0xd10003ffu)
            return p>gText && Word(p-4)==0xd503237f ? p-4 : p;
        if (p<=start) break;
    }
    return 0;
}
// f240/f490: ADRP,ADD,MOVZ W0; a BL within the following four words.
static uintptr_t RegistrationCall(uintptr_t pc, uintptr_t end, uintptr_t *ctx) {
    if ((Word(pc)&0xff80001fu)!=0x52800000u) return 0;
    uintptr_t descriptor=AdrpAdd(pc-8);
    if (!descriptor || (descriptor&7)) return 0;
    for (unsigned i=1;i<=4 && pc+i*4<end;++i) {
        uint32_t w=Word(pc+i*4);
        if ((w>>26)==0x25) {
            *ctx=descriptor;
            return pc+i*4+SignExtend(w&0x3ffffffu,26)*4;
        }
    }
    return 0;
}
static void ScanGaussianCluster() {
    if (gScannedCluster || !gInitialized) return;
    gScannedCluster=true;
    if (gTextEnd-gText<40) return;
    uintptr_t end=gTextEnd-32;
    for (uintptr_t p=gText+8;p<end;p+=4) {
        uintptr_t contexts[8]={}, target=RegistrationCall(p,end,&contexts[0]);
        if (!target) continue;
        unsigned count=1;
        uintptr_t cursor=p;
        while (count<8) {
            uintptr_t limit=cursor+64<end ? cursor+64 : end, ctx=0;
            bool found=false;
            while ((cursor+=4)<limit) {
                if (RegistrationCall(cursor,end,&ctx)==target) {
                    contexts[count++]=ctx; found=true; break;
                }
            }
            if (!found) break;
        }
        if (count<4) continue;
        // e648/e864: Gaussian is the SECOND call in the confirmed cluster.
        uintptr_t table=0;
        for (unsigned back=2;back<=25 && p>=gText+back*4; ++back) {
            uintptr_t candidate=p-back*4;
            if (candidate<=gText) break;
            table=AdrpLdr(candidate);
            if (table) break;
        }
        if (!Code(target) || !Readable(contexts[1],8) || !Readable(table,8)) {
            Fail("confirmed Gaussian cluster has out-of-image target/slots"); return;
        }
        gAdd=target; gGaussian=contexts[1]; gTable=table; return;
    }
    Fail("no confirmed four-call Gaussian registration cluster");
}
}

uintptr_t NGRenderStripCode(uintptr_t p) {
#if __has_feature(ptrauth_calls)
    return p ? (uintptr_t)ptrauth_strip((void *)p,ptrauth_key_asia) : 0;
#else
    return p;
#endif
}
uintptr_t NGRenderStripData(uintptr_t p) {
#if __has_feature(ptrauth_calls)
    return p ? (uintptr_t)ptrauth_strip((void *)p,ptrauth_key_asda) : 0;
#else
    return p;
#endif
}
void *NGRenderMakeCallable(uintptr_t p) {
    p=NGRenderStripCode(p);
#if __has_feature(ptrauth_calls)
    return p ? ptrauth_sign_unauthenticated((void *)p,ptrauth_key_asia,0) : nullptr;
#else
    return (void *)p;
#endif
}
const char *NGRenderResolverLastError(void) { return gError; }
bool NGRenderAddressInQuartzCore(uintptr_t p,size_t n) { return p && Readable(p,n); }

bool NGRenderResolverInit(void) {
    if (gInitialized) return true;
    for (uint32_t i=0;i<_dyld_image_count();++i) {
        const char *name=_dyld_get_image_name(i);
        if (!name || !strstr(name,"QuartzCore")) continue;
        auto *h=(const mach_header_64 *)_dyld_get_image_header(i);
        if (!h || h->magic!=MH_MAGIC_64) continue;
        intptr_t slide=_dyld_get_image_vmaddr_slide(i);
        uintptr_t p=(uintptr_t)(h+1), end=p+h->sizeofcmds;
        gRangeCount=0; gText=gTextEnd=0;
        for (uint32_t c=0;c<h->ncmds && p+sizeof(load_command)<=end;++c) {
            const auto *lc=(const load_command *)p;
            if (lc->cmdsize<sizeof(load_command) || lc->cmdsize>end-p)
                return Fail("invalid QuartzCore load command");
            if (lc->cmd==LC_SEGMENT_64 && lc->cmdsize>=sizeof(segment_command_64)) {
                const auto *s=(const segment_command_64 *)p;
                if (s->vmsize && s->initprot) {
                    if (gRangeCount==32) return Fail("too many QuartzCore segments");
                    uintptr_t a=s->vmaddr+slide;
                    if (s->vmsize>UINTPTR_MAX-a) return Fail("QuartzCore segment overflow");
                    gRanges[gRangeCount++]={a,a+(uintptr_t)s->vmsize,s->initprot};
                    if (!strncmp(s->segname,"__TEXT",16)) { gText=a; gTextEnd=a+s->vmsize; }
                }
            }
            p+=lc->cmdsize;
        }
        if (!gText || gTextEnd<=gText || !Readable(gText,gTextEnd-gText))
            return Fail("QuartzCore __TEXT unavailable");
        gInitialized=true; gError="none"; return true;
    }
    return Fail("QuartzCore is not loaded");
}
uintptr_t NGRenderResolveCAInternAtomWithCString(void) {
    uintptr_t exported=NGRenderStripCode((uintptr_t)dlsym(RTLD_DEFAULT,"CAInternAtomWithCString"));
    if (exported && Code(exported)) return exported;
    if (!gInitialized) return 0;
    // e2d8/e4e8: STP X20,X19; STP FP,LR; ADD FP; MOV X19,X0;
    // BL; MOV X20,X0; CBNZ. Include preceding PACIBSP when present.
    for (uintptr_t p=gText;p+28<=gTextEnd;p+=4) {
        if (Word(p)==0xa9be4ff4 && Word(p+4)==0xa9017bfd &&
            Word(p+8)==0x910043fd && Word(p+12)==0xaa0003f3 &&
            (Word(p+16)>>26)==0x25 && Word(p+20)==0xaa0003f4 &&
            (Word(p+24)&0x7f00001fu)==0x35000000u)
            return p>gText && Word(p-4)==0xd503237f ? p-4 : p;
    }
    Fail("CAInternAtom wrapper signature not found"); return 0;
}
uintptr_t NGRenderResolveAddFilter(void) { ScanGaussianCluster(); return gAdd; }
uintptr_t NGRenderResolveGaussianCtxSlot(void) { ScanGaussianCluster(); return gGaussian; }
uintptr_t NGRenderResolveFilterTableSlot(void) { ScanGaussianCluster(); return gTable; }
uintptr_t NGRenderResolveStopEncoders(void) {
    uintptr_t site=FindXref(FindCString("!memoryless_in_use ()"));
    uintptr_t entry=site ? FindPrologue(site,0x200) : 0;
    if (!entry) Fail("stop_encoders anchor/xref/prologue not found");
    return entry;
}
ptrdiff_t NGRenderResolveMetalCmdBufOffset(void) {
    uintptr_t site=FindXref(FindCString("Command buffer allocation failed!\n"));
    uintptr_t entry=site ? FindPrologue(site,0x400) : 0;
    if (!entry) { Fail("start_command_buffer anchor/xref/prologue not found"); return -1; }
    uint32_t aliases=1; // x0 is MetalContext; original scans exactly 48 words.
    for (unsigned i=0;i<48 && entry+i*4+4<=gTextEnd;++i) {
        uint32_t w=Word(entry+i*4);
        if ((w&0xffe0ffe0u)==0xaa0003e0u) {
            uint32_t bit=1u<<(w&31);
            aliases=(aliases&(1u<<((w>>16)&31))) ? aliases|bit : aliases&~bit;
        } else if ((w>>23)==0x1f2) {
            uint32_t offset=(w>>7)&0x7ff8;
            if (offset>=0x400 && (aliases&(1u<<((w>>5)&31)))) return offset;
            if (w&0x400000) aliases &= ~(1u<<(w&31));
        }
    }
    Fail("command-buffer access absent from 48-word context window"); return -1;
}
int NGRenderResolveRenderVtableSlot(const uintptr_t *v,unsigned count) {
    if (!v || count<2 || !Readable((uintptr_t)v,count*8)) return -1;
    for (unsigned slot=0;slot+1<count;++slot) {
        uintptr_t f=NGRenderStripCode(v[slot]);
        if (!Code(f)) continue;
        for (unsigned i=0;i<23 && Code(f+i*4);++i) {
            uint32_t w=Word(f+i*4);
            if (w==0xd65f03c0) break;
            if (w==0xf9400008 && Code(f+(i+1)*4)) {
                uint32_t load=Word(f+(i+1)*4), target=(load>>10)&0xfff;
                if ((load&0xffc003ffu)==0xf9400108u && target==slot+1) {
                    for (unsigned k=i+2;k<i+16 && Code(f+k*4);++k) {
                        uint32_t b=Word(f+k*4);
                        if ((b&0xffdfffffu)==0xd61f0100u) return (int)target;
                        if (b==0xd65f03c0) break;
                    }
                }
            } else if (w==0xf9400010) {
                // PAC forwarder: LDR X16,[X0]; LDR X8,[X16,#imm]!;
                // ... BRAA/BLRAA X8,<modifier>. 0x1ae7e1 is the sample mask.
                for (unsigned j=i+1;j<23 && j<i+10 && Code(f+j*4);++j) {
                    uint32_t load=Word(f+j*4);
                    if ((load&0xffe00fffu)!=0xf8400e08u) continue;
                    uint32_t target=(load>>15)&0x3f;
                    if (target!=slot+1) break;
                    for (unsigned k=j+1;k<=23 && k<j+10 && Code(f+k*4);++k) {
                        uint32_t b=Word(f+k*4);
                        if (((b|0x200000u)>>11)==0x1ae7e1) return (int)target;
                        if (b==0xd65f03c0) break;
                    }
                    break;
                }
            }
        }
    }
    Fail("render forwarder not found in Gaussian vtable"); return -1;
}
int NGRenderResolveEdgeInfoVtableSlot(const uintptr_t *v,unsigned count) {
    if (!v || !Readable((uintptr_t)v,count*8)) return -1;
    for (unsigned slot=0;slot<count;++slot) {
        uintptr_t f=NGRenderStripCode(v[slot]);
        unsigned flags=0;
        if (!Code(f)) continue;
        for (unsigned i=0;i<80 && Code(f+i*4);++i) {
            uint32_t w=Word(f+i*4);
            if (w==0xaa0503f7) flags|=1; // MOV X23,X5
            if (w==0xaa0603f4) flags|=2; // MOV X20,X6
            if (w==0x2d0002e1) flags|=4; // STP S1,S0,[X23]
            if (w==0x39000288) flags|=8; // STRB W8,[X20]
            if (w==0xd65f0fff || w==0xd65f03c0) break; // RETAB/RET
        }
        if (flags==15) return (int)slot;
    }
    Fail("Gaussian get_edge_info signature not found"); return -1;
}
bool NGRenderResolveSymbols(NGRenderResolvedSymbols *out,unsigned osMajor) {
    if (!out) return Fail("null resolution output");
    *out={}; out->renderSlot=out->edgeInfoSlot=-1; out->commandBufferOffset=-1;
    if (!NGRenderResolverInit()) return false;
    uintptr_t atom=NGRenderResolveCAInternAtomWithCString(), add=NGRenderResolveAddFilter();
    uintptr_t stop=NGRenderResolveStopEncoders();
    if (!atom || !add || !stop || !gGaussian || !gTable) return false;
    uintptr_t v=NGRenderStripData(Pointer(gGaussian));
    if (!v || !Readable(v,22*8)) return Fail("Gaussian descriptor/vtable unavailable");
    out->gaussianVtable=(const uintptr_t *)v;
    out->edgeInfoSlot=NGRenderResolveEdgeInfoVtableSlot(out->gaussianVtable,22);
    out->renderSlot=NGRenderResolveRenderVtableSlot(out->gaussianVtable,22);
    // Original's sole direct-slot fallback is edge-3 on iOS14.
    if (out->renderSlot<0 && osMajor<15 && out->edgeInfoSlot>2 &&
        Code(NGRenderStripCode(out->gaussianVtable[out->edgeInfoSlot-3])))
        out->renderSlot=out->edgeInfoSlot-3;
    if (out->edgeInfoSlot<0 || out->renderSlot<0 || out->renderSlot>=22 ||
        out->renderSlot==out->edgeInfoSlot) return Fail("invalid Gaussian dispatch slots");
    out->internAtom=(NGRenderInternAtomFunction)NGRenderMakeCallable(atom);
    out->addFilter=(NGRenderAddFilterFunction)NGRenderMakeCallable(add);
    out->stopEncoders=(NGRenderStopEncodersFunction)NGRenderMakeCallable(stop);
    out->gaussianDescriptor=(const void *)gGaussian;
    out->filterTableSlot=(const uintptr_t *)gTable;
    out->commandBufferOffset=NGRenderResolveMetalCmdBufOffset();
    // The original allows registration with an unresolved command-buffer field.
    // Register chooses whether to activate; the renderer must not guess it.
    if (out->commandBufferOffset>=0) gError="none";
    return true;
}
