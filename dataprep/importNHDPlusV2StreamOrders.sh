#!/bin/bash

# Download NHDPlus V2 StreamOrder data and join to NHDPlus HR
# This gives us scientifically accurate Strahler stream orders

set -e

DATADIR=./NHDPlusV2
DB=rivers

echo "========================================="
echo "NHDPlus V2 Stream Order Import"
echo "========================================="
echo ""
echo "This will download NHDPlus V2 data to get pre-calculated"
echo "Strahler stream orders and join them to your NHDPlus HR data"
echo ""

# Create directory
mkdir -p $DATADIR
cd $DATADIR

# Determine which regions we need based on what's in the database
echo "Checking which regions are in your database..."
psql -d $DB -t -c "
SELECT DISTINCT substring(reachcode from 1 for 2) as region 
FROM rivers 
ORDER BY region;
" > regions.txt

REGIONS=$(cat regions.txt | tr -d ' ' | grep -v '^$')
echo "Found regions: $REGIONS"
echo ""

# NHDPlus V2 region mapping
# Region codes: 01-18 for NHDPlus
declare -A REGION_NAMES=(
    ["01"]="NHDPlusNE"
    ["02"]="NHDPlusMA" 
    ["03"]="NHDPlusSA"
    ["04"]="NHDPlusGL"
    ["05"]="NHDPlusMS"
    ["06"]="NHDPlusMS"
    ["07"]="NHDPlusMS"
    ["08"]="NHDPlusMS"
    ["09"]="NHDPlusSR"
    ["10"]="NHDPlusMS"
    ["11"]="NHDPlusMS"
    ["12"]="NHDPlusTX"
    ["13"]="NHDPlusRG"
    ["14"]="NHDPlusCO"
    ["15"]="NHDPlusCO"
    ["16"]="NHDPlusGB"
    ["17"]="NHDPlusPN"
    ["18"]="NHDPlusCA"
)

# Base URL for NHDPlus V2 data
BASE_URL="https://dmap-data-commons-ow.s3.amazonaws.com/NHDPlusV21/Data"

# Download function
download_region() {
    local region=$1
    local region_name=${REGION_NAMES[$region]}
    
    if [ -z "$region_name" ]; then
        echo "Unknown region: $region"
        return
    fi
    
    local filename="${region_name}_NHDPlusAttributes_06.7z"
    local url="${BASE_URL}/${region_name}/${filename}"
    
    echo "Downloading $filename..."
    
    # Check if already downloaded
    if [ -f "$filename" ]; then
        echo "  Already downloaded"
    else
        wget -q --show-progress "$url" || {
            echo "  Failed to download, trying alternate URL..."
            # Try S3 bucket directly
            wget -q --show-progress "https://edap-ow-data-commons.s3.amazonaws.com/NHDPlusV21/Data/${region_name}/${filename}"
        }
    fi
    
    # Extract if not already done
    if [ ! -d "${region_name}_NHDPlusAttributes" ]; then
        echo "  Extracting..."
        7z x -y "$filename" > /dev/null
    fi
}

# Download all needed regions
for region in $REGIONS; do
    download_region $region
done

cd ..

echo ""
echo "========================================="
echo "Importing Stream Order Data"
echo "========================================="

# Import PlusFlowlineVAA tables into PostgreSQL
psql -d $DB << 'EOF'

-- Create schema for V2 data
CREATE SCHEMA IF NOT EXISTS nhdplusv2;

-- Drop existing table
DROP TABLE IF EXISTS nhdplusv2.plusflowlinevaa;

-- Create table for stream attributes
CREATE TABLE nhdplusv2.plusflowlinevaa (
    comid BIGINT,
    streamleve INTEGER,
    streamorde INTEGER,
    streamcalc INTEGER,
    reachcode VARCHAR(14),
    hydroseq BIGINT,
    levelpathi BIGINT
);

EOF

