#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH=${1:-config/day.yaml}
IMAGES_ROOT=${2:-dataset/images}
DEFAULT_OUTPUT_NAME="kidnapped_$(basename "${CONFIG_PATH%.*}").json"
OUTPUT_PATH=${3:-artifacts/${DEFAULT_OUTPUT_NAME}}

mkdir -p "$(dirname "$OUTPUT_PATH")"

python scripts/build_kidnapped_dataset.py \
  --config "$CONFIG_PATH" \
  --images_root "$IMAGES_ROOT" \
  --output "$OUTPUT_PATH"
