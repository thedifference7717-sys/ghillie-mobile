#!/usr/bin/env bash
# Builds CAMO's wallet library + native/camo_wallet_ffi for iPhone/iPad (arm64, iOS 15+) on macOS with Xcode:
#   bash native/ios/build-ios-lib.sh <camo source dir> <work dir>
# Output: <work dir>/out/libcamo_wallet.a (one static library: bridge + wallet + all dependencies).
# Dependencies are built from pinned, checksummed source releases (same versions as camo's contrib/depends, except
# Boost 1.84: 1.69 does not build with current Xcode).
set -euo pipefail
SRC=$(cd "${1:?camo source}" && pwd); WORK=$(mkdir -p "${2:?work dir}" && cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=$WORK/prefix; mkdir -p "$PREFIX" "$WORK/dl" "$WORK/build" "$WORK/out"
SDK=$(xcrun --sdk iphoneos --show-sdk-path); MIN=15.0; J=$(sysctl -n hw.ncpu)
export CC="$(xcrun --sdk iphoneos -f clang)" CXX="$(xcrun --sdk iphoneos -f clang++)"
export CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN -O2"
# configure's header checks use the preprocessor, which reads CPPFLAGS only: give it the iPhone SDK too
export CPPFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN"
export CXXFLAGS="$CFLAGS" LDFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN"
# a host triplet different from the build Mac (also arm64) makes configure cross-compile instead of running iPhone binaries
HOSTARG="--host=arm-apple-darwin --build=aarch64-apple-darwin"

fetch() { # url sha256 -> extracted dir name on stdout
  local f="$WORK/dl/$(basename "$1")"
  [ -f "$f" ] || curl -fsSL -o "$f" "$1"
  echo "$2  $f" | shasum -a 256 -c - >&2
  tar -C "$WORK/build" -xf "$f"
}
# on failure, show the end of the newest config.log
trap 'f=$(ls -t $(find "$WORK/build" -name config.log 2>/dev/null) 2>/dev/null | head -1); [ -n "$f" ] && tail -n 40 "$f"' ERR
done_mark() { [ -f "$PREFIX/.done-$1" ]; }
mark() { touch "$PREFIX/.done-$1"; }

if ! done_mark openssl; then
  fetch https://github.com/openssl/openssl/releases/download/openssl-3.0.22/openssl-3.0.22.tar.gz \
    67ebca7e50d17383028045486653492195b83db95f8558709701bb47b5c1ef81
  (cd "$WORK/build/openssl-3.0.22" && env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS ./Configure ios64-xcrun no-shared no-tests no-dso \
     no-engine -miphoneos-version-min=$MIN --prefix="$PREFIX" --libdir=lib >/dev/null && make -j$J >/dev/null && make install_sw >/dev/null)
  mark openssl
fi
if ! done_mark sodium; then
  fetch https://github.com/jedisct1/libsodium/releases/download/1.0.18-RELEASE/libsodium-1.0.18.tar.gz \
    6f504490b342a4f8a4c4a02fc9b866cbef8622d5df4e5452b46be121e46636c1
  (cd "$WORK/build/libsodium-1.0.18" && ./configure $HOSTARG --prefix="$PREFIX" --disable-shared --enable-static \
     --enable-minimal=no >/dev/null && make -j$J >/dev/null && make install >/dev/null)
  mark sodium
fi
if ! done_mark expat; then
  fetch https://github.com/libexpat/libexpat/releases/download/R_2_6_0/expat-2.6.0.tar.bz2 \
    ff60e6a6b6ce570ae012dc7b73169c7fdf4b6bf08c12ed0ec6f55736b78d85ba
  (cd "$WORK/build/expat-2.6.0" && ./configure $HOSTARG --prefix="$PREFIX" --disable-shared --enable-static \
     --without-docbook --without-examples --without-tests --without-xmlwf >/dev/null && make -j$J >/dev/null && make install >/dev/null)
  mark expat
fi
if ! done_mark unbound; then
  fetch https://www.nlnetlabs.nl/downloads/unbound/unbound-1.26.1.tar.gz \
    35a6dc0e425a9282c3426d9a3043144011bf0534aed4b73ab62c52aee0af1503
  (cd "$WORK/build/unbound-1.26.1" && ./configure $HOSTARG --prefix="$PREFIX" --disable-shared --enable-static \
     --with-ssl="$PREFIX" --with-libexpat="$PREFIX" --without-pyunbound --without-pythonmodule --disable-flto \
     --with-libunbound-only --disable-gost >/dev/null || { grep -n -B2 -A12 "sizeof (size_t)" config.log | tail -60; exit 1; }
     make -j$J >/dev/null && make install >/dev/null)
  mark unbound
fi
if ! done_mark zmq; then
  fetch https://github.com/zeromq/libzmq/releases/download/v4.3.4/zeromq-4.3.4.tar.gz \
    c593001a89f5a85dd2ddf564805deb860e02471171b3f204944857336295c3e5
  (cd "$WORK/build/zeromq-4.3.4" && ./configure $HOSTARG --prefix="$PREFIX" --disable-shared --enable-static \
     --disable-curve --disable-curve-keygen --disable-perf --without-docs --without-libsodium --disable-Werror >/dev/null \
     && make -j$J >/dev/null && make install >/dev/null)
  mark zmq
fi
if ! done_mark boost; then
  fetch https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.xz \
    2e64e5d79a738d0fa6fb546c6e5c2bd28f88d268a2a080546f74e5ff98f29d0e
  cd "$WORK/build/boost-1.84.0"
  CC=clang CXX=clang++ CFLAGS= CXXFLAGS= CPPFLAGS= LDFLAGS= ./bootstrap.sh --with-libraries=chrono,date_time,filesystem,locale,program_options,regex,serialization,system,thread >/dev/null
  # Boost.Locale needs iconv (part of iOS); -liconv lets its configure check link
  echo "using darwin : iphone : $CXX -arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN -std=c++14 : <linkflags>-liconv ;" > user-config.jam
  ./b2 -j$J -d0 --user-config=user-config.jam toolset=darwin-iphone target-os=iphone architecture=arm address-model=64 \
    abi=aapcs binary-format=mach-o link=static threading=multi variant=release boost.locale.icu=off boost.locale.iconv=on \
    --layout=system --prefix="$PREFIX" install > "$WORK/b2.log" 2>&1 || {
      echo "b2 failed; real errors (configure probes left out):"
      grep -E "error:|failed updating|skipped <" "$WORK/b2.log" | grep -v "/config/\|/build/has_\|_test\.cpp\|has_" | head -60
      tail -20 "$WORK/b2.log"; exit 1; }
  cd "$WORK"
  mark boost
fi

echo "==> CAMO wallet library"
B=$WORK/build/camo; mkdir -p "$B"
cmake -S "$SRC" -B "$B" -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN \
  -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DBoost_USE_STATIC_LIBS=ON -DBOOST_ROOT="$PREFIX" -DBoost_NO_SYSTEM_PATHS=ON -DOPENSSL_ROOT_DIR="$PREFIX" \
  -DSTATIC=ON -DBUILD_GUI_DEPS=ON -DBUILD_TESTS=OFF -DUSE_DEVICE_TREZOR=OFF -DUSE_READLINE=OFF -DBUILD_DOCUMENTATION=OFF \
  -DARCH=armv8-a -DCMAKE_BUILD_TYPE=Release
cmake --build "$B" --target wallet_api -j$J

echo "==> bridge + one static library"
$CXX $CXXFLAGS -std=c++17 -fvisibility=hidden -I"$SRC/src" -I"$PREFIX/include" -c "$HERE/../camo_wallet_ffi.cpp" -o "$WORK/bridge.o"
LIBS=$(find "$B" -name '*.a' -not -path '*CMakeFiles*' | sort)
libtool -static -o "$WORK/out/libcamo_wallet.a" "$WORK/bridge.o" $LIBS "$PREFIX"/lib/lib{boost_*,ssl,crypto,sodium,unbound,expat,zmq}.a 2>&1 | grep -v "has no symbols" || true
ls -la "$WORK/out/libcamo_wallet.a"
echo "camo_ symbols: $(nm -gU "$WORK/out/libcamo_wallet.a" 2>/dev/null | grep -c ' T _camo_')"

echo "==> link check: an iPhone executable using the library resolves every symbol"
$CC $CFLAGS -I"$HERE/.." "$HERE/../test/smoke.c" "$WORK/out/libcamo_wallet.a" -lc++ -liconv -lz \
  -framework Security -framework CoreFoundation -framework SystemConfiguration -o "$WORK/out/link-check"
echo "link check OK"
