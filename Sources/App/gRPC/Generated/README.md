# Generated Protocol Buffer Code

This directory contains Swift code generated from Protocol Buffer definitions.

## Generating Code

Run the following command from the project root:

```bash
./generate-protos.sh
```

## Prerequisites

You need the following tools installed:

1. **Protocol Buffers Compiler (protoc)**
   ```bash
   brew install protobuf
   ```

2. **Swift Protobuf Plugin**
   ```bash
   brew install swift-protobuf
   ```

3. **gRPC Swift Plugin**
   ```bash
   # Clone and build grpc-swift
   git clone https://github.com/grpc/grpc-swift.git
   cd grpc-swift
   make plugins

   # Copy plugin to PATH
   sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/
   ```

## Generated Files

After running the generation script, you should see:
- `afcon.pb.swift` - Message definitions
- `afcon.grpc.swift` - Service definitions and client/server code

These files are auto-generated and should not be edited manually.
