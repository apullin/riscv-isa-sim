#!/bin/sh

set -eu

usage()
{
  cat <<'EOF'
Usage: scripts/build-clang-perf.sh [CONFIGURE-OPTION...]

Configure and build an optimized Spike binary with Clang and ThinLTO.  The
build directory must be empty so that objects compiled with different flags
cannot be reused accidentally.

Environment variables:
  SPIKE_BUILD_DIR          Build directory (default: build-clang-perf)
  SPIKE_PREFIX             Install prefix (default: BUILD_DIR/install)
  SPIKE_LLVM_VERSION       Versioned LLVM tool suffix (default: 21)
  SPIKE_JOBS               Parallel build jobs (default: online CPUs, max 16)
  SPIKE_PERF_FLAGS         C/C++ optimization flags
                           (default: -O3 -march=native -flto=thin)
  SPIKE_EXTRA_CFLAGS       Additional C compiler flags
  SPIKE_EXTRA_CXXFLAGS     Additional C++ compiler flags
  SPIKE_EXTRA_LDFLAGS      Additional linker flags
  SPIKE_PGO_GENERATE_DIR   Build an instrumented binary writing raw profiles
  SPIKE_PGO_PROFILE        Build using an existing merged .profdata file
  RISCV_FAST_ALU_CFLAGS    Optional flags for selected integer handlers
  CC, CXX, AR, RANLIB      LLVM tool overrides
  MAKE                     Make implementation (default: make)

SPIKE_PGO_GENERATE_DIR and SPIKE_PGO_PROFILE are mutually exclusive.  Train
an instrumented binary with representative workloads, merge its .profraw
files with llvm-profdata, then use a separate build directory with
SPIKE_PGO_PROFILE set to the merged file.

Zen 2 benchmark configuration:
  RISCV_FAST_ALU_CFLAGS=-mno-bmi scripts/build-clang-perf.sh
EOF
}

die()
{
  echo "build-clang-perf: $*" >&2
  exit 1
}

require_tool()
{
  command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

case "${1-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

src_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${SPIKE_BUILD_DIR:-"$src_dir/build-clang-perf"}

if test -d "$build_dir" &&
   test -n "$(find "$build_dir" -mindepth 1 -maxdepth 1 -print -quit)"; then
  die "build directory is not empty: $build_dir"
fi

mkdir -p "$build_dir"
build_dir=$(CDPATH= cd -- "$build_dir" && pwd)
prefix=${SPIKE_PREFIX:-"$build_dir/install"}

llvm_version=${SPIKE_LLVM_VERSION:-21}
cc=${CC:-clang-$llvm_version}
cxx=${CXX:-clang++-$llvm_version}
ar=${AR:-llvm-ar-$llvm_version}
ranlib=${RANLIB:-llvm-ranlib-$llvm_version}
make=${MAKE:-make}

require_tool "$cc"
require_tool "$cxx"
require_tool "$ar"
require_tool "$ranlib"
require_tool "$make"

clang_version=$($cc --version | sed -n '1p')
case "$clang_version" in
  *"clang version $llvm_version."*|*"clang version $llvm_version "*) ;;
  *) die "expected Clang $llvm_version, found: $clang_version" ;;
esac

jobs=${SPIKE_JOBS:-}
if test -z "$jobs"; then
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
fi
case "$jobs" in
  ''|*[!0-9]*) die "SPIKE_JOBS must be a positive integer" ;;
esac
test "$jobs" -gt 0 || die "SPIKE_JOBS must be a positive integer"
if test -z "${SPIKE_JOBS:-}" && test "$jobs" -gt 16; then
  jobs=16
fi

perf_flags=${SPIKE_PERF_FLAGS:-"-O3 -march=native -flto=thin"}
cflags="$perf_flags${SPIKE_EXTRA_CFLAGS:+ $SPIKE_EXTRA_CFLAGS}"
cxxflags="$perf_flags${SPIKE_EXTRA_CXXFLAGS:+ $SPIKE_EXTRA_CXXFLAGS}"
ldflags="-flto=thin${SPIKE_EXTRA_LDFLAGS:+ $SPIKE_EXTRA_LDFLAGS}"

pgo_generate_dir=${SPIKE_PGO_GENERATE_DIR:-}
pgo_profile=${SPIKE_PGO_PROFILE:-}
if test -n "$pgo_generate_dir" && test -n "$pgo_profile"; then
  die "SPIKE_PGO_GENERATE_DIR and SPIKE_PGO_PROFILE are mutually exclusive"
fi

if test -n "$pgo_generate_dir"; then
  mkdir -p "$pgo_generate_dir"
  pgo_generate_dir=$(CDPATH= cd -- "$pgo_generate_dir" && pwd)
  pgo_flag="-fprofile-generate=$pgo_generate_dir"
  cflags="$cflags $pgo_flag"
  cxxflags="$cxxflags $pgo_flag"
  ldflags="$ldflags $pgo_flag"
elif test -n "$pgo_profile"; then
  test -f "$pgo_profile" || die "PGO profile not found: $pgo_profile"
  pgo_profile_dir=$(CDPATH= cd -- "$(dirname -- "$pgo_profile")" && pwd)
  pgo_profile="$pgo_profile_dir/$(basename -- "$pgo_profile")"
  pgo_flag="-fprofile-use=$pgo_profile"
  profile_warnings="-Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
  cflags="$cflags $pgo_flag $profile_warnings"
  cxxflags="$cxxflags $pgo_flag $profile_warnings"
  ldflags="$ldflags $pgo_flag"
fi

echo "Configuring Clang $llvm_version ThinLTO build in $build_dir"
(
  cd "$build_dir"
  CC="$cc" \
  CXX="$cxx" \
  AR="$ar" \
  RANLIB="$ranlib" \
  CFLAGS="$cflags" \
  CXXFLAGS="$cxxflags" \
  LDFLAGS="$ldflags" \
    "$src_dir/configure" --prefix="$prefix" "$@"
)

echo "Building Spike with $jobs jobs"
"$make" -C "$build_dir" -j"$jobs" \
  RISCV_FAST_ALU_CFLAGS="${RISCV_FAST_ALU_CFLAGS:-}" spike

echo "Built $build_dir/spike"
