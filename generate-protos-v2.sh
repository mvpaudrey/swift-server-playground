#!/bin/bash

# Script to generate Swift code from Protocol Buffer definitions for grpc-swift 2.x
# Uses locally built protoc plugins from grpc-swift 2.x

set -e

echo "🚀 Generating Swift code from Protocol Buffers (grpc-swift 2.x)..."

# Use locally built grpc-swift 2.x plugins
SWIFT_BUILD_DIR=.build/arm64-apple-macosx/debug
PROTOC_GEN_SWIFT="$SWIFT_BUILD_DIR/protoc-gen-swift-tool"
PROTOC_GEN_GRPC_SWIFT="$SWIFT_BUILD_DIR/protoc-gen-grpc-swift-tool"

PROTO_DIR="Protos"
OUTPUT_DIR_APP="Sources/App/gRPC/Generated"
OUTPUT_DIR_CLIENT="Sources/AFCONClient/Generated"

# Check if plugins exist
if [ ! -f "$PROTOC_GEN_SWIFT" ]; then
    echo "Error: protoc-gen-swift-tool not found"
    echo "Run 'swift build' first to build the plugins"
    exit 1
fi

if [ ! -f "$PROTOC_GEN_GRPC_SWIFT" ]; then
    echo "Error: protoc-gen-grpc-swift-tool not found"
    echo "Run 'swift build' first to build the plugins"
    exit 1
fi

mkdir -p "$OUTPUT_DIR_APP"
mkdir -p "$OUTPUT_DIR_CLIENT"

# Generate Swift code for App module (server-side with GRPCCore)
echo "📦 Generating for App module (Server)..."
protoc \
    --proto_path="$PROTO_DIR" \
    --plugin=protoc-gen-swift="$PROTOC_GEN_SWIFT" \
    --plugin=protoc-gen-grpc-swift="$PROTOC_GEN_GRPC_SWIFT" \
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
    --plugin=protoc-gen-swift="$PROTOC_GEN_SWIFT" \
    --plugin=protoc-gen-grpc-swift="$PROTOC_GEN_GRPC_SWIFT" \
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
echo "✅ Using grpc-swift 2.x (GRPCCore) for code generation"
