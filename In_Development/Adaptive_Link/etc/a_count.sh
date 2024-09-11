#!/bin/sh

#quick tool to count incoming messages 

# Start socat in the background
socat -u UDP-RECV:5000 - | tee /tmp/socat_output.log &
SOCAT_PID=$!

# Function to count messages per second
count_per_second() {
    while true; do
        sleep 1
        local count=$(wc -l < /tmp/socat_output.log)
        echo "Messages per second: $count"
        > /tmp/socat_output.log  # Clear the log file for the next second
    done
}

count_per_second

# Clean up
kill $SOCAT_PID
