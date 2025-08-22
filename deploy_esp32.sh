#!/bin/bash

# ESP32 Build, Upload, and Monitor Script
# Usage: ./deploy_esp32.sh

set -e  # Exit on any error

# Configuration
# FQBN="esp32:esp32:lilygo_t_display_s3"
# FQBN="esp32:esp32:esp32"
FQBN="esp32:esp32:esp32c3"

PORT="/dev/cu.usbmodem1201" # T-Display-S3
# PORT="/dev/cu.usbserial-0206671E" # TTGO-T1

BAUDRATE="115200"
SKETCH_NAME="VarexBLE.ino"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔨 ESP32 Build & Deploy Script${NC}"
echo "=================================="
echo "Board: $FQBN"
echo "Port: $PORT"
echo "Sketch: $SKETCH_NAME"
echo ""

# Check if sketch file exists
if [ ! -f "$SKETCH_NAME" ]; then
    echo -e "${RED}❌ Error: $SKETCH_NAME not found in current directory${NC}"
    echo "Make sure you're running this script from the directory containing $SKETCH_NAME"
    exit 1
fi

# Check if port exists
if [ ! -e "$PORT" ]; then
    echo -e "${YELLOW}⚠️  Warning: Port $PORT not found${NC}"
    echo "Available ports:"
    ls /dev/cu.* 2>/dev/null || echo "No USB ports found"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${YELLOW}📦 Step 1: Compiling sketch...${NC}"
if arduino-cli compile --fqbn "$FQBN" "$SKETCH_NAME"; then
    echo -e "${GREEN}✅ Compilation successful!${NC}"
else
    echo -e "${RED}❌ Compilation failed!${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}📤 Step 2: Uploading to device...${NC}"
if arduino-cli upload -p "$PORT" --fqbn "$FQBN" "$SKETCH_NAME"; then
    echo -e "${GREEN}✅ Upload successful!${NC}"
else
    echo -e "${RED}❌ Upload failed!${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}📡 Step 3: Starting serial monitor...${NC}"
echo -e "${BLUE}Press CTRL-C to exit monitor${NC}"
echo "=================================="

# Wait a moment for the device to restart
sleep 2

# Start monitoring
arduino-cli monitor -p "$PORT" --config baudrate="$BAUDRATE"