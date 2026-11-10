#!/usr/bin/env bash
# 앱에 싣는 FFmpeg(Windows x64)를 앱이 쓰는 부품만 넣어 소스에서 빌드한다(2026-11-09).
#
# 왜: BtbN의 win64-lgpl 빌드는 OpenH264(H.264 인코더)를 실행 파일 안에 정적으로 넣는다. Cisco가 특허료를 대신 내는 것은
# Cisco가 만든 바이너리를 사용자가 따로 받을 때뿐이라, 그 빌드를 그대로 배포하면 그 보장을 받지 못한다. HEVC · VVC 인코더
# (kvazaar · vvenc), FFmpeg 자체 AAC 인코더 같은 특허 풀 대상 부품과 쓰지 않는 라이브러리 수십 개도 같이 들어 있었다.
# H.264 · AAC 인코딩은 Windows의 Media Foundation 인코더(h264_mf · aac_mf)로 옮겼으므로(src/runtime/mp4Encoding.ts) 그 부품은
# 빌드에 넣지 않는다. 넣는 외부 라이브러리는 BSD 계열 넷(libaom · libopus · libwebp · dav1d)과 zlib뿐이고 GPL · version3
# 옵션을 켜지 않는다 — 결과물은 LGPL 2.1 이상이다.
#
# 돌리는 곳(둘 다 같은 결과를 내도록 썼다):
#   - Ubuntu 24.04(Docker · WSL · CI): sudo bash scripts/ffmpeg-build/setup-ubuntu.sh 뒤 bash scripts/ffmpeg-build/build.sh
#   - MSYS2 UCRT64 셸: bash scripts/ffmpeg-build/setup-msys2.sh 뒤 bash scripts/ffmpeg-build/build.sh
# 결과: $WORK/out/ffmpeg.exe (기본 WORK = ./.artifacts/ffbuild — git이 무시하는 곳). 넣은 부품은 `ffmpeg -buildconf`로 볼 수 있다.
#
# 부품 목록을 바꿀 때: 앱 소스에서 쓰는 이름(필터 · 인코더 · 디코더 · 입출력 형식)을 아래 목록과 맞추고,
# 실제 FFmpeg를 부르는 jest 묶음(src/runtime/__tests__/*)과 Electron 골든을 새 바이너리로 돌린다.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$PWD/.artifacts/ffbuild}
JOBS=${JOBS:-$(nproc)}
PREFIX=$WORK/prefix
SRC=$WORK/src
OUT=$WORK/out
mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$SRC" "$OUT"

if [ -n "${MSYSTEM:-}" ]; then
  MODE=native
  CROSS=
else
  MODE=cross
  CROSS=x86_64-w64-mingw32-
fi
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
# 크로스 빌드에서 호스트(리눅스)의 .pc가 섞이지 않게 찾는 곳을 prefix로 한정한다.
[ "$MODE" = cross ] && export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig

# 소스: 태그로 받고 태그가 가리키는 커밋을 대조한다(태그를 옮겨 달면 빌드가 멈춘다).
# 갱신할 때: git ls-remote --tags <url> 'refs/tags/<tag>^{}' 로 커밋을 확인해 두 값을 같이 바꾼다.
SOURCES=(
  "ffmpeg|https://github.com/FFmpeg/FFmpeg.git|n8.1.3|1041abdc962f4cc4f394aa8de9dc5236c0c3b9e7"
  "zlib|https://github.com/madler/zlib.git|v1.3.2|da607da739fa6047df13e66a2af6b8bec7c2a498"
  "aom|https://aomedia.googlesource.com/aom|v3.15.3|b141d9c45db236335351c8a4b2a14b3ade27c937"
  "opus|https://gitlab.xiph.org/xiph/opus.git|v1.6.1|22244de5a79bd1d6d623c32e72bf1954b56235be"
  "libwebp|https://chromium.googlesource.com/webm/libwebp|v1.6.0|4fa21912338357f89e4fd51cf2368325b59e9bd9"
  "dav1d|https://code.videolan.org/videolan/dav1d.git|1.5.4|54706fc6bc0cdecab7e9593974a4039cc038fca7"
)

log() { printf '\n[ffmpeg-build] %s\n' "$*"; }

fetch_sources() {
  local entry name url tag commit dir head
  for entry in "${SOURCES[@]}"; do
    IFS='|' read -r name url tag commit <<<"$entry"
    dir=$SRC/$name
    if [ ! -d "$dir/.git" ]; then
      log "받기: $name $tag"
      git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$dir"
    fi
    head=$(git -C "$dir" rev-parse HEAD)
    if [ "$head" != "$commit" ]; then
      echo "[ffmpeg-build] $name $tag 의 커밋이 다릅니다: 기대 $commit · 실제 $head" >&2
      exit 1
    fi
  done
}

