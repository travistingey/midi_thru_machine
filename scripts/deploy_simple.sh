#!/bin/bash

# Simple deployment script for MIDI Thru Machine
# This script deploys the code and provides testing instructions

set -e  # Exit on any error

echo "🚀 Starting MIDI Thru Machine deployment..."

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

print_instruction() {
    echo -e "${BLUE}[INSTRUCTION]${NC} $1"
}

# Step 1: Test connection
print_status "Testing connection to Norns device..."
if ! test_connection; then
    print_error "Cannot connect to Norns device. Please check your configuration."
    exit 1
fi

# Step 2: Run local tests first
print_status "Running local tests..."
if ! make test-local; then
    print_error "Local tests failed! Aborting deployment."
    exit 1
fi
print_status "Local tests passed ✓"

# Step 3: Deploy to Norns
print_status "Deploying to Norns device..."
if ! rsync_norns -av --exclude='.git' ./ "$NORNS_HOST:$NORNS_PATH"; then
    print_error "Deployment failed!"
    exit 1
fi
print_status "Deployment completed ✓"

# Step 4: Provide testing instructions
echo ""
print_instruction "To test on Norns device, follow these steps:"
echo ""
echo "1. Open Maiden (web interface) at http://norns.local"
echo "2. Navigate to the Foobar script"
echo "3. In the REPL, run:"
echo "   dofile('test/run_norns_test.lua')"
echo ""
echo "OR"
echo ""
echo "4. Run automated tests via SSH:"
echo "   make test-norns"
echo ""
echo "OR"
echo ""
echo "5. Connect to Norns via SSH and run:"
echo "   ssh $NORNS_HOST"
echo "   cd $NORNS_PATH"
echo "   busted -o plain test/spec"
echo ""
print_status "Deployment completed successfully!"
print_instruction "The MIDI Thru Machine is ready for testing on your Norns device." 