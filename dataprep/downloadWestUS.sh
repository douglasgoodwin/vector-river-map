#!/bin/bash

# Download NHDPlus HR for Western US regions
# Much faster than downloading everything - good for testing/teaching

set -e

BASE_URL="https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHDPlusHR/Beta/GDB"

mkdir -p NHD
cd NHD

# Western US regions (useful for CalArts context)
declare -a REGIONS=(
    # Region 18 - California (rest of California)
    "1802" "1803" "1804" "1805" "1806" "1807" "1808" "1809" "1810" "1811"
    
    # Region 17 - Pacific Northwest (Oregon, Washington)
    "1701" "1702" "1703" "1704" "1705" "1706" "1707" "1708" "1709" "1710" "1711" "1712"
    
    # Region 16 - Great Basin (Nevada, Utah)
    "1601" "1602" "1603" "1604" "1605"
    
    # Region 15 - Lower Colorado (Arizona, Southern California)
    "1501" "1502" "1503" "1504" "1505" "1506" "1507"
    
    # Region 14 - Upper Colorado (Colorado, Utah)
    "1401" "1402" "1403" "1404" "1405" "1406" "1407" "1408"
)

TOTAL=${#REGIONS[@]}
CURRENT=0

echo "========================================="
echo "NHDPlus HR - Western US Download"
echo "========================================="
echo "Regions: California, Pacific NW, Great Basin, Colorado"
echo "Total HUC4 regions: $TOTAL"
echo "Estimated download: ~30GB"
echo "Estimated time: 1-2 hours (depending on connection)"
echo ""
read -p "Press Enter to start download (or Ctrl+C to cancel)..."

for region in "${REGIONS[@]}"; do
    CURRENT=$((CURRENT + 1))
    filename="NHDPLUS_H_${region}_HU4_GDB.zip"
    
    echo ""
    echo "[$CURRENT/$TOTAL] Region $region"
    
    # Skip if already exists
    if [ -d "NHDPLUS_H_${region}_HU4_GDB.gdb" ]; then
        echo "  ✓ Already have this region"
        continue
    fi
    
    if [ -f "$filename" ]; then
        echo "  Found zip file, extracting..."
        unzip -q "$filename" && rm "$filename"
        continue
    fi
    
    # Download
    url="${BASE_URL}/${filename}"
    echo "  Downloading..."
    if wget -q --show-progress "$url"; then
        echo "  ✓ Downloaded"
        echo "  Extracting..."
        unzip -q "$filename" && rm "$filename"
        echo "  ✓ Ready"
    else
        echo "  ✗ Failed (URL might be wrong, skip for now)"
    fi
done

echo ""
echo "========================================="
echo "Download Complete!"
echo "========================================="
echo ""
echo "Geodatabases available:"
ls -d NHDPLUS_H_*.gdb 2>/dev/null | wc -l
echo ""
echo "Next: Run '../importNhdHR.sh' to import all regions"