# 크로스 빌드용 CMake 설정. 네이티브(MSYS2)에서는 기본값을 쓴다.
cmake_target_flags() {
  if [ "$MODE" = cross ]; then
    printf '%s\n' -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
      "-DCMAKE_C_COMPILER=${CROSS}gcc" "-DCMAKE_CXX_COMPILER=${CROSS}g++" "-DCMAKE_RC_COMPILER=${CROSS}windres" \
      "-DCMAKE_FIND_ROOT_PATH=$PREFIX" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  fi
}

cmake_build() {
  local name=$1; shift
  local flags
  mapfile -t flags < <(cmake_target_flags)
  rm -rf "$SRC/$name/_build"
  cmake -S "$SRC/$name" -B "$SRC/$name/_build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_INSTALL_PREFIX=$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF "${flags[@]}" "$@"
  cmake --build "$SRC/$name/_build" -j "$JOBS"
  cmake --install "$SRC/$name/_build"
}

build_zlib() {
  log 'zlib'
  make -C "$SRC/zlib" -f win32/Makefile.gcc clean >/dev/null
  make -C "$SRC/zlib" -f win32/Makefile.gcc PREFIX="$CROSS" -j "$JOBS" libz.a
  cp "$SRC/zlib/libz.a" "$PREFIX/lib/"
  cp "$SRC/zlib/zlib.h" "$SRC/zlib/zconf.h" "$PREFIX/include/"
}

build_aom() {
  log 'libaom (AV1 인코더만)'
  local toolchain=()
  [ "$MODE" = cross ] && toolchain=("-DCMAKE_TOOLCHAIN_FILE=$SRC/aom/cmake/toolchains/x86_64-mingw-gcc.cmake")
  rm -rf "$SRC/aom/_build"
  # aom 전용 툴체인 파일이 컴파일러를 정하므로 cmake_build의 일반 크로스 설정 대신 그것을 쓴다.
  cmake -S "$SRC/aom" -B "$SRC/aom/_build" -G Ninja -DCMAKE_BUILD_TYPE=Release "${toolchain[@]}" \
    "-DCMAKE_INSTALL_PREFIX=$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0 -DENABLE_TOOLS=0 \
    -DENABLE_NASM=1 -DCONFIG_AV1_DECODER=0
  cmake --build "$SRC/aom/_build" -j "$JOBS"
  cmake --install "$SRC/aom/_build"
}

build_opus() {
  log 'libopus'
  cmake_build opus -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_SHARED_LIBRARY=OFF \
    -DOPUS_FORTIFY_SOURCE=OFF -DOPUS_STACK_PROTECTOR=OFF
}

build_webp() {
  log 'libwebp'
  cmake_build libwebp -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=ON
}

build_dav1d() {
  log 'dav1d (AV1 디코더)'
  local cross=()
  if [ "$MODE" = cross ]; then
    cat >"$SRC/dav1d-cross.ini" <<EOF
[binaries]
c = '${CROSS}gcc'
ar = '${CROSS}gcc-ar'
strip = '${CROSS}strip'
windres = '${CROSS}windres'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
    cross=(--cross-file "$SRC/dav1d-cross.ini")
  fi
  rm -rf "$SRC/dav1d/_build"
  meson setup "$SRC/dav1d/_build" "$SRC/dav1d" "${cross[@]}" --prefix="$PREFIX" --libdir=lib \
    --buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false
  ninja -C "$SRC/dav1d/_build" -j "$JOBS" install
}

# ── FFmpeg 부품 ────────────────────────────────────────────────────────────────────────────────────────
# 앱이 쓰는 것(src/runtime/* · src/index.ts · src/utils/exportCompression.ts)과 테스트가 시험 파일을 만들 때 쓰는 것.
# 특허 풀 대상 인코더(H.264 · HEVC · VVC · MPEG-4 Part 2 · FFmpeg 자체 AAC)는 넣지 않는다.
# ⚠️ 목록은 configure 부품 이름이다(libavformat/allformats.c의 ff_<이름>_muxer 등) — 형식 이름과 다를 수 있고
# (형식 s16le = 부품 pcm_s16le, png_pipe = image_png_pipe) 틀린 이름은 오류 없이 빠진다. 빌드 뒤 -muxers 등으로 대조할 것.

