#!/bin/bash

# Import NHDPlus HR with correct field names
# Based on actual schema inspection

DB=rivers

echo "Creating rivers table from nhdflowline..."

psql -d $DB << 'EOF'
-- Drop existing rivers table if it exists
DROP TABLE IF EXISTS rivers;

-- Create rivers table with the fields we need
-- Note: NHDPlus HR doesn't include StreamOrder/Strahler by default
-- We'll use lengthkm as a proxy for importance (or set default)
CREATE TABLE rivers AS
SELECT 
    gid,
    gnis_id,
    gnis_name as name,
    reachcode,
    substring(reachcode from 1 for 8) as huc8,
    -- NHDPlus HR doesn't have Strahler order, so we'll estimate based on length
    -- Longer rivers are generally higher order
    CASE 
        WHEN lengthkm > 100 THEN 6
        WHEN lengthkm > 50 THEN 5
        WHEN lengthkm > 20 THEN 4
        WHEN lengthkm > 5 THEN 3
        WHEN lengthkm > 1 THEN 2
        ELSE 1
    END as strahler,
    geom as geometry
FROM nhdflowline
WHERE ftype = 460  -- StreamRiver type
  AND fcode NOT IN (56600);  -- Exclude coastlines

-- Create indices
CREATE INDEX rivers_geometry_gist ON rivers USING gist(geometry);
CREATE INDEX rivers_gnis_id_idx ON rivers(gnis_id);
CREATE INDEX rivers_huc8_idx ON rivers(huc8);
CREATE INDEX rivers_strahler_idx ON rivers(strahler);

-- Vacuum and analyze
VACUUM ANALYZE rivers;

-- Print stats
SELECT 
    COUNT(*) as total_rivers,
    COUNT(DISTINCT gnis_id) as unique_gnis_ids,
    COUNT(DISTINCT name) FILTER (WHERE name IS NOT NULL) as named_rivers,
    COUNT(DISTINCT huc8) as watersheds,
    MIN(strahler) as min_order,
    MAX(strahler) as max_order,
    pg_size_pretty(pg_total_relation_size('rivers')) as table_size
FROM rivers;
EOF

echo "✓ Rivers table created successfully"
