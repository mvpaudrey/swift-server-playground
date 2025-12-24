#!/bin/bash

# Script to generate Swift code from Protocol Buffer definitions for grpc-swift 2.x
# Requires: protoc, protoc-gen-swift, protoc-gen-grpc-swift (v2.x)

set -e

PROTO_DIR="Protos"
OUTPUT_DIR_APP="Sources/App/gRPC/Generated"
OUTPUT_DIR_CLIENT="Sources/AFCONClient/Generated"
GRPC_SWIFT_PLUGIN="grpc-swift/grpc-swift-protobuf/.build/debug/protoc-gen-grpc-swift"

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

# Check if protoc-gen-grpc-swift 2.x is available
if [ ! -f "$GRPC_SWIFT_PLUGIN" ]; then
    echo "Error: protoc-gen-grpc-swift 2.x is not built"
    echo "Build with:"
    echo "  git clone --depth 1 --branch 1.0.0 https://github.com/grpc/grpc-swift-protobuf.git"
    echo "  cd grpc-swift-protobuf"
    echo "  swift build --product protoc-gen-grpc-swift"
    exit 1
fi

echo "🚀 Generating Swift code from Protocol Buffers (grpc-swift 2.x)..."

# Create output directories if they don't exist
mkdir -p "$OUTPUT_DIR_APP"
mkdir -p "$OUTPUT_DIR_CLIENT"

# Generate Swift code for App module (server-side with GRPCCore)
echo "📦 Generating for App module (Server)..."
protoc \
    --proto_path="$PROTO_DIR" \
    --plugin="$GRPC_SWIFT_PLUGIN" \
    --swift_out="$OUTPUT_DIR_APP" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUTPUT_DIR_APP" \
    --grpc-swift_opt=Visibility=Public,Server=true,Client=false \
    "$PROTO_DIR/afcon.proto"

echo "✅ Successfully generated Swift code in $OUTPUT_DIR_APP"

# Generate Swift code for AFCONClient module (client-side with GRPCCore)
echo "📦 Generating for AFCONClient module (Client)..."
protoc \
    --proto_path="$PROTO_DIR" \
    --plugin="$GRPC_SWIFT_PLUGIN" \
    --swift_out="$OUTPUT_DIR_CLIENT" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUTPUT_DIR_CLIENT" \
    --grpc-swift_opt=Visibility=Public,Server=false,Client=true \
    "$PROTO_DIR/afcon.proto"

echo "✅ Successfully generated Swift code in $OUTPUT_DIR_CLIENT"
echo ""
echo "Generated files (App):"
ls -lh "$OUTPUT_DIR_APP"
echo ""
echo "Generated files (AFCONClient):"
ls -lh "$OUTPUT_DIR_CLIENT"
echo ""
echo "⚠️  NOTE: grpc-swift 2.x uses GRPCCore instead of GRPC"
echo "   You will need to update your service implementation to use the new API"
