#!/bin/bash

echo "🔄 Enabling Today's Upcoming Endpoint..."
echo ""

cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync

# Step 1: Regenerate protocol buffers
echo "Step 1: Regenerating protocol buffers..."
./generate-protos.sh

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Failed to regenerate protocol buffers"
    echo ""
    echo "You may need to install the protoc tools first:"
    echo "  brew install protobuf swift-protobuf"
    echo ""
    echo "For grpc-swift plugin:"
    echo "  git clone https://github.com/grpc/grpc-swift.git"
    echo "  cd grpc-swift"
    echo "  make plugins"
    echo "  sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/"
    exit 1
fi

echo ""
echo "✅ Protocol buffers regenerated"
echo ""

# Step 2: Uncomment the gRPC method
echo "Step 2: Re-enabling gRPC method in AFCONServiceProvider.swift..."

# Use sed to remove the comment markers
sed -i '' 's/\/\* TEMPORARY: Commented out until protos are regenerated//' Sources/App/gRPC/Server/AFCONServiceProvider.swift
sed -i '' 's/\*\///' Sources/App/gRPC/Server/AFCONServiceProvider.swift

echo "✅ gRPC method re-enabled"
echo ""

# Step 3: Build
echo "Step 3: Building server..."
swift build

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "✅ Build successful"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Today's Upcoming Endpoint is now ENABLED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Now restart the server:"
echo "  swift run Run"
echo ""
echo "Then test the endpoint:"
echo "  curl http://localhost:8080/api/v1/league/6/season/2025/today"
echo ""
