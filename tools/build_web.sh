#!/usr/bin/env bash
# Builds the web page (build-web/BeetleRecomp.html, .js, .wasm, .data) from the USA ROM, on Linux with Docker: all of
# it runs in tools/docker/Dockerfile's image (emsdk, naga, spirv-opt and ccache as every page's, and what BeetleDecomp
# and BeetleRecomp's generators need), ccache in build-web-prep/ccache:
#
#   bash tools/build_web.sh <USA ROM> [cpus] [--prepare]   --prepare stops before the page (steps 1-3)
#   bash tools/build_web.sh --patches                      step 1 alone, where it is run: no ROM, no image, only git
#                                                          and CMake
#
# 1. The submodules the page needs and their patches, from clean whenever this script, scripts/dependency-patches,
#    lib/N64Recomp-browser or web/patches moved since the last time (build-web-prep/web-patched records it):
#    apply.cmake can't take a checkout from one version of its patches to another. rt64 first goes to the upstream
#    commit the web's patches are made on (web/patches/rt64-upstream.patch: upstream rt64 merged into this repo's rt64
#    without a conflict, and plume at the commit that one pins, in rt64's index too), then the game's own patches as
#    scripts/apply-dependency-patches.py applies them but the Windows and macOS ones the page doesn't build, then
#    N64Recomp-browser's web support (lib/N64Recomp-browser/patches/apply.cmake, project by project, lib/N64Recomp
#    too, which writes the game's code, and lib/RecompFrontend, this repo's own copy), but for the files where the two
#    change the same lines: the web's change to those (web/patches/files.txt) is web/patches/<project>.patch instead,
#    made on top of the game's from the N64Recomp-browser commit files.txt names, with what the web has changed in
#    them since merged in by apply.cmake --since (only a change that meets the game's own lines stops the build, for
#    another merge by hand).
# 2. The decomp (lib/bar-decomp) from the ROM, checked byte for byte, and its recomp ELF (elf/recomp.elf), as
#    BUILDING.md's Generate private inputs and code has them; done again only when lib/bar-decomp moves.
# 3. N64Recomp built from the patched lib/N64Recomp, and the recompiled game and patches (RecompiledFuncs,
#    RecompiledPatches) as BUILDING.md makes them, again whenever their inputs moved (build-web-prep/recompiled-stamp).
#    The generated code is the web-patched N64Recomp's: a desktop build in the same checkout makes its own again.
# 4. The page, with emcmake, in build-web (CMakeLists.txt's EMSCRIPTEN parts).
# N64Recomp-browser's CI runs --patches with its own checkout as lib/N64Recomp-browser and the submodules checked out,
# so a web change there that meets this port's own lines in a file left out is red where it is made: merge it into the
# patch by hand then.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: $0 <USA ROM> [cpus] [--prepare] | --patches" >&2; exit 2; }
mode=page jobs="$(nproc)"
[[ "$1" == --patches ]] && mode=patches
[[ $mode == patches ]] || rom="$(realpath "$1")"
for a in "${@:2}"; do
    case "$a" in --prepare) mode=prepare ;; *) jobs="$a" ;; esac
done
cd "$root"
browser=lib/N64Recomp-browser
prep=build-web-prep
mkdir -p $prep

step() { printf '\n== %s\n' "$*"; }

if [[ $mode != patches && -z "${BEETLE_WEB_IMAGE:-}" ]]; then
    step "Image"
    image=beetle-web:$(sha256sum tools/docker/Dockerfile | cut -c1-12)
    docker image inspect "$image" > /dev/null 2>&1 || docker build -t "$image" tools/docker
    mkdir -p $prep/home $prep/ccache
    exec docker run --rm -u "$(id -u):$(id -g)" -e BEETLE_WEB_IMAGE=1 -e HOME=/src/$prep/home \
        -e CCACHE_DIR=/src/$prep/ccache -v "$root:/src" -v "$rom:/rom.z64:ro" -w /src "$image" \
        bash -c 'git config --global --add safe.directory "*" && exec bash tools/build_web.sh "$@"' - /rom.z64 "${@:2}"
fi

# --- 1. Submodules and patches ---
step "Submodules"
[[ -f lib/rt64/CMakeLists.txt && -f lib/N64ModernRuntime/N64Recomp/CMakeLists.txt && -f lib/N64Recomp/CMakeLists.txt &&
   -f $browser/patches/apply.cmake ]] ||
    git submodule update --init --recursive lib/rt64 lib/N64ModernRuntime lib/N64Recomp $browser
