#!/bin/bash

# SSH helper functions for Norns deployment
# Source this file in deployment scripts

# Load environment variables if .env exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Set defaults if not provided
NORNS_HOST=${NORNS_HOST:-we@norns.local}
NORNS_PASS=${NORNS_PASS:-sleep}
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"}
NORNS_PATH=${NORNS_PATH:-~/dust/code/Foobar}

# SSH helper function
ssh_norns() {
    sshpass -p "$NORNS_PASS" ssh $SSH_OPTS "$NORNS_HOST" "$@"
}

# RSYNC helper function
rsync_norns() {
    sshpass -p "$NORNS_PASS" rsync -e "ssh $SSH_OPTS" "$@"
}

# Test connection
test_connection() {
    echo "Testing connection to $NORNS_HOST..."
    if ssh_norns "echo 'Connection successful'"; then
        echo "✅ Connection successful"
        return 0
    else
        echo "❌ Connection failed"
        return 1
    fi
} 