#!/usr/bin/env bash
#
# sound-pack-curator.sh
#
# Curation script for ccbell sound packs.
# Queries sound providers, downloads sounds, converts formats, and creates packs.
#
# Usage:
#   ./sound-pack-curator.sh query <provider> <query> [--limit N]
#   ./sound-pack-curator.sh download <provider> <sound_id> <output_dir>
#   ./sound-pack-curator.sh convert <input_dir> <output_dir>
#   ./sound-pack-curator.sh create-pack <pack_name> <version> <sounds_dir>
#   ./sound-pack-curator.sh curate <provider> <pack_name> <query>
#
# Providers:
#   pixabay    - Pixabay API (free, no OAuth)
#   freesound  - Freesound API (API key + OAuth2 for downloads)
#
# Environment Variables:
#   PIXABAY_API_KEY      - Pixabay API key (get at pixabay.com/api/docs/)
#   FREESOUND_API_KEY    - Freesound API key (get at freesound.org/apiv2/apply)
#   FREESOUND_OAUTH_TOKEN - Freesound OAuth token (for downloads)
#
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-./downloads}"
PACKS_DIR="${PACKS_DIR:-./packs}"
LOG_FILE="${LOG_FILE:-/tmp/sound-pack-curator.log}"

# Rate limiting
declare -A PROVIDER_RATE_LIMITS=(
  ["pixabay"]="100/60"    # 100 requests per 60 seconds
  ["freesound"]="60/60"   # 60 requests per 60 seconds
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$*"; }
log_warn() { log "${YELLOW}WARN${NC}" "$*"; }
log_error() { log "${RED}ERROR${NC}" "$*"; }
log_success() { log "${GREEN}SUCCESS${NC}" "$*"; }

# Check dependencies
check_dependencies() {
  local deps=("curl" "jq" "ffmpeg")
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    log_info "Install with: brew install curl jq ffmpeg"
    exit 1
  fi
}

# Rate limiting
wait_for_rate_limit() {
  local provider="$1"
  local rate_limit="${PROVIDER_RATE_LIMITS[$provider]}"
  local max_requests="${rate_limit%%/*}"
  local interval="${rate_limit##*/}"

  # Simple rate limiting - wait between requests
  local wait_time=$((interval / max_requests + 1))
  sleep "$wait_time"
}

# === PIXABAY PROVIDER ===

query_pixabay() {
  local query="$1"
  local limit="${2:-20}"
  local api_key="${PIXABAY_API_KEY:-}"

  if [ -z "$api_key" ]; then
    log_warn "PIXABAY_API_KEY not set, using limited rate (5 req/sec)"
  fi

  log_info "Querying Pixabay for: $query"

  local url="https://pixabay.com/api/?q=$(echo "$query" | tr ' ' '+')&category=sound-effects&per_page=$limit"
  if [ -n "$api_key" ]; then
    url+="&key=$api_key"
  fi

  wait_for_rate_limit "pixabay"

  local response
  response=$(curl -s "$url")

  if [ -z "$response" ]; then
    log_error "Empty response from Pixabay"
    return 1
  fi

  local total_hits
  total_hits=$(echo "$response" | jq -r '.totalHits')

  if [ "$total_hits" == "0" ] || [ "$total_hits" == "null" ]; then
    log_warn "No results found for: $query"
    return 0
  fi

  log_info "Found $total_hits results"

  # Output results as JSON
  echo "$response" | jq -r ".hits[] | {
    id: .id,
    provider: \"pixabay\",
    title: .tags,
    url: .pageURL,
    audio_url: .audio,
    preview_url: .previewURL,
    duration: .duration // \"unknown\",
    license: \"pixabay\"
  } | @json"
}

download_pixabay() {
  local sound_id="$1"
  local output_dir="$2"
  local api_key="${PIXABAY_API_KEY:-}"

  log_info "Downloading Pixabay sound: $sound_id"

  local url="https://pixabay.com/api/?id=$sound_id"
  if [ -n "$api_key" ]; then
    url+="&key=$api_key"
  fi

  wait_for_rate_limit "pixabay"

  local response
  response=$(curl -s "$url")

  local audio_url
  audio_url=$(echo "$response" | jq -r '.hits[0].audio // empty')

  if [ -z "$audio_url" ]; then
    log_error "Could not find audio URL for: $sound_id"
    return 1
  fi

  mkdir -p "$output_dir"
  local output_file="$output_dir/${sound_id}.mp3"

  curl -L -o "$output_file" "$audio_url"

  if [ -f "$output_file" ]; then
    log_success "Downloaded: $output_file"
    echo "$output_file"
  else
    log_error "Failed to download: $sound_id"
    return 1
  fi
}

# === FREESOUND PROVIDER ===

