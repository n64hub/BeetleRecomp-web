# The image tools/build_web.sh builds the page in: donald-duck-goin-quackers-recomp's tools/docker/Dockerfile.web
# (rush-2049-recomp's, the image N64Recomp-browser's tools/publish_pages.sh builds every page in) instruction for
# instruction, so Docker's cache shares its layers: emsdk on Ubuntu 24.04, ninja, ccache, clang with lld, naga 30.0.1
# (WGSL from SPIR-V; dxc comes with rt64) and spirv-opt. Then what BeetleDecomp's build needs (lib/bar-decomp's README,
# Quick start: its IDO compilers and Python packages it fetches itself into lib/bar-decomp) and BeetleRecomp's
# generators (BUILDING.md: N64Recomp, and its MIPS patches with LLVM 18's clang and lld).
# build_web.sh tags it with a hash of this file, so a change here makes the next run build a new one.
FROM emscripten/emsdk:6.0.12
RUN apt-get update && apt-get install -y --no-install-recommends ninja-build ccache clang lld git curl ca-certificates \
    libsdl2-dev libgtk-3-dev xz-utils unzip p7zip-full && rm -rf /var/lib/apt/lists/*
ENV CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal && /opt/cargo/bin/cargo install naga-cli --version 30.0.1 --locked \
    && cp /opt/cargo/bin/naga /usr/local/bin/ && rm -rf /opt/cargo/registry
RUN apt-get update && apt-get install -y --no-install-recommends xdelta3 make pkg-config libdbus-1-dev libfreetype-dev \
    python3-venv && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y --no-install-recommends spirv-tools && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y --no-install-recommends binutils-mips-linux-gnu rsync && rm -rf /var/lib/apt/lists/*
RUN git config --system http.version HTTP/1.1
# BeetleDecomp and BeetleRecomp's generators.
RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3-pip python3-dev libcjson-dev \
    libzstd-dev binutils-dev libelf-dev libpng-dev zlib1g-dev clang-18 lld-18 llvm-18 wget && rm -rf /var/lib/apt/lists/*
