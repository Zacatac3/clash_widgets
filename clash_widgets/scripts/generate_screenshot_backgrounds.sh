#!/bin/sh
set -eu

source_dir="$SRCROOT/clash_widgets/Assets.xcassets/backgrounds"
output_file="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ScreenshotBackgrounds.txt"

mkdir -p "$(dirname "$output_file")"
: > "$output_file"

for asset in "$source_dir"/*.imageset; do
    [ -d "$asset" ] || continue
    asset_name=${asset##*/}
    printf '%s\n' "${asset_name%.imageset}" >> "$output_file"
done
