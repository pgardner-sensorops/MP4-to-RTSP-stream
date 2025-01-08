#!/bin/bash
script_dir="$(cd "$(dirname "$0")" && pwd)"
cd script_dir

path=""
route="mystream"
port="8554"

while getopts ":p:" opt; do
  case ${opt} in
    p ) # Detect the -u (or -url) option
      path=$OPTARG
      shift
      ;;
    --route=* )
      route = *
      shift
      ;;
    --port=* )
      port = *
      shift
      ;;
    \? ) echo "Usage: cmd [-p] <path>"
      ;;
  esac
done

if [ -z "$path" ]; then
  echo "No mp4 video provided. Usage: $0 -p <path>"
  exit 1
fi

pkill -f "mediamtx"
$script_dir/mediamtx $script_dir/mediamtx.yml  &

ffmpeg -re -stream_loop -1 -i $path -c:v libx264 -preset ultrafast -tune zerolatency -f rtsp -rtsp_transport tcp rtsp://localhost:${port}/${route}