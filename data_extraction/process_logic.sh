#!/bin/bash

# Setup paths relative to Downloads
SOURCE_DIR="logic"
TARGET_DIR="processed_csvs"

# Create the final flat directory
mkdir -p "$TARGET_DIR"

# Loop through CSVs in the logic folder
for file in "$SOURCE_DIR"/*.csv; do
    # Basic checks to skip irrelevant files
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    base="${filename%.*}"

    if [[ "$filename" == *"_stripped"* ]] || [[ "$filename" == *"_final"* ]]; then
        continue
    fi

    echo "Processing $filename..."

    # 1. Create the stripped file in the current directory (Downloads)
    dd if="$file" of="${base}_stripped.csv" bs=1 skip=68 status=none

    # 2. Run sce. We'll use a temporary folder name for the output
    # because the tool insists on creating subfolders.
    sce "${base}_stripped.csv" --out "${base}_temp_output"

    # 3. Flattening Step:
    # Find any CSV file inside the newly created temp folder and move it 
    # directly to processed_csvs with the original name.
    find "./${base}_temp_output" -name "*.csv" -exec mv {} "$TARGET_DIR/${base}.csv" \;

    # 4. Cleanup
    rm "${base}_stripped.csv"
    rm -rf "./${base}_temp_output"
done

echo "Done. All flat files are in: $TARGET_DIR"