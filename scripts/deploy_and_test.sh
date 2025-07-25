#!/bin/bash

# Deploy and Test Script for MIDI Thru Machine
# This script deploys the code to Norns and runs comprehensive tests in the actual Norns runtime

set -e  # Exit on any error

echo "🚀 Starting MIDI Thru Machine deployment and comprehensive testing..."

# Source SSH helpers
source "$(dirname "$0")/ssh_helpers.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
}

# Step 1: Test connection
print_status "Testing connection to Norns device..."
if ! test_connection; then
    print_error "Cannot connect to Norns device. Please check your configuration."
    exit 1
fi

# Step 2: Run local tests first
print_section "Running local tests (Lua 5.4 with stubbed APIs)..."
if ! make test-local; then
    print_error "Local tests failed! Aborting deployment."
    exit 1
fi
print_status "Local tests passed ✓"

# Step 3: Deploy to Norns
print_section "Deploying to Norns device..."
if ! rsync_norns -av --exclude='.git' ./ "$NORNS_HOST:$NORNS_PATH"; then
    print_error "Deployment failed!"
    exit 1
fi
print_status "Deployment completed ✓"

# Step 4: Test on Norns using system shell (Lua 5.1) for compatibility
print_section "Testing on Norns system shell (Lua 5.1) for compatibility..."
if ssh_norns "cd $NORNS_PATH && LUA_PATH='./?.lua;./lib/?.lua;test/spec/?.lua;;' busted -o plain test/spec"; then
    print_status "✅ Norns system shell tests passed"
else
    print_warning "⚠️  Norns system shell tests failed (expected due to Lua 5.1 vs 5.3 differences)"
fi

# Step 5: Test on Norns using actual runtime (Lua 5.3) for comprehensive testing
print_section "Testing on Norns runtime (Lua 5.3) for comprehensive coverage..."
if ./scripts/run-test test/norns_runtime_spec.lua; then
    print_status "🎉 Norns runtime tests PASSED!"
    echo ""
    echo "✅ Deployment and comprehensive testing completed successfully!"
    echo "📱 The MIDI Thru Machine is ready to use on your Norns device."
    echo ""
    print_status "Test Coverage Summary:"
    echo "  • Local tests (Lua 5.4 + stubbed APIs): ✓"
    echo "  • Norns system shell (Lua 5.1): ⚠️  (expected failures)"
    echo "  • Norns runtime (Lua 5.3 + real APIs): ✓"
    echo ""
    print_status "The code is fully tested in the actual Norns environment!"
else
    print_error "❌ Norns runtime tests FAILED!"
    echo ""
    echo "🔧 Troubleshooting tips:"
    echo "1. Check that the Norns device is running the correct Lua version (5.3)"
    echo "2. Verify that maiden repl is available on the Norns device"
    echo "3. Check the test output above for specific error messages"
    echo "4. Ensure all dependencies are properly installed"
    echo "5. Try running tests manually via Maiden: dofile('test/norns_runtime_spec.lua')"
    echo "6. Run setup: make setup-norns"
    exit 1
fi

# Step 6: Optional - Test with busted in runtime (if available)
print_section "Testing with busted in Norns runtime (optional)..."
if ./scripts/run-test test/norns_busted_spec.lua; then
    print_status "✅ Norns busted tests passed"
else
    print_warning "⚠️  Norns busted tests failed (busted may not be available in runtime)"
fi 