[[ $mode == patches || ( -f lib/RmlUi/CMakeLists.txt && -f lib/lunasvg/CMakeLists.txt ) ]] ||
    git submodule update --init lib/RmlUi lib/lunasvg
[[ $mode == patches || -f lib/bar-decomp/Makefile ]] || git submodule update --init --recursive lib/bar-decomp

step "Patches"
# The plume rt64's upstream commit pins (web/patches/rt64-upstream.patch).
plume=d890ac899e505fb30040e037a4037cdeca68f033
# <name> <checkout> [files left to web/patches/<name>.patch, merged from the commit files.txt names]
shared() { awk -v p="$1" '!/^#/ && $1 == p { printf "%s ", $2 }' web/patches/files.txt; }
merged_from="$(sed -n 's/^# merged from N64Recomp-browser //p' web/patches/files.txt)"
web_patches="rt64 lib/rt64 $(shared rt64)
plume lib/rt64/src/contrib/plume $(shared plume)
hlslpp lib/rt64/src/contrib/hlslpp
N64ModernRuntime lib/N64ModernRuntime $(shared N64ModernRuntime)
N64Recomp lib/N64ModernRuntime/N64Recomp
N64Recomp lib/N64Recomp
RecompFrontend lib/RecompFrontend $(shared RecompFrontend)"
# The game's own: <checkout> <patch>, in apply-dependency-patches.py's order, without rt64-windows-dxil,
# rt64-macos-baseline and plume-metal-encoder-retain, and N64ModernRuntime-code-memory: it makes a code mod's native
# pages writable and clears the instruction cache after (mprotect, __builtin___clear_cache), which wasm has neither of,
# and a page has no native code to patch.
own_patches="lib/N64ModernRuntime N64ModernRuntime
lib/rt64 rt64
lib/N64Recomp N64Recomp
lib/rt64 rt64-sdl-filter-restore
lib/N64ModernRuntime N64ModernRuntime-interrupt-mask"
stamp="$(git -C $browser rev-parse HEAD) $( (cat tools/build_web.sh scripts/dependency-patches/*.patch web/patches/*; echo "$web_patches") |
    sha1sum | cut -c1-40)"
# A checkout reset since (rt64 clean) is patched again whatever the stamp says.
if [[ "$(cat $prep/web-patched 2> /dev/null)" != "$stamp" ]] || git -C lib/rt64 diff --quiet; then
    for s in lib/rt64 lib/N64ModernRuntime lib/N64Recomp; do
        git -C $s submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C $s submodule update -q --init --recursive --force
        git -C $s reset -q --hard && git -C $s clean -fdq
        rm -f "$(git -C $s rev-parse --path-format=absolute --git-dir)"/n64recomp-browser-*
    done
    git checkout -q -- lib/RecompFrontend && git clean -fdq lib/RecompFrontend
    rm -f "$(git rev-parse --path-format=absolute --git-dir)"/n64recomp-browser-*
    git -C lib/rt64 apply --whitespace=nowarn "$root/web/patches/rt64-upstream.patch"
    if ! git -C lib/rt64/src/contrib/plume checkout -q $plume 2> /dev/null; then
        git -C lib/rt64/src/contrib/plume fetch -q https://github.com/renderbag/plume $plume
        git -C lib/rt64/src/contrib/plume checkout -q $plume
    fi
    # rt64's index names that plume too, so a recursive submodule update over this checkout (a build host's sync)
    # finds plume where rt64 says it is and leaves it, patched, in place of putting back the commit rt64's own pins.
    git -C lib/rt64 update-index --cacheinfo 160000,$plume,src/contrib/plume
    git -C lib/rt64/src/contrib/plume submodule update -q --init --recursive
    while read -r checkout patch; do
        git -C "$checkout" apply --whitespace=nowarn "$root/scripts/dependency-patches/$patch.patch"
    done <<< "$own_patches"
    while read -r name checkout skip; do
        cmake -P $browser/patches/apply.cmake "$name" "$checkout" $skip
        # RecompFrontend is in this repository's tree, where git apply takes the patch's paths from the top and leaves
        # out, silently, those outside the folder it runs in.
        prefix="$(git -C "$checkout" rev-parse --show-prefix)"
        [[ -z "$skip" ]] || git -C "$checkout" apply --whitespace=nowarn ${prefix:+--directory="$prefix"}             "$root/web/patches/$name.patch"
        [[ -z "$skip" ]] || cmake -P $browser/patches/apply.cmake "$name" "$checkout" --since "$merged_from" $skip
    done <<< "$web_patches"
    echo "$stamp" > $prep/web-patched
fi

[[ $mode == patches ]] && exit 0

