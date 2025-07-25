#!/bin/bash

# Deploy and Test Script for MIDI Thru Machine
# This script deploys the code to Norns and runs the E2E test

set -e  # Exit on any error

echo "🚀 Starting MIDI Thru Machine deployment and test..."

# Configuration
NORNS_HOST="we@norns.local"
NORNS_PATH="~/dust/code/Foobar"
TEST_SCRIPT="test_norns.lua"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Run local tests first
print_status "Running local tests..."
if ! lua test_e2e.lua; then
    print_error "Local tests failed! Aborting deployment."
    exit 1
fi
print_status "Local tests passed ✓"

# Step 2: Deploy to Norns
print_status "Deploying to Norns device..."
if ! make deploy PI_HOST="$NORNS_HOST"; then
    print_error "Deployment failed!"
    exit 1
fi
print_status "Deployment completed ✓"

# Step 3: Test on Norns
print_status "Running E2E test on Norns device..."
ssh "$NORNS_HOST" "cd $NORNS_PATH && echo 'dofile(\"run_norns_test.lua\")' | norns"

# Check the exit code
if [ $? -eq 0 ]; then
    print_status "🎉 Norns E2E test PASSED!"
    echo ""
    echo "✅ Deployment and testing completed successfully!"
    echo "📱 The MIDI Thru Machine is ready to use on your Norns device."
else
    print_error "❌ Norns E2E test FAILED!"
    echo ""
    echo "🔧 Troubleshooting tips:"
    echo "1. Check that the Norns device is connected and accessible"
    echo "2. Verify that Lua is available on the Norns device"
    echo "3. Check the test output above for specific error messages"
    echo "4. Ensure all dependencies are properly installed"
    exit 1
fi 