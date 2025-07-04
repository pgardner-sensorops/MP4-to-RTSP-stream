#!/usr/bin/env bash
set -euo pipefail

# resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# defaults
VIDEO_PATH=""
ROUTE="mystream"
PORT="8554"
# always define DEC_OPTS to avoid unbound-variable under set -u
DEC_OPTS=()

# parse options
ARGS=$(getopt -o p: -l path:,route:,port: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  echo "Usage: $0 -p <path> [--route <route>] [--port <port>]" >&2
  exit 1
fi
eval set -- "$ARGS"
while true; do
  case "$1" in
    -p|--path)
      VIDEO_PATH="$2"; shift 2 ;; 
    --route)
      ROUTE="$2"; shift 2 ;;
    --port)
      PORT="$2"; shift 2 ;;
    --)
      shift; break ;;
    *)
      echo "Internal error parsing options" >&2
      exit 1 ;;
  esac
done

# require video file
if [[ -z "$VIDEO_PATH" ]]; then
  echo "Error: no video provided."
  echo "Usage: $0 -p <path> [--route <route>] [--port <port>]" >&2
  exit 1
fi

# cleanup MediaMTX on exit
cleanup() {
  pkill -f mediamtx || true
}
trap cleanup EXIT

# kill any existing server
pkill -f mediamtx || true

# start MediaMTX
"$SCRIPT_DIR/mediamtx" "$SCRIPT_DIR/mediamtx.yml" &
MTX_PID=$!

# wait for binding
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

# choose encoder: prefer NVIDIA NVENC if available (no hardware decode)
decoders_cmd="ffmpeg -hide_banner -encoders 2>/dev/null || true"
if eval "$decoders_cmd" | grep -q "h264_nvenc"; then
  echo "Using NVIDIA GPU encoder (h264_nvenc)"
  ENC_OPTS=( -c:v h264_nvenc -preset fast )
else
  echo "NVENC unavailable; falling back to software encoding (libx264)"
  ENC_OPTS=( -c:v libx264 -preset medium -tune zerolatency )
fi

# path to a TrueType font for drawtext
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf

# build drawtext filter with strftime expansion and escaped colons
TS_FILTER="drawtext=fontfile=${FONT}:\
expansion=strftime:\
fontcolor=white:fontsize=24:\
box=1:boxcolor=black@0.5:\
x=10:y=10:\
text='%Y-%m-%d %H\:%M\:%S'"

# stream in a loop with timestamp overlay
ffmpeg \
  "${DEC_OPTS[@]}" \
  -re -stream_loop -1 -i "$VIDEO_PATH" \
  -vf "$TS_FILTER" \
  "${ENC_OPTS[@]}" \
  -f rtsp "rtsp://localhost:${PORT}/${ROUTE}"

