# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project creates RTSP video streams from MP4 files or USB cameras using FFmpeg and [MediaMTX](https://github.com/bluenviern/mediamtx) as the RTSP server. It is a collection of bash scripts — there is no build system, test suite, or linter.

## Dependencies

- `ffmpeg` (required)
- `fzf` (required by `menu.sh` for interactive device selection in `usb_to_mp4.sh`)
- `nc` (netcat, used to verify MediaMTX port is listening)
- DejaVu fonts at `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` (for timestamp overlay)

Install: `sudo apt update && sudo apt install -y ffmpeg fzf`

## Key Scripts

- **`create_stream.sh`** — Loops an MP4 file as an RTSP stream. Starts MediaMTX, detects NVENC for GPU encoding, optionally overlays a timestamp.
  - Usage: `./create_stream.sh -p <path/to/file.mp4> [--route mystream] [--port 8554] [--timestamp]`
  - Stream URL: `rtsp://localhost:<port>/<route>`

- **`usb_to_mp4.sh`** — Captures a live USB camera (V4L2) and publishes as an RTSP stream. Supports audio, configurable resolution/FPS/bitrate, and interactive device selection via fzf.
  - Usage: `./usb_to_mp4.sh [--device /dev/video0] [--width 1280] [--height 720] [--fps 30] [--format mjpeg] [--route mystream] [--port 8554] [--timestamp] [--audio] [--bitrate 2500k]`
  - Sources `menu.sh` for the interactive device picker when no `--device` is specified.

- **`menu.sh`** — Reusable fzf-powered menu selection library. Sourced by other scripts, not run directly. Provides `menu_select()` function.

## MediaMTX

The RTSP server binary (`mediamtx`) is checked into the repo at the project root (currently x86_64). Architecture-specific tarballs are in `arm64/` and `x86_64/` directories (version 1.15.6). Configuration is in `mediamtx.yml`.

Both streaming scripts start MediaMTX automatically and kill it on exit via a trap. The default RTSP port is **8554**.

Key MediaMTX config: authentication is disabled (any user can publish/read), RTSP/RTMP/HLS/WebRTC/SRT protocols are all enabled.

## Architecture Notes

- All scripts resolve their own directory (`SCRIPT_DIR`) and `cd` into it, so they work regardless of where they're invoked from.
- Both streaming scripts share the same pattern: parse args → start MediaMTX → wait for port → detect NVENC vs libx264 → build FFmpeg filter graph → run FFmpeg.
- The encoder selection logic checks `ffmpeg -encoders` for `h264_nvenc` and falls back to `libx264` with `zerolatency` tune.
- `.gitignore` excludes `*.mp4` files — the MP4 files in the working tree are test videos, not tracked.
