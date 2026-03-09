#!/bin/bash

# Disk Guardian - A simple script to monitor disk capacity, send alerts and automatically stop containers if necessary.

# diskPathsList=(/dev/nvme0n1p8 /dev/nvme0n1p8)
# downloaderContainerNames=(dashboard-dev idp-server)
# pollingRate=10
# warningThreshold=50
# stoppingThreshold=51
# WEBHOOK_URL=http://localhost:80/disk_guard


# Disk paths (space-separated string for env var)
# Dynamically get all directories mounted under /check
echo "disk-guardian running. disk guardian is a simply bash script to monitor disk space and send warnings, and stop specified containers when disk usage exceeds specific limits, defaults are 90% to notify and 95% to stop other contianer, notifications sent via webhooks  works with ntfy"
diskPathsList=()
for dir in /check/*; do
    # Only add if it exists and is a directory
    [ -d "$dir" ] && diskPathsList+=("$dir")
done

echo "Monitoring paths: ${diskPathsList[@]}"

# diskPathsList=(${DISK_PATHS})
# echo $diskPathsList

# Containers to stop
downloaderContainerNames=(${DOWNLOADER_CONTAINERS:-idp-server dashboard-dev})
echo $downloaderContainerNames

# Polling interval in seconds
pollingRate=${POLLING_RATE:-10}
echo "$pollingRate"

# Thresholds
warningThreshold=${WARNING_THRESHOLD:-50}
stoppingThreshold=${STOPPING_THRESHOLD:-51}
echo "$warningThreshold"
echo "$stoppingThreshold"

# Webhook URL
WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:80/disk_guard}
echo "$WEBHOOK_URL"

declare -A diskWarned
declare -A diskStopped

for disk in "${diskPathsList[@]}"; do
    diskWarned[$disk]=false
    diskStopped[$disk]=false
done

notifyStoppingContainers(){
    local disk_path=$1
    local usage=$2
    local stoppingDownloadersMsg=$3

    # JSON payload depends on the service
    local message="Warning: Disk $disk_path usage at ${usage}%. $stoppingDownloadersMsg"

    echo "$(date '+%Y-%m-%d %H:%M:%S') $message"

    curl -s -d "$message" "$WEBHOOK_URL" > /dev/null
}

stop_downloaders_and_notify() {
    local stoppedAny=false
    local disk=$1
    local usage=$2
    local messsage
    for container in "${downloaderContainerNames[@]}"; do
        if [ "$(docker ps --filter "name=$container" --filter "status=running" -q)" ]; then
            docker stop "$container"
            stoppedAny=true
        fi
    
    done
    if [ "$stoppedAny" = true ]; then
        message="$disk $usage Stopped downloaders due to high disk usage"
    else
        message="$disk usege at $usage No containers to stop, check container list, something else may be causing drive overload"
    fi
    notifyStoppingContainers "$message"

}

notify(){
    local disk_path=$1
    local usage=$2

    # JSON payload depends on the service
    local message="Warning: Disk $disk_path usage at ${usage}%"

    echo "$(date '+%Y-%m-%d %H:%M:%S') $message"

    curl -s -d "$message" "$WEBHOOK_URL" > /dev/null
}


# function checkDiskUsage(disk)
check_disk_usage(){
    local disk_path=$1
    local use

    use=$(df -P "$disk_path" | awk 'NR==2 {gsub("%","",$5); print $5}')
    echo "$use"
}


check_disks(){
    for disk in "$@"; do
        usage=$(check_disk_usage "$disk")

        if (( usage > warningThreshold )) && [ "${diskWarned[$disk]}" != "true" ]; then
            notify "$disk" "$usage"
            diskWarned[$disk]="true"
        fi

        if (( usage > stoppingThreshold )) && [ "${diskStopped[$disk]}" != "true" ]; then
            stop_downloaders_and_notify "$disk" "$usage"
            diskStopped[$disk]="true"
        fi

        # Reset state if usage drops below warning threshold
        if (( $usage < $warningThreshold )); then
            diskWarned[$disk]=false
            diskStopped[$disk]=false
        fi
    done
}

while true; do
    check_disks "${diskPathsList[@]}"
    sleep $pollingRate
done