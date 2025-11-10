#!/bin/bash

# Script to generate Swift code from Protocol Buffer definitions
# Requires: protoc and protoc-gen-swift, protoc-gen-grpc-swift

set -e

PROTO_DIR="Protos"
OUTPUT_DIR_APP="Sources/App/gRPC/Generated"
OUTPUT_DIR_CLIENT="Sources/AFCONClient/Generated"

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed"
    echo "Install with: brew install protobuf"
    exit 1
fi

# Check if protoc-gen-swift is installed
if ! command -v protoc-gen-swift &> /dev/null; then
    echo "Error: protoc-gen-swift is not installed"
    echo "Install with: brew install swift-protobuf"
    exit 1
fi

# Check if protoc-gen-grpc-swift is installed
if ! command -v protoc-gen-grpc-swift &> /dev/null; then
    echo "Error: protoc-gen-grpc-swift is not installed"
    echo "Install with:"
    echo "  git clone https://github.com/grpc/grpc-swift.git"
    echo "  cd grpc-swift"
    echo "  make plugins"
    echo "  cp .build/release/protoc-gen-grpc-swift /usr/local/bin/"
    exit 1
fi

echo "Generating Swift code from Protocol Buffers..."

# Create output directories if they don't exist
mkdir -p "$OUTPUT_DIR_APP"
mkdir -p "$OUTPUT_DIR_CLIENT"

# Generate Swift code for App module (server-side)
echo "📦 Generating for App module..."
protoc \
    --proto_path="$PROTO_DIR" \
    --swift_out="$OUTPUT_DIR_APP" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUTPUT_DIR_APP" \
    --grpc-swift_opt=Visibility=Public \
    "$PROTO_DIR/afcon.proto"

echo "✅ Successfully generated Swift code in $OUTPUT_DIR_APP"

# Generate Swift code for AFCONClient module (client-side, used by iOS)
echo "📦 Generating for AFCONClient module..."
protoc \
    --proto_path="$PROTO_DIR" \
    --swift_out="$OUTPUT_DIR_CLIENT" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUTPUT_DIR_CLIENT" \
    --grpc-swift_opt=Visibility=Public \
    "$PROTO_DIR/afcon.proto"

echo "✅ Successfully generated Swift code in $OUTPUT_DIR_CLIENT"
echo ""
echo "Generated files (App):"
ls -lh "$OUTPUT_DIR_APP"
echo ""
echo "Generated files (AFCONClient):"
ls -lh "$OUTPUT_DIR_CLIENT"
