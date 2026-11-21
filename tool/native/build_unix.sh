#!/usr/bin/env bash
# Builds libjxl_native for one target into dist/<target>/.
# usage: tool/native/build_unix.sh <target>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <target>" >&2
  exit 2
fi

target=$1
root=$(cd "$(dirname "$0")/../.." && pwd)
cache=${JXL_NATIVE_CACHE:-"$root/.native-cache"}
source_dir="$cache/sources/libjxl"
build="$cache/build/$target"
dist="$root/dist/$target"

for tool in git cmake ninja python3; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done

read_versions() {
  python3 - "$root/native/versions.json" "$1" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))["libjxl"][sys.argv[2]]
print(" ".join(value) if isinstance(value, list) else value)
PY
}

url=$(read_versions repository)
commit=$(read_versions commit)
read -r -a submodules <<<"$(read_versions submodules)"
if [[ "$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]]; then
  rm -rf "$source_dir"
  git clone --quiet --filter=blob:none --no-checkout "$url" "$source_dir"
  git -C "$source_dir" fetch --quiet --depth 1 origin "$commit"
  git -C "$source_dir" checkout --quiet --detach "$commit"
fi
# Submodule commits are pinned by the libjxl commit itself.
git -C "$source_dir" submodule update --quiet --init --depth 1 "${submodules[@]}"

cmake_args=(
  -S "$root/native"
  -B "$build"
  -G Ninja
  -DCMAKE_BUILD_TYPE=MinSizeRel
  -DLIBJXL_SOURCE_DIR="$source_dir"
)

case "$target" in
  macos-arm64)
    cmake_args+=( -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 )
    ext=dylib ;;
  macos-x64)
    cmake_args+=( -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 )
    ext=dylib ;;
  ios-device-arm64)
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib ;;
  ios-simulator-arm64)
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib ;;
  ios-simulator-x64)
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib ;;
  android-arm64|android-arm|android-x64)
    ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${ANDROID_NDK_LATEST_HOME:-}}}
    [[ -n "$ndk" ]] || { echo "set ANDROID_NDK_HOME" >&2; exit 1; }
    case "$target" in
      android-arm64) abi=arm64-v8a ;;
      android-arm) abi=armeabi-v7a ;;
      android-x64) abi=x86_64 ;;
    esac
    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="$abi"
      -DANDROID_PLATFORM=21
      -DANDROID_STL=c++_static
      # 16 KB page-size alignment required for Android 15+ devices.
      -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON
    )
    ext=so ;;
  linux-x64)
    ext=so ;;
  linux-arm64)
    if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
      command -v aarch64-linux-gnu-g++ >/dev/null || {
        echo "install g++-aarch64-linux-gnu for linux-arm64" >&2
        exit 1
      }
      cmake_args+=(
        -DCMAKE_SYSTEM_NAME=Linux
        -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
        -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++
      )
    fi
    ext=so ;;
  *)
    echo "unsupported target: $target" >&2
    exit 2 ;;
esac

rm -rf "$build"
mkdir -p "$dist"
cmake "${cmake_args[@]}"
cmake --build "$build" --target jxl_native --parallel

library=$(find "$build" -type f -name "libjxl_native.$ext" -print -quit)
[[ -n "$library" ]] || { echo "built library not found" >&2; exit 1; }
cp "$library" "$dist/libjxl_native.$ext"
case "$target" in
  macos-*|ios-*) strip -x "$dist/libjxl_native.$ext" ;;
  android-*)
    llvm_strip=$(find "$ndk/toolchains/llvm/prebuilt" -path '*/bin/llvm-strip' -print -quit)
    "$llvm_strip" --strip-unneeded "$dist/libjxl_native.$ext" ;;
  linux-*) strip --strip-unneeded "$dist/libjxl_native.$ext" ;;
esac
gzip -9 -n -c "$dist/libjxl_native.$ext" > "$dist/libjxl_native.$ext.gz"

echo "$dist/libjxl_native.$ext"
