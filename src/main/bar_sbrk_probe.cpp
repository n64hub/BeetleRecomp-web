// TEST ONLY: prints the stack of whatever grows the heap, each 32 MB, without allocating (sbrk runs under malloc's lock).
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/console.h>
#include <atomic>
#include <cstdint>
#include <cstdio>

extern "C" void *__real_sbrk(intptr_t increment);
static std::atomic<intptr_t> grown{0};
static std::atomic<intptr_t> reported{0};

extern "C" void *__wrap_sbrk(intptr_t increment) {
    void *result = __real_sbrk(increment);
    if (increment > 0) {
        const intptr_t total = grown.fetch_add(increment) + increment;
        if ((total - reported.load()) >= (32 << 20)) {
            reported.store(total);
            static char stack[6144];
            char line[128];
            snprintf(line, sizeof(line), "[sbrk] heap grown by %ld MB since start (this call +%ld KB)", long(total >> 20), long(increment >> 10));
            emscripten_console_error(line);
            emscripten_get_callstack(EM_LOG_C_STACK, stack, sizeof(stack));
            emscripten_console_error(stack);
        }
    }
    return result;
}
#endif
