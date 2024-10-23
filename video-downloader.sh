#!/bin/bash

# --------------------------------------------------------
#  Copyright (c) 2024 Daniel Dietrich, licensed under MIT
# --------------------------------------------------------

# Function to display usage instructions
usage() {
    echo "Usage: $0 [-y] <m3u8_url> <output_filename>"
    echo "  -y   Overwrite existing output files without prompt."
    echo "Example: $0 \"https://example.com/stream.m3u8\" \"output.mp4\""
    exit 1
}

# Function to check if required commands are available
check_requirements() {
    local missing_requirements=0
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "Error: ffmpeg is not installed. Please install it first."
        missing_requirements=1
    fi
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "Error: ffprobe is not installed. Please install it first."
        missing_requirements=1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is not installed. Please install it first."
        missing_requirements=1
    fi
    if [ $missing_requirements -eq 1 ]; then
        exit 1
    fi
}

# Function to validate URL
validate_url() {
    local url=$1
    if ! curl --output /dev/null --silent --head --fail "$url"; then
        echo "Error: Invalid URL or resource not accessible: $url"
        exit 1
    fi
}

# Function to determine total content length using ffprobe
get_content_length() {
    local url=$1
    local duration
    duration=$(ffprobe -i "$url" -show_entries format=duration -v quiet -of csv="p=0")
    echo "$duration"
}

# Function to get format name and long name using ffprobe
get_format() {
    local url=$1
    local format_info
    format_info=$(ffprobe -i "$url" -show_entries format=format_name,format_long_name -v quiet -of csv="p=0")
    
    # Transform the output into "<name> (<long_name>)"
    echo "$format_info" | awk -F, '{print $1 " (" $2 ")"}'
}

get_video_resolution() {
    local file=$1
    local resolution
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file")
    echo "$resolution"
}

# Function to display spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr="|/-\\"
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

# Function to download and process the m3u8 stream
download_stream() {
    local url=$1
    local output=$2
    echo "Starting download of: $url"
    echo "Format: $(get_format "$url")"
    echo "Output will be saved as: $output"

    # Get the total duration of the stream
    local total_duration
    total_duration=$(get_content_length "$url")
    total_duration=${total_duration%.*}  # Remove any decimal part
    if [[ ! "$total_duration" =~ ^[0-9]+$ ]]; then
        echo "Content length not determinable."
        ffmpeg -i "$url" \
            -c copy \
            -bsf:a aac_adtstoasc \
            -movflags +faststart \
            -y \
            "$output" > /dev/null 2>&1 &
        spinner $!
    else
        # Convert total duration to HH:MM:SS format
        printf -v formatted_duration '%02d:%02d:%02d' "$(echo "$total_duration/3600" | bc)" "$(echo "$total_duration%3600/60" | bc)" "$(echo "$total_duration%60" | bc)"
        echo "Content length determined: $formatted_duration"
        ffmpeg -i "$url" \
            -c copy \
            -bsf:a aac_adtstoasc \
            -movflags +faststart \
            -y \
            "$output" 2>&1 | while read -r line; do
            if [[ "$line" =~ time=([0-9]+):([0-9]+):([0-9]+) ]]; then
                hours=${BASH_REMATCH[1]}
                minutes=${BASH_REMATCH[2]}
                seconds=${BASH_REMATCH[3]}
                # Remove leading zeros by using arithmetic evaluation
                current_duration=$((10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
                if [ "$total_duration" -ne 0 ]; then
                    progress=$(awk "BEGIN {printf \"%.2f\", ($current_duration / $total_duration) * 100}")
                    echo -ne "Progress: $progress% \r"
                fi
            fi
        done
    fi

    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        echo "Download completed successfully!"
        echo "File saved in $(get_video_resolution "$output") as: $output"
    else
        echo "Error: Download failed!"
        rm -f "$output"
        exit 1
    fi
}

# Main script execution starts here

# Check if correct number of arguments provided
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
fi

# Initialize variables
FORCE_OVERWRITE=0

# Parse command line options
while getopts ":y" opt; do
    case ${opt} in
        y )
            FORCE_OVERWRITE=1
            ;;
        \? )
            usage
            ;;
    esac
done
shift $((OPTIND -1))

# Get command line arguments
M3U8_URL=$1
OUTPUT_FILE=$2

# Check if output file already exists
if [ "$FORCE_OVERWRITE" -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    read -p "File $OUTPUT_FILE already exists. Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
fi

# Check for required commands
check_requirements

# Validate URL
validate_url "$M3U8_URL"

# Start download
download_stream "$M3U8_URL" "$OUTPUT_FILE"
