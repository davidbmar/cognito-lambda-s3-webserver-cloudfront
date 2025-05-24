#!/usr/bin/env bash
# scripts/copy_to_bucket.sh
# Upload a local file to the S3 “website” bucket defined in .env
# --------------------------------------------------------------
# Usage examples:
#   scripts/copy_to_bucket.sh -file hello.txt
#   scripts/copy_to_bucket.sh -file scripts/setup.sql -dest backups/
# --------------------------------------------------------------

set -euo pipefail

########################################
# helper: print usage
########################################
usage() {
    cat <<EOF
Usage: $(basename "$0") -file <local_file> [-dest <s3_prefix>]

Options
  -file <path>   Local file to upload (required)
  -dest <path>   Key prefix in bucket (default "." = root).  Add trailing "/" if you
                 want it treated as a folder.  The file's basename is appended.
  -h, --help     Show this help and exit

Examples
  $(basename "$0") -file scripts/setup.sql
  $(basename "$0") -file logo.png -dest images/
EOF
    exit 1
}

error() { echo "❌  $*" >&2; exit 1; }

########################################
# find repo-root .env (walk up dirs)
########################################
find_env() {
    local dir; dir="$(dirname "$(realpath "$0")")"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && { echo "$dir/.env"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

########################################
# parse args
########################################
FILE=""
DEST="."          # default: bucket root
while [[ $# -gt 0 ]]; do
    case "$1" in
        -file) [[ $# -lt 2 ]] && usage; FILE="$2"; shift 2 ;;
        -dest) [[ $# -lt 2 ]] && usage; DEST="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done
[[ -n "$FILE" ]] || usage

[[ -f "$FILE" ]] || error "Local file '$FILE' does not exist."

########################################
# load .env
########################################
ENV_PATH="$(find_env)" || error ".env not found walking up from script directory."
# shellcheck disable=SC1090
source "$ENV_PATH"          || error "Failed to source $ENV_PATH"

[[ -n "${S3_BUCKET_NAME:-}" ]] || error "S3_BUCKET_NAME missing in .env"

########################################
# prep destination key
########################################
BASENAME=$(basename "$FILE")
# If DEST is "." treat as empty; ensure exactly one trailing slash if non-empty
[[ "$DEST" == "." ]] && DEST=""
[[ -n "$DEST" && "${DEST: -1}" != "/" ]] && DEST="${DEST}/"
S3_KEY="${DEST}${BASENAME}"
S3_URI="s3://${S3_BUCKET_NAME}/${S3_KEY}"

########################################
# upload
########################################
echo "➜  Uploading '${FILE}' → '${S3_URI}'"
aws s3 cp "$FILE" "$S3_URI" \
    || error "Upload failed."

echo "✅  Upload successful!"
if [[ -n "${CLOUDFRONT_URL:-}" ]]; then
    echo "🌐  Accessible (via CloudFront) at:"
    echo "    https://${CLOUDFRONT_URL}/${S3_KEY}"
fi
