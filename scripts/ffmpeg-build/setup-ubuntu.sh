#!/usr/bin/env bash
# Ubuntu 24.04(Docker · WSL · CI)에 build.sh가 쓰는 도구를 설치한다. root로 실행한다.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates git make cmake ninja-build meson nasm pkg-config \
  python3 gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 mingw-w64-x86-64-dev
# libaom · dav1d가 쓰는 스레드는 winpthreads라 posix 스레드 모델의 컴파일러를 쓴다.
update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix
