#!/bin/sh
counter=0
while true; do
    echo -e "\n\n\n\n\n"
    counter=$((counter + 1))
    clear
    echo "run:$counter disk guardian is being executed every 10 seconds to simulate live reload, this should be for dev only, executing disk-guardian again"

    # Start disk-guardian in the background
    bash ./disk-guardian.sh &
    PID=$!  # Save the process ID

    # Let it run for 4 seconds (or however long you want)
    sleep 4

    # Stop disk-guardian
    kill $PID

    # Optional: wait for it to actually exit
    wait $PID 2>/dev/null
done