#!/usr/bin/env bash
# MSYS2 UCRT64 셸에 build.sh가 쓰는 도구를 설치한다.
set -euo pipefail
if [ "${MSYSTEM:-}" != UCRT64 ]; then
  echo 'MSYS2 UCRT64 셸에서 실행하세요(ucrt64.exe).' >&2
  exit 1
fi
pacman -S --needed --noconfirm git make diffutils \
  mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-meson mingw-w64-ucrt-x86_64-nasm mingw-w64-ucrt-x86_64-pkgconf
