#!/bin/bash

echo "Disk Guardian is running — monitoring disk usage and sending alerts."
echo "Defaults: 90% to warn, 95% to stop containers. Notifications via webhooks (ntfy compatible)."

# Disk paths (space-separated string for env var)
# Dynamically get all directories mounted under /check
diskPathsList=()
for dir in /check/*; do
    # Only add if it exists and is a directory
    [ -d "$dir" ] && diskPathsList+=("$dir")
done

# Containers to stop
read -ra downloaderContainerNames <<< "$DOWNLOADER_CONTAINERS"

# Polling interval in seconds
pollingRate=${POLLING_RATE:-10}
# Thresholds
warningThreshold=${WARNING_THRESHOLD:-90}
stoppingThreshold=${STOPPING_THRESHOLD:-95}
# Webhook URL
WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:80/disk_guard}

declare -A diskWarned
declare -A diskStopped

verify_disk_paths() {
    local exit_no_valid_paths=true
    local newDiskList=()   # no spaces around '='

    # check if initial list is empty
    if [ "${#diskPathsList[@]}" -eq 0 ]; then
        echo "ERROR: No directories found to monitor under /check."
        exit 1
    fi

    for disk in "${diskPathsList[@]}"; do
        # skip invalid disks

        #disk doesnt exist
        if [ ! -d "$disk" ]; then
            echo "WARNING: Disk path $disk does not exist or is not a directory."
            continue
        fi

        #disk not readable
        if [ ! -r "$disk" ]; then
            echo "WARNING: Disk path $disk is not readable. Monitoring may fail."
            continue
        fi

        #disk not accessible
        if ! df "$disk" >/dev/null 2>&1; then
            echo "WARNING: Disk path $disk is not accessible by df."
            continue
        fi

        # if we get here, disk is valid
        exit_no_valid_paths=false
        newDiskList+=("$disk")
    done

    if [ "$exit_no_valid_paths" = true ]; then
        echo "CRITICAL WARNING: No valid disks"
        exit 1
    fi

    # update global array and normalize paths
    diskPathsList=("${newDiskList[@]}")
    diskPathsList=( "${diskPathsList[@]%/}" )   # remove trailing slashes

    echo "Monitoring paths: ${diskPathsList[*]}"
}

verify_containers_list(){
    local missing=()
    local not_running=()

    #check containers list isnt empty
    if [ ${#downloaderContainerNames[@]} -eq 0 ]; then
        echo "WARNING: No containers specified, script will operate without stopping any containers"
    fi

    for container in "${downloaderContainerNames[@]}"; do
        #verify container exists
        if ! docker ps -a --format '{{.Names}}' | grep -qw "$container"; then
            missing+=("$container")
            continue #skip next if since container doesnt exist
        fi

        #verify container is currently running
        if ! docker ps --format '{{.Names}}' | grep -qw "$container"; then
            not_running+=("$container")
        fi
    done

    #notify missing containers
    if [ ${#missing[@]} -gt 0 ]; then
        echo "WARNING: The following containers are missing: ${missing[@]}"
    fi

    #notify containers not running
    if [ ${#not_running[@]} -gt 0 ]; then
        echo "WARNING: The following containers are not currently running: ${not_running[*]}"
    fi


}

verify_threshold(){
    local threshold=$1
    local val=$2
    local re='^[0-9]+$'

    #check not null
    if [ -z "$threshold" ]; then  
        echo "ERROR: $val is not set."
        exit 1
    fi
    
    #check number
    if ! [[ "$threshold" =~ $re ]]; then
        echo "ERROR: $val is not a valid integer: $threshold"
        exit 1
    fi 

    #check in valid range
    if ! (( $threshold >= 0 && $threshold <= 100 )); then
        echo "ERROR: $val must be between 0 and 100"
        exit 1
    fi
}

verify_both_thresholds(){
    local warning=$1
    local stopping=$2

    verify_threshold "$warning" "warningThreshold"
    verify_threshold "$stopping" "stoppingThreshold"

    #check threshold size relationshoip
    if (( stopping < warning )); then
        echo "ERROR: STOPPING_THRESHOLD ($stopping) cannot be less than WARNING_THRESHOLD ($warning)"
        exit 1
    elif (( stopping == warning )); then
        echo "WARNING: STOPPING_THRESHOLD equals WARNING_THRESHOLD — this may cause duplicate alerts"
    fi
}


verify_WEBHOOK_URL(){
    #check webhook url exists
    if [ -z "$WEBHOOK_URL" ]; then
        echo "ERROR: WEBHOOK_URL is not set."
        echo "Continuing without notifications"
        return
    fi

    #curl to check webhook reachable
    if ! curl -s --head --fail "$WEBHOOK_URL" >/dev/null; then
        echo "WARNING: WEBHOOK_URL ($WEBHOOK_URL) is not reachable. Notifications may fail."
    fi
}

verify_polling_rate(){
    local re='^[0-9]*\.?[0-9]+$'

    if ! [[ "$pollingRate" =~ $re ]]; then
        echo "ERROR: POLLING_RATE must be a non-negative number: $pollingRate"
        exit 1
    fi

    if awk "BEGIN {exit !($pollingRate < 1)}"; then
        echo "WARNING: POLLING_RATE less than one second may cause high CPU usage: $pollingRate"
    fi
}

print_welcome_message(){
    echo "Disk guardian started and env verified"
    echo "monitoring disks: ${diskPathsList[*]}"
    echo
    echo "Warning threshhold: $warningThreshold%"
    echo "Stopping threshhold: $stoppingThreshold%"
    echo
    echo "Containers: ${downloaderContainerNames[*]}"
    echo
    echo "Polling rate: $pollingRate"
    echo "ntfy url: $WEBHOOK_URL"

}

verify_disk_paths
verify_containers_list
verify_both_thresholds "$warningThreshold" "$stoppingThreshold"
verify_WEBHOOK_URL
verify_polling_rate

print_welcome_message

#set all disk flags to false
for disk in "${diskPathsList[@]}"; do
    diskWarned[$disk]=false
    diskStopped[$disk]=false
done

notify(){
    local message=$1
    # JSON payload depends on the service
    echo "$message"

    if [ -n "$WEBHOOK_URL" ]; then
        curl -s --max-time 5 -d "$message" "$WEBHOOK_URL" > /dev/null
    fi
}

stop_downloaders_and_build_message() {
    local stoppedAny=false
    local disk=$1
    local usage=$2
    local message
    for container in "${downloaderContainerNames[@]}"; do
        if [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = "true" ]; then
            docker stop "$container"
            stoppedAny=true
        fi
    
    done
    if [ "$stoppedAny" = true ]; then
        message="disk $disk usage at $usage% Stopping downloaders due to high disk usage"
    else
        message="$disk usage at $usage% No containers to stop, check container list, something else may be causing drive overload"
    fi
    echo "$message"

}



# function checkDiskUsage(disk)
check_disk_usage(){
    local disk_path=$1
    local use

    use=$(df -P "$disk_path" | awk 'NR==2 {gsub("%","",$5); print $5}')
    echo "$use"
}


check_disks_and_notify(){
    echo "checking disks"
    local notifyWarn=false
    local notifyStop=false
    local stopMessage="$(date '+%Y-%m-%d %H:%M:%S') CRITICAL WARNING DRIVE USAGE ABOVE $stoppingThreshold%"
    local warnMessage="$(date '+%Y-%m-%d %H:%M:%S') WARNING DRIVE USAGE ABOVE $warningThreshold%"

    for disk in "$@"; do
        local usage=$(check_disk_usage "$disk")

        if (( usage > warningThreshold )) && [ "${diskWarned[$disk]}" != "true" ]; then
            warnMessage="${warnMessage}
            Warning: Disk $disk usage at ${usage}%"
            # notify $message
            diskWarned[$disk]="true"
            notifyWarn="true"
            echo "$warnMessage"

        fi

        if (( usage > stoppingThreshold )) && [ "${diskStopped[$disk]}" != "true" ]; then
            local message=$(stop_downloaders_and_build_message "$disk" "$usage")
            stopMessage="${stopMessage}
            $message"
            diskStopped[$disk]="true"
            notifyStop="true"
            echo "$stopMessage"


        fi

        # Reset state if usage drops below warning threshold
        if (( usage < warningThreshold )); then
            diskWarned[$disk]=false
            diskStopped[$disk]=false
            notifyWarn="false"
            notifyStop="false"

        fi
    done

    if [ "$notifyWarn" = true ]; then
        notify "$warnMessage"
    fi
    if [ "$notifyStop" = true ]; then
        notify "$stopMessage"
    fi
}

while true; do
    echo "starting disk check"
    check_disks_and_notify "${diskPathsList[@]}"
    sleep $pollingRate
done