# Import all the DBF files
echo "Importing attribute tables..."
for dbf in $DATADIR/*/PlusFlowlineVAA.dbf; do
    if [ -f "$dbf" ]; then
        echo "  Importing $dbf"
        # Use ogr2ogr to import DBF
        ogr2ogr -f PostgreSQL \
            PG:"dbname=$DB" \
            "$dbf" \
            -nln nhdplusv2.plusflowlinevaa \
            -append \
            -lco SCHEMA=nhdplusv2
    fi
done

echo ""
echo "Creating indices..."
psql -d $DB << 'EOF'

-- Index for joining
CREATE INDEX IF NOT EXISTS plusflowlinevaa_reachcode_idx 
ON nhdplusv2.plusflowlinevaa(reachcode);

CREATE INDEX IF NOT EXISTS plusflowlinevaa_comid_idx 
ON nhdplusv2.plusflowlinevaa(comid);

-- Stats
VACUUM ANALYZE nhdplusv2.plusflowlinevaa;

-- Show what we got
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT reachcode) as unique_reachcodes,
    MIN(streamorde) as min_order,
    MAX(streamorde) as max_order
FROM nhdplusv2.plusflowlinevaa
WHERE streamorde IS NOT NULL;

EOF

echo ""
echo "========================================="
echo "Joining Stream Orders to Your Data"
echo "========================================="

psql -d $DB << 'EOF'

-- Update rivers table with V2 stream orders
UPDATE rivers r
SET strahler = v2.streamorde
FROM nhdplusv2.plusflowlinevaa v2
WHERE r.reachcode = v2.reachcode
AND v2.streamorde IS NOT NULL
AND v2.streamorde BETWEEN 1 AND 10;

-- Show how many matched
SELECT 
    COUNT(*) FILTER (WHERE strahler IS NOT NULL) as matched,
    COUNT(*) as total,
    ROUND(100.0 * COUNT(*) FILTER (WHERE strahler IS NOT NULL) / COUNT(*), 1) as match_pct
FROM rivers;

-- Now update merged_rivers
-- Take the MAX stream order from all segments in each merged river
UPDATE merged_rivers m
SET strahler = (
    SELECT MAX(r.strahler)
    FROM rivers r
    WHERE r.gnis_id = m.gnis_id
    AND r.gnis_id IS NOT NULL
    AND r.strahler IS NOT NULL
)
WHERE m.gnis_id IS NOT NULL
AND EXISTS (
    SELECT 1 FROM rivers r 
    WHERE r.gnis_id = m.gnis_id 
    AND r.strahler IS NOT NULL
);

-- Update unnamed rivers by HUC8
UPDATE merged_rivers m
SET strahler = (
    SELECT MAX(r.strahler)
    FROM rivers r
    WHERE r.huc8 = m.huc8
    AND r.gnis_id IS NULL
    AND m.gnis_id IS NULL
    AND r.strahler IS NOT NULL
)
WHERE m.gnis_id IS NULL
AND EXISTS (
    SELECT 1 FROM rivers r 
    WHERE r.huc8 = m.huc8 
    AND r.gnis_id IS NULL
    AND r.strahler IS NOT NULL
);

-- Fix geometry for tile serving
ALTER TABLE merged_rivers 
  ALTER COLUMN geometry TYPE geometry(GEOMETRY, 4269) 
  USING ST_SetSRID(geometry, 4269);

DROP INDEX IF EXISTS merged_rivers_geometry_gist;
CREATE INDEX merged_rivers_geometry_gist ON merged_rivers USING gist(geometry);

VACUUM ANALYZE merged_rivers;

-- Show final distribution
SELECT 
    strahler,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percent
FROM merged_rivers
WHERE strahler IS NOT NULL
GROUP BY strahler
ORDER BY strahler DESC;

-- Show major rivers
SELECT 
    name, 
    strahler, 
    ROUND(ST_Length(geometry::geography)/1000) as length_km
FROM merged_rivers 
WHERE name IS NOT NULL 
AND strahler IS NOT NULL
ORDER BY strahler DESC, length_km DESC 
LIMIT 30;

EOF

echo ""
echo "========================================="
echo "✓ Complete!"
echo "========================================="
echo ""
echo "You now have scientifically accurate Strahler stream orders"
echo "from the official NHDPlus V2 dataset."
echo ""
echo "Next steps:"
echo "1. Restart pg_tileserv"
echo "2. Reload your map"
echo "3. Enjoy perfect stream hierarchy! 🎉"
echo ""
