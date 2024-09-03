#!/bin/bash

# Function to URL encode a string
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Function to extract URLs from sitemap
extract_urls_from_sitemap() {
    local sitemap_url="$1"
    curl -s "$sitemap_url" | grep -oP '(?<=<loc>)https?://[^<]+'
}

# Function to submit a single URL
submit_single_url() {
    local url="$1"
    local key="$2"
    local search_engine="$3"
    encoded_url=$(urlencode "$url")
    curl -s "https://${search_engine}/indexnow?url=${encoded_url}&key=${key}"
}

# Function to submit multiple URLs
submit_multiple_urls() {
    local host="$1"
    local key="$2"
    local search_engine="$3"
    shift 3
    local urls=("$@")
    
    # Convert URL list to JSON array
    local url_json_array=$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)
    
    # Prepare JSON data
    local json_data=$(jq -n \
                  --arg host "$host" \
                  --arg key "$key" \
                  --argjson urlList "$url_json_array" \
                  '{host: $host, key: $key, urlList: $urlList}')
    
    echo "Debug: JSON data to be sent:"
    echo "$json_data"
    
    # Submit URLs
    local response=$(curl -v -X POST "https://${search_engine}/indexnow" \
         -H "Content-Type: application/json; charset=utf-8" \
         -d "$json_data")
    echo "Response: $response"
}

# Check for required commands
for cmd in curl grep jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it and try again."
        exit 1
    fi
done

# Main script
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <search_engine> <key> <host> <sitemap_url>"
    exit 1
fi

search_engine="$1"
key="$2"
host="$3"
sitemap_url="$4"

echo "Extracting URLs from sitemap..."
urls=($(extract_urls_from_sitemap "$sitemap_url"))

if [ ${#urls[@]} -eq 0 ]; then
    echo "No URLs found in the sitemap."
    exit 1
fi

echo "Found ${#urls[@]} URLs in the sitemap."

echo "Debug: First few URLs extracted from sitemap:"
printf '%s\n' "${urls[@]:0:5}"

# Check if we have more than 10,000 URLs
if [ ${#urls[@]} -gt 10000 ]; then
    echo "Warning: More than 10,000 URLs found. Submitting only the first 10,000."
    urls=("${urls[@]:0:10000}")
fi

echo "Submitting URLs to IndexNow..."
submit_multiple_urls "$host" "$key" "$search_engine" "${urls[@]}"

echo "Done."