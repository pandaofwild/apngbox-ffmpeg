# apngbox-ffmpeg

The FFmpeg build bundled with **Apng Box** (Windows x64), built from source with only the components the app uses.

- License of the binary: **LGPL 2.1 or later** (no `--enable-gpl`, no `--enable-version3`, no `--enable-nonfree`).
- External libraries: libaom, libopus, libwebp, dav1d (BSD-style licenses) and zlib.
- Not included: OpenH264, x264/x265, HEVC/VVC encoders, FFmpeg's native AAC encoder.
  (Apng Box encodes H.264/AAC through Windows Media Foundation.)

## Releases

Each release carries `ffmpeg.exe` and the **exact source** of every component it was built from
(`*-source.tar.gz`, unmodified upstream tags), so the corresponding source is available next to the binary.
The SHA256 of each asset is listed in the release notes.

## Rebuild

Ubuntu 24.04 (WSL, Docker or CI), cross-compiling with mingw-w64:

```sh
sudo bash scripts/ffmpeg-build/setup-ubuntu.sh
WORK=$HOME/ffbuild bash scripts/ffmpeg-build/build.sh   # → $WORK/out/ffmpeg.exe
```

Or natively in an MSYS2 UCRT64 shell: `bash scripts/ffmpeg-build/setup-msys2.sh` then `bash scripts/ffmpeg-build/build.sh`.

`build.sh` pins every source by tag **and** commit; the exact configure line is printed by `ffmpeg -buildconf`.
