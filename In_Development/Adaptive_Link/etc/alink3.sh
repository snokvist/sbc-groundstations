#!/bin/sh

last_value=""
# Create a temporary buffer file
BUFFER_FILE=$(mktemp)

# Function to process the latest message from the buffer
process_message() {
    local msg="$1"
    echo "Processing: $msg"
    # Check if the input is a valid number (integer or float)
  if echo "$msg" | grep -E -q '^[-]?[0-9]+([.][0-9]+)?$'; then
    # If it's a valid number, round it to the nearest integer
    rounded_number=$(printf "%.0f" "$msg")

    # Only update if the value has changed
    if [ "$rounded_number" != "$last_value" ]; then
      
      #echo "Received number: $rounded_number"
      /usr/bin/./channels.sh 0 $rounded_number

      # Update last_value to the current rounded number
    last_value="$rounded_number"
    fi
  
  else
    # If input is not a valid number, print an error message
    #clear
    echo "Invalid input, not a number."
  fi
}

# Start socat in the background to receive UDP messages and save them to the buffer
socat -u UDP-RECV:5000 STDOUT | while read -r msg; do
    echo "$msg" > "$BUFFER_FILE"  # Overwrite buffer with the latest message
done &

# Infinite loop to process the latest message from the buffer every x seconds
while true; do
    if [ -s "$BUFFER_FILE" ]; then
        latest_message=$(tail -n 1 "$BUFFER_FILE")
        process_message "$latest_message"
    fi
    sleep 0.2
done

# Clean up the temporary buffer file on exit
trap 'rm -f "$BUFFER_FILE"' EXIT
