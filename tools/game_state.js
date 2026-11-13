// Evaluated in the page by N64Recomp-browser's tools/play_page.mjs (tools/play_plan.json) and tools/record_shaders.mjs
// (tools/shader_plan.json), with n64r, RDRAM words at N64 addresses. The addresses are the kernel's, which never
// moves (lib/bar-decomp's build/kernel.map): gGameSettings at 0x80025CF0 (include/structs.h).
//
//   gameState()  gGameSettings.currentGameState (include/game.h): 2 the intro, 3 the attract demo, 5 a race, 6 Beetle
//       Battle, 14 the save and main menus.
//   raceState()  gGameSettings.raceState.
//   track()  gGameSettings.currentTrack.
//   raceTime()  the race's clock, in seconds from the race's load (its countdown included): a float at 0x8002CC78,
//       found by its moving with the race (the game steps by the CPU's count register, so its time is the race's).
//   raceTicks()  raceTime() in 60ths, the plans' clock step.
//   speed()  the player's car's speed in miles an hour (what its speedometer shows), on Coventry Cove a float at
//       0x8036E3D0 in the heap the race loads into, found by its moving with the gas held and let go; null on another
//       track, whose race loads it elsewhere (no pointer to it was found).
//   stuck()  racing for 5 s or more and below 8 miles an hour: the car is against something (a fence, a rock face), and
//       the plans back it out. Never on a track speed() doesn't know.
//   takeTurn()  window.__turn (a plan's check sets it to stuck()), cleared: true once after a check that found the car
//       stuck, so a pressUntil on !takeTurn() presses its key once then, and not at all otherwise.
//   state()  all three, the race's clock and the speed, for the console.
//   untilState(n, ms)  resolves once gameState() is n, or after ms.
//   trackChanges()  how many times track() has changed since this file was evaluated (Track Select's Right moves it),
//       polled every 50 ms, leaving out the intro's track (27) and back.
//   openTracks(n)  gNumOpenTracks (0x8002CFF0), how many of the single race's tracks Track Select offers, in its order
//       (Coventry Cove, track() 5; Mount Mayhem, 7; Inferno Isle, 9; Sunset Sands; Metro Madness, 10; Wicked Woods),
//       wrapping at the last: a new save's 2, which the game raises as championships are won (the desktop build's
//       Unlock everything cheat writes 6, src/main/bar_cheats.cpp). The pause menu's Track Select (New Track) reads it
//       too, and moves no currentTrack until a track is chosen.
(() => {
  const SETTINGS = 0x80025CF0;
  const s32 = (offset) => n64r(SETTINGS + offset) | 0;
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  window.gameState = () => s32(0xA4);
  window.raceState = () => s32(0x88);
  window.track = () => s32(0x44);
  const f32 = new Float32Array(1), u32 = new Uint32Array(f32.buffer);
  window.raceTime = () => { u32[0] = n64r(0x8002CC78); return f32[0]; };
  window.raceTicks = () => Math.floor(raceTime() * 60);
  const SPEED = { 5: 0x8036E3D0 };
  window.speed = () => { if (!SPEED[track()]) return null; u32[0] = n64r(SPEED[track()]); return f32[0]; };
  let raceStart = null;
  window.stuck = () => raceStart !== null && raceTime() - raceStart >= 5 && speed() !== null &&
    Math.abs(speed()) < 8;
  window.takeTurn = () => { const turn = !!window.__turn; window.__turn = false; return turn; };
  window.state = () => `gameState ${gameState()} raceState ${raceState()} track ${track()}` +
    ` race clock ${raceTime().toFixed(2)} speed ${speed()?.toFixed(1)}`;
  let lastTrack = null, changes = 0;
  clearInterval(window.__trackPoll);
  window.__trackPoll = setInterval(() => {
    const now = track();
    // The intro plays on track 27 (0x1B) and puts the menus' track back after: not a change Track Select made.
    if (lastTrack !== null && now !== lastTrack && now !== 27 && lastTrack !== 27) changes++;
    lastTrack = now;
    // The race's clock when the countdown ended (raceState 0 in a race), for stuck().
    if (gameState() === 5 && raceState() === 0) { if (raceStart === null) raceStart = raceTime(); }
    else raceStart = null;
  }, 50);
  window.trackChanges = () => changes;
  window.openTracks = (n) => n64w(0x8002CFF0, n);
  window.untilState = async (n, ms) => {
    const end = Date.now() + ms;
    while (gameState() !== n && Date.now() < end) await sleep(50);
    return (gameState() === n ? 'there: ' : 'not there: ') + state();
  };
})();
