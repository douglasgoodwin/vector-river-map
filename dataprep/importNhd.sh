#!/bin/bash

# Import NHDPlus High Resolution data into PostGIS
# Updated for NHDPlus HR format (2025)

### Defensive shell scripting
set -eu

### Configurable variables
DATADIR=./NHD
DB=rivers

### Set up logging
LOG=$(mktemp /tmp/nhd.log.XXXXXX)
echo "Script output logging to $LOG"

### Simple time statistic
start=$(date +%s)

### Check if database exists
if psql -lqt | cut -d \| -f 1 | grep -qw $DB; then
    echo "Database '$DB' already exists. Using it."
else
    echo "Creating database '$DB'"
    createdb $DB
    psql -q -d $DB -c 'CREATE EXTENSION postgis;'
    psql -q -d $DB -c 'CREATE EXTENSION postgis_topology;'
fi

### Find NHDPlus HR GDB files
echo "Looking for NHDPlus HR geodatabases..."
gdbs=$(find $DATADIR -name "NHDPLUS_H_*.gdb" -type d)

if [ -z "$gdbs" ]; then
    echo "ERROR: No NHDPlus HR geodatabases found in $DATADIR"
    echo "Expected format: NHDPLUS_H_XXXX_HU4_GDB.gdb"
    echo "Run downloadNhdModern.sh first"
    exit 1
fi

echo "Found geodatabases:"
echo "$gdbs"

### Import NHDFlowline from each GDB
echo ""
echo "Importing NHDFlowline layers..."

# Track if this is the first import (for schema creation)
FIRST=1

for gdb in $gdbs; do
    echo "Processing $gdb"
    
    # Find the NHDFlowline layer
    flowline_layer=$(ogrinfo -so "$gdb" | grep -i "nhdflowline" | head -1 | awk '{print $2}')
    
    if [ -z "$flowline_layer" ]; then
        echo "  WARNING: No NHDFlowline layer found in $gdb, skipping"
        continue
    fi
    
    echo "  Importing layer: $flowline_layer"
    
    if [ $FIRST -eq 1 ]; then
        # First import: create the table schema
        echo "  Creating schema (first import)"
        ogr2ogr -f PostgreSQL \
            PG:"dbname=$DB" \
            "$gdb" \
            "$flowline_layer" \
            -nln nhdflowline \
            -nlt LINESTRING \
            -t_srs EPSG:4269 \
            -lco GEOMETRY_NAME=geom \
            -lco FID=gid \
            -progress \
            >> $LOG 2>&1
        FIRST=0
    else
        # Subsequent imports: append to existing table
        echo "  Appending to existing table"
        ogr2ogr -f PostgreSQL \
            PG:"dbname=$DB" \
            "$gdb" \
            "$flowline_layer" \
            -nln nhdflowline \
            -append \
            -nlt LINESTRING \
            -t_srs EPSG:4269 \
            -progress \
            >> $LOG 2>&1
    fi
    
    echo "  ✓ Imported $flowline_layer"
done

### Build the rivers table from nhdflowline
echo ""
echo "Building rivers table from NHDFlowline data..."

# Create rivers table with just the fields we need
psql -d $DB -q << 'EOF'
-- Drop existing rivers table if it exists
DROP TABLE IF EXISTS rivers;

-- Create rivers table with relevant fields
-- NHDPlus HR uses different field names than V2
CREATE TABLE rivers AS
SELECT 
    gid,
    gnis_id::integer as gnis_id,
    gnis_name as name,
    reachcode,
    substring(reachcode from 1 for 8) as huc8,
    streamorde as strahler,  -- NHDPlus HR uses streamorde for Strahler
    geom as geometry
FROM nhdflowline
WHERE ftype = 460  -- Flowline type code
  AND fcode NOT IN (56600);  -- Exclude coastlines

-- Create spatial index
CREATE INDEX rivers_geometry_gist ON rivers USING gist(geometry);
CREATE INDEX rivers_gnis_id_idx ON rivers(gnis_id);
CREATE INDEX rivers_huc8_idx ON rivers(huc8);
CREATE INDEX rivers_strahler_idx ON rivers(strahler);

-- Vacuum and analyze
VACUUM ANALYZE rivers;

-- Print stats
SELECT 
    COUNT(*) as total_rivers,
    COUNT(DISTINCT gnis_id) as unique_names,
    COUNT(DISTINCT huc8) as watersheds,
    pg_size_pretty(pg_total_relation_size('rivers')) as table_size
FROM rivers;
EOF

echo "✓ Rivers table created"

### Run merge script
echo ""
echo "Creating merged_rivers table..."
python3 mergeRivers.py

### Print final stats
end=$(date +%s)
echo ""
echo "=== Import Complete ==="
echo "Total time: $((end-start)) seconds"
echo ""
psql -d $DB -c "
SELECT 
    'rivers' as table_name,
    COUNT(*) as rows,
    pg_size_pretty(pg_total_relation_size('rivers')) as size
FROM rivers
UNION ALL
SELECT 
    'merged_rivers' as table_name,
    COUNT(*) as rows,
    pg_size_pretty(pg_total_relation_size('merged_rivers')) as size
FROM merged_rivers;
"

echo ""
echo "Log file: $LOG"
echo "✓ Import successful!"