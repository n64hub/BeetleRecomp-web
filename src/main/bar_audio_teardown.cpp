// bar_audio_teardown.cpp — the audio manager's teardown waits until the scheduler has retired its audio task.
//
// The audio manager module's teardown, func_uvaudiomgr_rom_004008C0 (its export 0, run as the game unloads the
// module between screens: three times on the way from the boot to a race), destroys the audio thread, then frees the
// audio heap, which holds the OSScTask the thread last handed the scheduler. That task is nearly always still the
// scheduler's: queued in its command queue until the next retrace (the thread queues the next frame's task as soon as
// the last one is done), or running on the RSP. The scheduler starts it at the retrace and, once the RSP is done,
// _uvScDoneAud sends to the task's msgQ, which it reads from the task then. On the console the RSP takes about a
// millisecond and loading the next module far longer, so the task is retired before anything reuses its memory. Here
// the RSP runs the task on a host thread and the scheduler hears it is done only at a game thread's next OS call,
// while the module's reload and the new audio manager's init, which zeroes its heap, run at host speed. When they get
// there first, msgQ reads 0 and the scheduler's osSendMesg faults on it: do_send <- osSendMesg <- _uvScDoneAud <-
// _uvScHandleRSP <- _uvScMain (docs/KNOWN_ISSUES.md), the page's "index out of bounds" on a worker in the menus.
//
// So once the thread is destroyed and before anything is freed (scripts/fix-recompiled.sh rule J calls this right
// after the teardown's osDestroyThread), the App thread yields until the scheduler holds no audio task, as the
// console's RSP would have retired it by then. With no thread left to queue another, that takes a retrace and the
// task. It is bounded, so a scheduler that never gets to the task can't hang the game, and says so when it gives up.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include "recomp.h"

extern "C" void yield_self_1ms(uint8_t* rdram);

namespace {

constexpr int64_t se(uint32_t addr) { return (int64_t)(int32_t)addr; }

constexpr uint32_t kSchedAudioTask = 0x8002EDF8;  // D_8002EDF8: the audio task the scheduler has taken from cmdQ
constexpr uint32_t kScheduler = 0x8002F4F8;       // gScheduler, the OSSched
constexpr int32_t kCmdQ = 0x78;                   // OSSched.cmdQ (_uvScGetCmdQ)
constexpr int32_t kTaskType = 0x10;               // OSScTask.list.t.type: 2 is M_AUDTASK
constexpr auto kMaxWait = std::chrono::milliseconds(250);

// Whether the scheduler's command queue (an OSMesgQueue of OSScTask pointers) still holds an audio task.
bool audio_task_queued(uint8_t* rdram) {
    const int32_t q = MEM_W(0, se(kScheduler)) + kCmdQ;
    const int32_t count = MEM_W(0x8, q), first = MEM_W(0xC, q), size = MEM_W(0x10, q), buf = MEM_W(0x14, q);
    for (int32_t i = 0; size > 0 && i < count && i < size; i++) {
        const int32_t task = MEM_W(4 * ((first + i) % size), buf);
        if (task != 0 && MEM_W(kTaskType, task) == 2) {
            return true;
        }
    }
    return false;
}

bool scheduler_holds_audio_task(uint8_t* rdram) {
    return MEM_W(0, se(kSchedAudioTask)) != 0 || audio_task_queued(rdram);
}

}  // namespace

extern "C" void bar_retire_audio_tasks(uint8_t* rdram) {
    const auto start = std::chrono::steady_clock::now();
    while (scheduler_holds_audio_task(rdram)) {
        if (std::chrono::steady_clock::now() - start > kMaxWait) {
            fprintf(stderr, "[BeetleRecomp] the audio manager's teardown went on with an audio task still the scheduler's\n");
            return;
        }
        yield_self_1ms(rdram);
    }
}