query_freesound() {
  local query="$1"
  local limit="${2:-20}"
  local api_key="${FREESOUND_API_KEY:-}"

  if [ -z "$api_key" ]; then
    log_error "FREESOUND_API_KEY not set"
    log_info "Get a free API key at: https://freesound.org/apiv2/apply"
    return 1
  fi

  log_info "Querying Freesound for: $query"

  wait_for_rate_limit "freesound"

  local url="https://freesound.org/apiv2/search/text/?q=$query&types=wav&fields=id,name,previews,pack,license,duration&limit=$limit&token=$api_key"

  local response
  response=$(curl -s "$url")

  if [ -z "$response" ]; then
    log_error "Empty response from Freesound"
    return 1
  fi

  local count
  count=$(echo "$response" | jq -r '.count')

  if [ "$count" == "0" ]; then
    log_warn "No results found for: $query"
    return 0
  fi

  log_info "Found $count results"

  echo "$response" | jq -r ".results[] | {
    id: .id,
    provider: \"freesound\",
    title: .name,
    url: \"https://freesound.org/descview/.id\",
    preview_url: (.previews.\"preview-hq-mp3\" // .previews.\"preview-lq-mp3\" // empty),
    license: (.license // \"unknown\"),
    duration: (.duration | if . then (tostring) else \"unknown\" end)
  } | select(.preview_url != null) | @json"
}

download_freesound() {
  local sound_id="$1"
  local output_dir="$2"
  local api_key="${FREESOUND_API_KEY:-}"
  local oauth_token="${FREESOUND_OAUTH_TOKEN:-}"

  log_info "Downloading Freesound sound: $sound_id"

  if [ -z "$api_key" ]; then
    log_error "FREESOUND_API_KEY not set"
    return 1
  fi

  # Method 1: Direct download with OAuth token (preferred)
  if [ -n "$oauth_token" ]; then
    wait_for_rate_limit "freesound"
    local url="https://freesound.org/apiv2/sounds/$sound_id/download/?token=$oauth_token"
    mkdir -p "$output_dir"
    local output_file="$output_dir/${sound_id}.wav"
    curl -L -o "$output_file" "$url"

  # Method 2: Download preview as fallback (lower quality)
  elif [ -n "$api_key" ]; then
    wait_for_rate_limit "freesound"
    local preview_url
    preview_url=$(curl -s "https://freesound.org/apiv2/sounds/$sound_id/?fields=previews&token=$api_key" | \
      jq -r '.previews."preview-hq-mp3" // .previews."preview-lq-mp3" // empty')

    if [ -z "$preview_url" ]; then
      log_error "Could not find download URL for: $sound_id"
      return 1
    fi

    mkdir -p "$output_dir"
    local output_file="$output_dir/${sound_id}.mp3"
    curl -L -o "$output_file" "$preview_url"
    log_warn "Downloaded preview quality (full quality requires OAuth)"
  else
    log_error "FREESOUND_API_KEY or FREESOUND_OAUTH_TOKEN required"
    return 1
  fi

  if [ -f "$output_dir/${sound_id}.wav" ] || [ -f "$output_dir/${sound_id}.mp3" ]; then
    log_success "Downloaded: $output_dir/${sound_id}.*"
    ls "$output_dir"/${sound_id}.*
  else
    log_error "Failed to download: $sound_id"
    return 1
  fi
}

# === COMMON FUNCTIONS ===

convert_to_aiff() {
  local input_dir="$1"
  local output_dir="$2"

  log_info "Converting sounds to AIFF format..."

  mkdir -p "$output_dir"

  find "$input_dir" -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.ogg" -o -name "*.flac" \) | while read -r file; do
    local basename
    basename=$(basename "$file" | sed 's/\.[^.]*$//')
    local output_file="$output_dir/${basename}.aiff"

    log_info "Converting: $basename"

    if ffmpeg -i "$file" -f aiff -acodec pcm_s16be "$output_file" -y 2>/dev/null; then
      log_success "Created: $output_file"
    else
      log_error "Failed to convert: $file"
    fi
  done
}

create_pack() {
  local pack_name="$1"
  local version="${2:-1.0.0}"
  local sounds_dir="$3"

  log_info "Creating pack: $pack_name v$version"

  local pack_dir="$PACKS_DIR/$pack_name"
  mkdir -p "$pack_dir"

  # Create pack.json
  cat > "$pack_dir/pack.json" <<EOF
{
  "id": "$pack_name",
  "name": "$(echo "$pack_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')",
  "description": "Sound pack curated from multiple providers",
  "author": "ccbell-sound-packs",
  "version": "$version",
  "events": {
EOF

  # Add event mappings
  local first=true
  declare -A EVENT_MAP=(
    ["stop"]="stop,notification,bell,complete"
    ["permission_prompt"]="permission,alert,question"
    ["idle_prompt"]="idle,wait,waiting"
    ["subagent"]="subagent,agent,complete,done"
  )

  for event in "${!EVENT_MAP[@]}"; do
    local keywords="${EVENT_MAP[$event]}"
    local sound_file=""

    # Try to find matching sound
    for keyword in $(echo "$keywords" | tr ',' ' '); do
      sound_file=$(find "$sounds_dir" -name "*${keyword}*.aiff" 2>/dev/null | head -1)
      if [ -n "$sound_file" ]; then
        break
      fi
    done

    # Fallback to any available sound
    if [ -z "$sound_file" ]; then
      sound_file=$(find "$sounds_dir" -name "*.aiff" 2>/dev/null | head -1)
    fi

    if [ -n "$sound_file" ]; then
      local basename
      basename=$(basename "$sound_file")

      if [ "$first" = true ]; then
        first=false
      else
        echo "," >> "$pack_dir/pack.json"
      fi

      echo -n "    \"$event\": \"$basename\"" >> "$pack_dir/pack.json"
      log_info "Mapped $event -> $basename"
    fi
  done

  echo -e "\n  }" >> "$pack_dir/pack.json"
  echo "}" >> "$pack_dir/pack.json"

  # Copy sounds
  mkdir -p "$pack_dir/sounds"
  cp "$sounds_dir"/*.aiff "$pack_dir/sounds/" 2>/dev/null || true

  log_success "Created pack: $pack_dir"
  log_info "pack.json:"
  cat "$pack_dir/pack.json"
}

curate_pack() {
  local provider="$1"
  local pack_name="$2"
  local query="$3"

  log_info "Starting curation: $provider -> $pack_name"

  local temp_dir
  temp_dir=$(mktemp -d)
  local downloads_dir="$temp_dir/downloads"
  local aiff_dir="$temp_dir/aiff"

  trap "rm -rf $temp_dir" EXIT

  # Query and download
  case "$provider" in
    pixabay)
      query_pixabay "$query" 10 | while read -r line; do
        local id
        id=$(echo "$line" | jq -r '.id')
        if [ "$id" != "null" ]; then
          download_pixabay "$id" "$downloads_dir"
        fi
      done
      ;;
    freesound)
      query_freesound "$query" 10 | while read -r line; do
        local id
        id=$(echo "$line" | jq -r '.id')
        if [ "$id" != "null" ]; then
          download_freesound "$id" "$downloads_dir"
        fi
      done
      ;;
    *)
      log_error "Unknown provider: $provider"
      return 1
      ;;
  esac

  # Convert to AIFF
  convert_to_aiff "$downloads_dir" "$aiff_dir"

  # Create pack
  create_pack "$pack_name" "1.0.0" "$aiff_dir"

  log_success "Curation complete: $pack_name"
}

# === MAIN ===

show_help() {
  cat <<EOF
sound-pack-curator.sh - Curation script for ccbell sound packs

Usage: $0 <command> [options]

Commands:
  query <provider> <query> [--limit N]
      Query a provider for sounds
      Providers: pixabay, freesound

  download <provider> <sound_id> <output_dir>
      Download a sound from a provider

  convert <input_dir> <output_dir>
      Convert audio files to AIFF format

  create-pack <pack_name> <version> <sounds_dir>
      Create a sound pack from a directory of sounds

  curate <provider> <pack_name> <query>
      Full curation workflow: query, download, convert, create pack

Options:
  --help, -h          Show this help message
  --verbose, -v       Verbose output

Environment Variables:
  PIXABAY_API_KEY      Pixabay API key
  FREESOUND_API_KEY    Freesound API key
  FREESOUND_OAUTH_TOKEN Freesound OAuth token (for downloads)

Examples:
  $0 query pixabay "notification bell"
  $0 query freesound "door bell"

  $0 curate pixabay minimal "notification alert"

  $0 create-pack minimal 1.0.0 ./sounds/

EOF
}

main() {
  if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
  fi

  check_dependencies

  local command="$1"
  shift

  case "$command" in
    query)
      local provider="$1"
      local query="$2"
      local limit="20"

      while [[ $# -gt 2 ]]; do
        case "$3" in
          --limit)
            limit="$4"
            shift 2
            ;;
        esac
      done

      case "$provider" in
        pixabay)
          query_pixabay "$query" "$limit"
          ;;
        freesound)
          query_freesound "$query" "$limit"
          ;;
        *)
          log_error "Unknown provider: $provider"
          exit 1
          ;;
      esac
      ;;

    download)
      local provider="$1"
      local sound_id="$2"
      local output_dir="${3:-./downloads}"

      case "$provider" in
        pixabay)
          download_pixabay "$sound_id" "$output_dir"
          ;;
        freesound)
          download_freesound "$sound_id" "$output_dir"
          ;;
        *)
          log_error "Unknown provider: $provider"
          exit 1
          ;;
      esac
      ;;

    convert)
      convert_to_aiff "$1" "$2"
      ;;

    create-pack)
      create_pack "$1" "$2" "$3"
      ;;

    curate)
      curate_pack "$1" "$2" "$3"
      ;;

    *)
      log_error "Unknown command: $command"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