# 프로토콜: 로컬 파일과 표준 입출력만(네트워크 없음).
PROTOCOLS=file,pipe
# 입력 형식: 그림 가져오기(animatedFrameExtraction.ts의 IMAGE_DEMUXERS) · 영상 가져오기(VIDEO_DEMUXERS) ·
# 음악 레이어(mp4AudioMix.ts의 audioDemuxerForDataUrl) · 렌더러 프레임(rawvideo · PNG 연번).
DEMUXERS=gif,apng,image2,image_png_pipe,image_jpeg_pipe,image_webp_pipe,mov,matroska,avi,mp3,wav,ogg,aac,flac,rawvideo
# 출력 형식: APNG · WebP · MP4 · 프레임 PNG · GIF 쓰기 앞의 rawvideo · 사용 가능 검사의 null.
# gif · avi · matroska · wav · s16le은 테스트가 시험 파일을 만들거나 결과를 풀 때 쓴다(특허와 무관한 포장).
MUXERS=apng,webp,mp4,mov,image2,rawvideo,null,gif,avi,matroska,webm,wav,pcm_s16le
ENCODERS=png,apng,libwebp,libwebp_anim,h264_mf,aac_mf,libaom_av1,libopus,rawvideo,wrapped_avframe,pcm_s16le,gif,mjpeg
# 디코더: 그림(PNG · APNG · GIF · JPEG · WebP), 영상 가져오기(H.264 · HEVC · VP8 · VP9 · AV1 · MPEG-4 Part 2 · ProRes ·
# Motion JPEG), 음악(MP3 · AAC · FLAC · Vorbis · Opus · ALAC · PCM).
# ⚠️ H.264 · HEVC 디코더도 특허 풀 대상이다 — 영상 가져오기를 어떻게 할지 정할 때 이 목록에서 뺀다(2026-11-09 결정 대기).
# wrapped_avframe: lavfi 입력(mp4Availability.ts의 color · anullsrc 검사, 테스트의 testsrc · sine)이 이 형식으로 나온다 —
# 디코더가 없으면 "no decoder found for: wrapped_avframe"로 검사가 늘 실패해 MP4가 "사용 불가"로 보인다.
DECODERS=png,apng,gif,mjpeg,webp,h264,hevc,vp8,vp9,libdav1d,mpeg4,prores,rawvideo,wrapped_avframe,mp3float,mp3,aac,flac,vorbis,opus,alac,pcm_*
PARSERS=h264,hevc,vp8,vp9,av1,mpeg4video,mjpeg,png,gif,webp,aac,mpegaudio,flac,opus,vorbis
# 필터: 내보내기 · 가져오기 · 음악 섞기에서 쓰는 것 + 테스트의 시험 신호(testsrc · sine · aevalsrc · concat).
FILTERS=scale,format,fps,showinfo,palettegen,paletteuse,split,lutrgb,alphaextract,alphamerge,premultiply,unpremultiply,setparams,overlay,color,null,nullsink,buffer,buffersink,setpts,trim,anullsrc,amix,apad,aresample,aformat,aeval,asplit,atrim,asetpts,aloop,volume,adelay,anull,abuffer,abuffersink,anullsink,testsrc,sine,aevalsrc,concat

build_ffmpeg() {
  log 'FFmpeg'
  local cross=()
  [ "$MODE" = cross ] && cross=(--cross-prefix="$CROSS" --target-os=mingw32 --arch=x86_64)
  cd "$SRC/ffmpeg"
  [ -f ffbuild/config.mak ] && make distclean >/dev/null 2>&1 || true
  # --enable-d3d11va: 하드웨어 가속을 넣으려는 것이 아니다 — n8.1.3의 mfenc.c가 D3D11 프레임 함수를 CONFIG_D3D11VA로
  # 감싸지 않아 끄면 컴파일이 안 된다(Windows 헤더만 쓰고 외부 라이브러리는 없다. hwaccel은 --disable-everything이 꺼 둔다).
  ./configure "${cross[@]}" --prefix="$PREFIX" --pkg-config=pkg-config --pkg-config-flags=--static \
    --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" --extra-ldexeflags=-static \
    --extra-version=apngbox \
    --disable-everything --disable-autodetect --disable-debug --disable-doc --disable-network \
    --disable-ffprobe --disable-ffplay --enable-ffmpeg --disable-shared --enable-static \
    --enable-w32threads --enable-zlib --enable-mediafoundation --enable-d3d11va \
    --enable-libaom --enable-libopus --enable-libwebp --enable-libdav1d \
    --enable-avdevice --enable-indev=lavfi \
    --enable-protocol="$PROTOCOLS" --enable-demuxer="$DEMUXERS" --enable-muxer="$MUXERS" \
    --enable-encoder="$ENCODERS" --enable-decoder="$DECODERS" --enable-parser="$PARSERS" \
    --enable-filter="$FILTERS" --enable-bsfs
  make -j "$JOBS"
  "${CROSS}strip" -o "$OUT/ffmpeg.exe" ffmpeg.exe
  cd - >/dev/null
}

fetch_sources
build_zlib
build_aom
build_opus
build_webp
build_dav1d
build_ffmpeg
log "완료: $OUT/ffmpeg.exe"
sha256sum "$OUT/ffmpeg.exe"
