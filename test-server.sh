#!/bin/bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync

echo "Testing server startup..."
echo ""

# Try to build
echo "Building..."
swift build --target Run 2>&1 | tail -30

echo ""
echo "Build exit code: $?"
