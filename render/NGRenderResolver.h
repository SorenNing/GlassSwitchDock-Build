#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif
// These are C call ABIs, not QuartzCore object-layout declarations.
typedef uint32_t (*NGRenderInternAtomFunction)(const char *);
typedef void (*NGRenderAddFilterFunction)(uint32_t atom, const void *descriptor);
typedef void (*NGRenderStopEncodersFunction)(void *metalContext);

struct NGRenderResolvedSymbols {
    NGRenderInternAtomFunction internAtom;
    NGRenderAddFilterFunction addFilter;
    NGRenderStopEncodersFunction stopEncoders;
    const void *gaussianDescriptor; // address of the original vtable-pointer slot
    const uintptr_t *gaussianVtable;
    const uintptr_t *filterTableSlot;
    int renderSlot;
    int edgeInfoSlot;
    ptrdiff_t commandBufferOffset; // -1 means unresolved; never a device constant
};

// Initialization/resolution is serialized by NGRenderRegister. QuartzCore must
// already be loaded; the original dylib is never loaded or consulted at runtime.
bool NGRenderResolverInit(void);
const char *NGRenderResolverLastError(void);
uintptr_t NGRenderResolveCAInternAtomWithCString(void);
uintptr_t NGRenderResolveAddFilter(void);
uintptr_t NGRenderResolveGaussianCtxSlot(void);
uintptr_t NGRenderResolveFilterTableSlot(void);
uintptr_t NGRenderResolveStopEncoders(void);
ptrdiff_t NGRenderResolveMetalCmdBufOffset(void);
int NGRenderResolveRenderVtableSlot(const uintptr_t *, unsigned count);
int NGRenderResolveEdgeInfoVtableSlot(const uintptr_t *, unsigned count);
bool NGRenderResolveSymbols(struct NGRenderResolvedSymbols *out, unsigned osMajor);
bool NGRenderAddressInQuartzCore(uintptr_t address, size_t bytes);

// arm64e sample 0xe04c/e068/e078: XPACI + PACIA(IA,0), XPACI, XPACD.
// Do not authenticate a foreign vtable pointer with an invented discriminator.
uintptr_t NGRenderStripCode(uintptr_t pointer);
uintptr_t NGRenderStripData(uintptr_t pointer);
void *NGRenderMakeCallable(uintptr_t pointer);
#ifdef __cplusplus
}
#endif
