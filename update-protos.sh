#!/bin/bash

# Regenerate protocol buffer files after updating afcon.proto
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync

echo "🔨 Regenerating protocol buffer files..."

./generate-protos.sh

if [ $? -eq 0 ]; then
    echo "✅ Protocol buffers regenerated successfully"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Implement getTodayUpcoming() in AFCONServiceProvider.swift"
    echo "   2. Rebuild the server: swift build"
    echo "   3. Restart the server: swift run Run"
else
    echo "❌ Failed to regenerate protocol buffers"
    exit 1
fi
