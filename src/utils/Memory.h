#pragma once
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>

static uintptr_t GetBase() {
    return (uintptr_t)dlopen(NULL, RTLD_NOW);
}

template<typename T>
static T Read(uintptr_t addr) {
    return *(T*)addr;
}

template<typename T>
static void Write(uintptr_t addr, T val) {
    *(T*)addr = val;
}

static uintptr_t GetOffset(uintptr_t offset) {
    static uintptr_t base = 0;
    if (!base) {
        Dl_info info;
        dladdr((void*)GetBase, &info);
        base = (uintptr_t)info.dli_fbase;
    }
    return base + offset;
}