# --- 2. The decomp and its recomp ELF ---
step "Decomp"
sha1=e5ab4d226c08d22f68a2edcc48870203e67454b8
[[ "$(sha1sum < "$rom" | cut -c1-40)" == $sha1 ]] || { echo "$rom is not Beetle Adventure Racing (USA), SHA-1 $sha1" >&2; exit 1; }
decomp="$(git -C lib/bar-decomp rev-parse HEAD)"
if [[ "$(cat $prep/decomp-stamp 2> /dev/null)" != "$decomp" || ! -f elf/recomp.elf ]]; then
    (
        cd lib/bar-decomp
        cp "$rom" baserom.us.z64
        [[ -d .venv ]] || python3 -m venv .venv
        . .venv/bin/activate
        [[ -f .venv/deps-done ]] || { make dependencies > /dev/null; touch .venv/deps-done; }
        [[ -d asm/us ]] || make extract > /dev/null
        make -j"$jobs" > "$root/$prep/decomp.log" 2>&1 || { tail -30 "$root/$prep/decomp.log"; exit 1; }
        grep -q 'beetleadventurerac.us.z64.*OK' "$root/$prep/decomp.log" || { echo "the decomp doesn't match the ROM" >&2; exit 1; }
        make recomp >> "$root/$prep/decomp.log" 2>&1 || { tail -30 "$root/$prep/decomp.log"; exit 1; }
    )
    cp lib/bar-decomp/build/recomp.elf elf/recomp.elf
    echo "$decomp" > $prep/decomp-stamp
fi

# --- 3. N64Recomp, RSPRecomp and the recompiled code ---
step "N64Recomp"
tools=$prep/tools
[[ -f $tools/build.ninja ]] || cmake -S lib/N64Recomp -B $tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ > /dev/null
ninja -C $tools N64RecompCLI > /dev/null

step "Recompiled code"
inputs="$( (cat elf/recomp.elf BeetleRecomp.toml overlays.us.txt config/original-functions.us.json patches.toml \
    scripts/generate-original-bindings.py scripts/fix-recompiled.sh scripts/resolve-fixup-anchors.py \
    tools/gen_reference_syms.py patches/*.[ch] patches/*.ld patches/*.toml patches/Makefile $tools/N64Recomp) | sha1sum | cut -c1-40)"
if [[ "$(cat $prep/recompiled-stamp 2> /dev/null)" != "$inputs" || ! -f RecompiledFuncs/funcs.h ||
      ! -f RecompiledPatches/patches.c ]]; then
    rm -rf RecompiledFuncs RecompiledPatches elf/BeetleRecomp.original-bound.toml syms/*.toml
    policy="$(sed -n 's/.*--policy-sha256 \([0-9a-f]\{64\}\).*/\1/p' BUILDING.md | head -1)"
    {
        python3 scripts/generate-original-bindings.py resolve --elf elf/recomp.elf \
            --policy config/original-functions.us.json --policy-sha256 "$policy" --base-config BeetleRecomp.toml \
            --output-toml elf/BeetleRecomp.original-bound.toml
        $tools/N64Recomp elf/BeetleRecomp.original-bound.toml
        bash scripts/fix-recompiled.sh
        python3 tools/gen_reference_syms.py elf/recomp.elf syms/beetleadventurerac.us.syms.toml \
            syms/beetleadventurerac.us.datasyms.toml
        make -C patches clean
        make -C patches CC=clang-18 LD=ld.lld-18
        $tools/N64Recomp patches.toml
    } > $prep/n64recomp.log 2>&1 || { tail -30 $prep/n64recomp.log; exit 1; }
    echo "$inputs" > $prep/recompiled-stamp
fi
[[ $mode == prepare ]] && exit 0

# --- 4. The page ---
step "Page"
embuilder build sdl2-mt freetype-legacysjlj > $prep/embuilder.log 2>&1 || { tail -20 $prep/embuilder.log; exit 1; }
[[ -f build-web/build.ninja ]] || emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release     -DBEETLE_ENABLE_FRONTEND=ON -DBEETLE_REQUIRE_PATCHES=ON -DRT64_NAGA_EXECUTABLE="$(command -v naga)"     -DPython3_EXECUTABLE="$(command -v python3)" > $prep/configure.log 2>&1 ||
    { tail -30 $prep/configure.log; rm -f build-web/build.ninja; exit 1; }
ninja -C build-web -j"$jobs" BeetleRecomp > $prep/page.log 2>&1 || { grep -E ' error|FAILED|undefined' $prep/page.log | head -40; exit 1; }
ls -l build-web/BeetleRecomp.{html,js,wasm,data}
