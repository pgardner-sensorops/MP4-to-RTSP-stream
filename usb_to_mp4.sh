#!/usr/bin/env bash
set -euo pipefail

# resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------- defaults ----------
DEVICE="/dev/video0"
WIDTH="1280"
HEIGHT="720"
FPS="30"
INPUT_FORMAT="mjpeg"          # try: mjpeg | yuyv422 | h264
ROUTE="mystream"
PORT="8554"
USE_TIMESTAMP=0
USE_AUDIO=0
AUDIO_DEV="default"
BITRATE="2500k"
GOP_MULTIPLIER=2              # keyframe interval = FPS * GOP_MULTIPLIER
NV_PRESET="fast"              # for NVENC when available
X264_PRESET="medium"          # for libx264 fallback
# --------------------------------

# parse options
ARGS=$(getopt -o d: --long device:,width:,height:,fps:,format:,route:,port:,timestamp,audio,audio-dev:,bitrate:,gop-mult:,nv-preset:,x264-preset: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  echo "Usage: $0 [--device /dev/video0] [--width 1280] [--height 720] [--fps 30] [--format mjpeg] [--route mystream] [--port 8554] [--timestamp] [--audio] [--audio-dev default] [--bitrate 2500k] [--gop-mult 2]" >&2
  exit 1
fi
eval set -- "$ARGS"
while true; do
  case "$1" in
    -d|--device)      DEVICE="$2"; shift 2 ;;
    --width)          WIDTH="$2"; shift 2 ;;
    --height)         HEIGHT="$2"; shift 2 ;;
    --fps)            FPS="$2"; shift 2 ;;
    --format)         INPUT_FORMAT="$2"; shift 2 ;;
    --route)          ROUTE="$2"; shift 2 ;;
    --port)           PORT="$2"; shift 2 ;;
    --timestamp)      USE_TIMESTAMP=1; shift ;;
    --audio)          USE_AUDIO=1; shift ;;
    --audio-dev)      AUDIO_DEV="$2"; shift 2 ;;
    --bitrate)        BITRATE="$2"; shift 2 ;;
    --gop-mult)       GOP_MULTIPLIER="$2"; shift 2 ;;
    --nv-preset)      NV_PRESET="$2"; shift 2 ;;
    --x264-preset)    X264_PRESET="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Internal error parsing options" >&2; exit 1 ;;
  esac
done

# cleanup MediaMTX on exit
cleanup() {
  pkill -f mediamtx || true
}
trap cleanup EXIT

# kill any existing server
pkill -f mediamtx || true

# start MediaMTX (expects mediamtx + mediamtx.yml in this dir)
"$SCRIPT_DIR/mediamtx" "$SCRIPT_DIR/mediamtx.yml" &
MTX_PID=$!

# wait for RTSP port
echo -n "Waiting for MediaMTX on port $PORT"
for i in {1..20}; do
  if nc -z localhost "$PORT"; then
    echo " ✓"
    break
  else
    echo -n .
    sleep 0.25
  fi
  if [ $i -eq 20 ]; then
    echo " failed to start on port $PORT" >&2
    exit 1
  fi
done

# pick encoder (NVENC if present)
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_nvenc"; then
  echo "Using NVIDIA GPU encoder (h264_nvenc)"
  ENC_OPTS=( -c:v h264_nvenc -preset "$NV_PRESET" -rc:v vbr -b:v "$BITRATE" -maxrate:v "$BITRATE" -bufsize:v "$BITRATE" )
else
  echo "NVENC unavailable; falling back to software encoding (libx264)"
  ENC_OPTS=( -c:v libx264 -preset "$X264_PRESET" -tune zerolatency -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BITRATE" )
fi

# timestamp overlay (optional) + full->limited range fix for MJPEG (yuvj*)
FILTER_GRAPH="scale=in_range=full:out_range=tv"
if [ "$USE_TIMESTAMP" -eq 1 ]; then
  FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
  TS_FILTER="drawtext=fontfile=${FONT}:expansion=strftime:fontcolor=white:fontsize=50:box=1:boxcolor=black@0.5:x=10:y=10:text='%Y-%m-%d %H\\:%M\\:%S'"
  FILTER_GRAPH="${FILTER_GRAPH},${TS_FILTER}"
  echo "Timestamp overlay enabled."
else
  echo "Streaming without timestamp overlay."
fi

# input(s)
VIDEO_IN=( -f v4l2 -framerate "$FPS" -video_size "${WIDTH}x${HEIGHT}" -input_format "$INPUT_FORMAT" -i "$DEVICE" )
AUDIO_IN=()
AUDIO_ENC=()
MAPS=( -map 0:v:0 )
if [ "$USE_AUDIO" -eq 1 ]; then
  AUDIO_IN=( -f alsa -thread_queue_size 1024 -i "$AUDIO_DEV" )
  AUDIO_ENC=( -c:a aac -b:a 128k -ar 44100 -ac 2 )
  MAPS+=( -map 1:a:0 )
  echo "Audio enabled from ALSA device: $AUDIO_DEV"
fi

# GOP
GOP=$(( FPS * GOP_MULTIPLIER ))

# publish to MediaMTX (no -rtsp_flags listen)
ffmpeg -hide_banner \
  "${VIDEO_IN[@]}" \
  "${AUDIO_IN[@]}" \
  -use_wallclock_as_timestamps 1 -fflags nobuffer -flags low_delay \
  -vf "$FILTER_GRAPH" -pix_fmt yuv420p \
  -r "$FPS" -g "$GOP" \
  "${ENC_OPTS[@]}" \
  "${AUDIO_ENC[@]}" \
  "${MAPS[@]}" \
  -f rtsp -rtsp_transport tcp \
  "rtsp://localhost:${PORT}/${ROUTE}"
