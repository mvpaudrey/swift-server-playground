#!/bin/bash
#
# sync-fixtures.sh
# Wrapper script for syncing fixtures to the database
#
# Usage:
#   ./sync-fixtures.sh <leagueID> <season> [competition]
#
# Examples:
#   ./sync-fixtures.sh 2 2025                    # Champions League (auto-detected)
#   ./sync-fixtures.sh 39 2024 "Premier League"  # Premier League with custom name
#   ./sync-fixtures.sh --help                    # Show help
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if grpcurl is installed
if ! command -v grpcurl &> /dev/null; then
    echo "❌ grpcurl is not installed"
    echo ""
    echo "Install it with:"
    echo "  brew install grpcurl"
    echo ""
    exit 1
fi

# Run the Swift script
swift "${SCRIPT_DIR}/Scripts/sync-fixtures.swift" "$@"
