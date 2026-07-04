#!/usr/bin/env bash
set -euo pipefail

# resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# defaults
PORT="8554"
USE_TIMESTAMP=0

# Collect video/route pairs.
# Each -p adds a video; an optional --route after it names the stream.
# Videos without an explicit --route get auto-named stream1, stream2, …
VIDEO_PATHS=()
ROUTES=()

# parse options
ARGS=$(getopt -o p:t -l path:,route:,port:,timestamp -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  echo "Usage: $0 -p <path> [-p <path2> ...] [--route <route>] [--port <port>] [--timestamp]" >&2
  echo "  Each --route applies to the preceding -p. Unrouted videos get stream1, stream2, …" >&2
  exit 1
fi
eval set -- "$ARGS"

while true; do
  case "$1" in
    -p|--path)
      # If the previous video had a pending route override, it was already stored.
      VIDEO_PATHS+=("$2")
      ROUTES+=("")  # placeholder, may be overwritten by a following --route
      shift 2 ;;
    --route)
      # Apply to the most recent -p
      if [ ${#ROUTES[@]} -eq 0 ]; then
        echo "Error: --route must follow a -p <path>" >&2
        exit 1
      fi
      ROUTES[$(( ${#ROUTES[@]} - 1 ))]="$2"
      shift 2 ;;
    --port)
      PORT="$2"; shift 2 ;;
    -t|--timestamp)
      USE_TIMESTAMP=1; shift ;;
    --)
      shift; break ;;
    *)
      echo "Internal error parsing options" >&2
      exit 1 ;;
  esac
done

# require at least one video
if [ ${#VIDEO_PATHS[@]} -eq 0 ]; then
  echo "Error: no video provided."
  echo "Usage: $0 -p <path> [-p <path2> ...] [--route <route>] [--port <port>] [--timestamp]" >&2
  exit 1
fi

# fill in default route names for any video that wasn't given one
for i in "${!ROUTES[@]}"; do
  if [ -z "${ROUTES[$i]}" ]; then
    ROUTES[$i]="stream$(( i + 1 ))"
  fi
done

# track ffmpeg child PIDs
FFMPEG_PIDS=()

# cleanup MediaMTX and all ffmpeg processes on exit
cleanup() {
  for pid in "${FFMPEG_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
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

# optionally build timestamp filter
FILTER_ARGS=()
if [ "$USE_TIMESTAMP" -eq 1 ]; then
  FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
  TS_FILTER="drawtext=fontfile=${FONT}:\
expansion=strftime:\
fontcolor=white:fontsize=50:\
box=1:boxcolor=black@0.5:\
x=10:y=10:\
text='%Y-%m-%d %H\\:%M\\:%S'"
  FILTER_ARGS=( -vf "$TS_FILTER" )
  echo "Timestamp overlay enabled."
else
  echo "Streaming without timestamp overlay."
fi

# choose codec path:
#   no filter        -> stream copy (zero re-encode, perfect quality, low CPU)
#   timestamp filter -> must re-encode; prefer NVENC, generous bitrate to avoid generational loss
if [ "$USE_TIMESTAMP" -eq 0 ]; then
  echo "Using stream copy (no re-encode)."
  ENC_OPTS=( -c:v copy -c:a copy -bsf:v h264_mp4toannexb )
elif ffmpeg -hide_banner -encoders 2>/dev/null | grep "h264_nvenc" >/dev/null; then
  echo "Using NVIDIA GPU encoder (h264_nvenc) with timestamp overlay."
  ENC_OPTS=(
    -c:v h264_nvenc
    -preset p5
    -tune ll
    -rc:v vbr
    -cq:v 19
    -b:v 0
    -maxrate:v 30M
    -bufsize:v 60M
    -profile:v high
    -pix_fmt yuv420p
    -color_range tv
    -g 60
    -bf 0
    -spatial-aq 1
    -temporal-aq 1
    -aq-strength 8
  )
else
  echo "NVENC unavailable; falling back to software encoding (libx264) with timestamp overlay."
  ENC_OPTS=(
    -c:v libx264
    -preset veryfast
    -tune zerolatency
    -profile:v high
    -pix_fmt yuv420p
    -g 60
    -bf 0
    -crf 18
    -maxrate 30M
    -bufsize 60M
  )
fi

# launch one ffmpeg per video
for i in "${!VIDEO_PATHS[@]}"; do
  echo "Starting stream: rtsp://localhost:${PORT}/${ROUTES[$i]}  ←  ${VIDEO_PATHS[$i]}"
  ffmpeg -hide_banner \
    -fflags +genpts -avoid_negative_ts make_zero \
    -re -stream_loop -1 -i "${VIDEO_PATHS[$i]}" \
    "${FILTER_ARGS[@]}" \
    "${ENC_OPTS[@]}" \
    -f rtsp -rtsp_transport tcp "rtsp://localhost:${PORT}/${ROUTES[$i]}" &
    # -f rtsp "rtsp://localhost:${PORT}/${ROUTES[$i]}" &
  FFMPEG_PIDS+=($!)
done

echo ""
echo "=== All streams running ==="
for i in "${!VIDEO_PATHS[@]}"; do
  echo "  rtsp://localhost:${PORT}/${ROUTES[$i]}"
done
echo "Press Ctrl+C to stop."

# wait for any ffmpeg to exit (or Ctrl+C)
wait -n "${FFMPEG_PIDS[@]}" 2>/dev/null || true
