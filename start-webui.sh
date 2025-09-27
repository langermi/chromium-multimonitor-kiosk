#!/usr/bin/env bash

# Start script for the Chromium Multi-Monitor Kiosk Web Interface
# This script makes it easy to start the web interface from command line or systemd

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
WEBUI_SCRIPT="$SCRIPT_DIR/webui.py"

# Default configuration
DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT="8080"
DEFAULT_DEBUG="false"

# Parse command line arguments
HOST=${1:-$DEFAULT_HOST}
PORT=${2:-$DEFAULT_PORT}
DEBUG=${3:-$DEFAULT_DEBUG}

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed or not in PATH"
    exit 1
fi

# Check if Flask is installed
if ! python3 -c "import flask" &> /dev/null; then
    echo "Error: Flask is not installed"
    echo "Please install it with: pip3 install flask"
    exit 1
fi

# Check if the webui.py script exists
if [ ! -f "$WEBUI_SCRIPT" ]; then
    echo "Error: Web UI script not found at $WEBUI_SCRIPT"
    exit 1
fi

echo "Starting Chromium Multi-Monitor Kiosk Web Interface"
echo "Host: $HOST"
echo "Port: $PORT"
echo "Debug: $DEBUG"
echo ""
echo "Open http://localhost:$PORT in your browser"
echo "Press Ctrl+C to stop the server"
echo ""

# Start the web interface
cd "$SCRIPT_DIR"
if [ "$DEBUG" = "true" ]; then
    python3 "$WEBUI_SCRIPT" --host "$HOST" --port "$PORT" --debug
else
    python3 "$WEBUI_SCRIPT" --host "$HOST" --port "$PORT"
fi