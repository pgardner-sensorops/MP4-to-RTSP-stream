# MP4 to RTSP stream
Simple method to output an RTSP stream based on an mp4

## Installation

Dependencies:
 - Ubuntu/Debian based linux distros:
    ```
    sudo apt update && sudo apt install -y \
        ffmpeg
    ```

## Usage
From the root of this repository run the following:

```
    create_stream.sh --port <port number> --route <route> -p </path/to/.mp4/file>
```

This will create a stream at `rtsp://localhost:<port>/<route>`. This should be accessible on your system's local network as `rtsp://<your host IP>:<port>/<route>`. In order to access this from extenally you will need to set up port forwarding on your router for the port specified in the `create_stream.sh` command. This would be accessible at `rtsp://<your public IP>:<port>/<route>`