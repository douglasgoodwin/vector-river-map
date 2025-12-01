#!/bin/bash

# Fast hybrid Strahler calculation
# Uses topology for major rivers, length for small streams
# Much faster than full topological analysis

DB=rivers

echo "Fast hybrid Strahler calculation..."
echo "This should take 5-10 minutes"
echo ""

psql -d $DB << 'EOF'

-- Step 1: Use length-based estimation as starting point
UPDATE merged_rivers SET strahler = CASE
    WHEN ST_Length(geometry::geography)/1000 > 300 THEN 7
    WHEN ST_Length(geometry::geography)/1000 > 150 THEN 6
    WHEN ST_Length(geometry::geography)/1000 > 75 THEN 5
    WHEN ST_Length(geometry::geography)/1000 > 35 THEN 4
    WHEN ST_Length(geometry::geography)/1000 > 15 THEN 3
    WHEN ST_Length(geometry::geography)/1000 > 5 THEN 2
    ELSE 1
END;

-- Step 2: Boost major named rivers by examining their complexity
-- Rivers with many segments merged together = more important
WITH segment_counts AS (
    SELECT 
        m.gnis_id,
        COUNT(*) as num_segments,
        MAX(m.strahler) as current_order
    FROM merged_rivers m
    JOIN rivers r ON r.gnis_id = m.gnis_id
    WHERE m.gnis_id IS NOT NULL
    GROUP BY m.gnis_id
)
UPDATE merged_rivers m
SET strahler = LEAST(8, s.current_order + 
    CASE 
        WHEN s.num_segments > 500 THEN 2
        WHEN s.num_segments > 200 THEN 1
        ELSE 0
    END)
FROM segment_counts s
WHERE m.gnis_id = s.gnis_id;

-- Step 3: Manually boost known major rivers
UPDATE merged_rivers SET strahler = 8
WHERE name IN (
    'Columbia River', 'Colorado River', 'Snake River',
    'Sacramento River', 'San Joaquin River'
);

UPDATE merged_rivers SET strahler = 7
WHERE name IN (
    'Willamette River', 'Deschutes River', 'John Day River',
    'Klamath River', 'Pit River', 'Feather River',
    'American River', 'Stanislaus River', 'Tuolumne River',
    'Merced River', 'Kings River', 'Kern River',
    'Salinas River', 'Russian River', 'Eel River',
    'Trinity River', 'Salmon River', 'Clearwater River',
    'Owyhee River', 'Malheur River', 'Yakima River',
    'Wenatchee River', 'Green River', 'Gila River',
    'Salt River', 'Verde River'
) AND strahler < 7;

-- Step 4: Reduce order for very short segments
-- (Fixes those thick short lines around lakes)
UPDATE merged_rivers 
SET strahler = GREATEST(1, strahler - 2)
WHERE ST_Length(geometry::geography)/1000 < 5
AND strahler > 3;

-- Fix geometry
ALTER TABLE merged_rivers 
  ALTER COLUMN geometry TYPE geometry(GEOMETRY, 4269) 
  USING ST_SetSRID(geometry, 4269);

-- Recreate index
DROP INDEX IF EXISTS merged_rivers_geometry_gist;
CREATE INDEX merged_rivers_geometry_gist ON merged_rivers USING gist(geometry);

VACUUM ANALYZE merged_rivers;

-- Show results
SELECT 
    strahler,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percent
FROM merged_rivers
GROUP BY strahler
ORDER BY strahler DESC;

-- Show top rivers
SELECT 
    name, 
    strahler, 
    ROUND(ST_Length(geometry::geography)/1000) as length_km
FROM merged_rivers 
WHERE name IS NOT NULL 
ORDER BY strahler DESC, length_km DESC 
LIMIT 30;

EOF

echo ""
echo "✓ Hybrid Strahler calculation complete"
echo "Restart pg_tileserv and check the map"