#!/bin/bash

# Simple deployment script for MIDI Thru Machine
# This script deploys the code and provides testing instructions

set -e  # Exit on any error

echo "🚀 Starting MIDI Thru Machine deployment..."

# Configuration
NORNS_HOST="we@norns.local"
NORNS_PATH="~/dust/code/Foobar"

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

# Step 3: Provide testing instructions
echo ""
print_instruction "To test on Norns device, follow these steps:"
echo ""
echo "1. Open Maiden (web interface) at http://norns.local"
echo "2. Navigate to the Foobar script"
echo "3. In the REPL, run:"
echo "   dofile('run_norns_test.lua')"
echo ""
echo "OR"
echo ""
echo "4. Connect to Norns via SSH and run:"
echo "   ssh we@norns.local"
echo "   cd ~/dust/code/Foobar"
echo "   echo \"dofile('run_norns_test.lua')\" | matron"
echo ""
print_status "Deployment completed successfully!"
print_instruction "The MIDI Thru Machine is ready for testing on your Norns device." 