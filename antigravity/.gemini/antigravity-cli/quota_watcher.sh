#!/bin/bash

# Background Quota Watcher for Antigravity
# This script refreshes the quota every 5 minutes if agy is running.

QUOTA_FILE="/home/maurice/.gemini/antigravity-cli/quota.txt"

while true; do
    # Only run if agy is actually active
    if pgrep -x "agy" > /dev/null; then
        # Fetch usage and extract percentage (e.g., "80%")
        usage=$(agy --print "\usage" 2>/dev/null | grep -o "[0-9]\+%" | head -n 1)
        
        if [ -n "$usage" ]; then
            echo "$usage" > "$QUOTA_FILE"
        fi
    fi
    
    # Wait 5 minutes before next sync
    sleep 300
done
