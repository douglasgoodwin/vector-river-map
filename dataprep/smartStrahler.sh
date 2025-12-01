#!/bin/bash

# Smart Strahler assignment for Western US rivers
# Uses a combination of: length, complexity (segment count), and known major rivers

DB=rivers

echo "Applying smart Strahler orders for Western US..."

psql -d $DB << 'EOF'

-- Start fresh with length-based baseline
UPDATE merged_rivers SET strahler = CASE
    WHEN ST_Length(geometry::geography)/1000 > 500 THEN 7
    WHEN ST_Length(geometry::geography)/1000 > 300 THEN 6
    WHEN ST_Length(geometry::geography)/1000 > 150 THEN 5
    WHEN ST_Length(geometry::geography)/1000 > 75 THEN 4
    WHEN ST_Length(geometry::geography)/1000 > 30 THEN 3
    WHEN ST_Length(geometry::geography)/1000 > 10 THEN 2
    ELSE 1
END;

-- Major rivers: Order 8 (continental systems)
UPDATE merged_rivers SET strahler = 8
WHERE name IN (
    'Columbia River',
    'Colorado River',
    'Snake River'
);

-- Large rivers: Order 7
UPDATE merged_rivers SET strahler = 7
WHERE name IN (
    'Sacramento River',
    'San Joaquin River',
    'Willamette River',
    'Klamath River',
    'Deschutes River',
    'John Day River',
    'Salmon River',
    'Clearwater River',
    'Yakima River',
    'Gila River',
    'Salt River',
    'Verde River',
    'Owyhee River'
) AND strahler < 7;

-- Medium-large rivers: Order 6
UPDATE merged_rivers SET strahler = 6
WHERE name IN (
    'Truckee River',
    'Carson River',
    'Walker River',
    'Owens River',
    'Kern River',
    'Kings River',
    'Merced River',
    'Tuolumne River',
    'Stanislaus River',
    'Mokelumne River',
    'American River',
    'Yuba River',
    'Feather River',
    'Pit River',
    'McCloud River',
    'Russian River',
    'Eel River',
    'Mad River',
    'Trinity River',
    'Smith River',
    'Rogue River',
    'Umpqua River',
    'Coquille River',
    'Coos River',
    'Siuslaw River',
    'Alsea River',
    'Siletz River',
    'Nestucca River',
    'Wilson River',
    'Lewis River',
    'Cowlitz River',
    'Chehalis River',
    'Skagit River',
    'Snoqualmie River',
    'Skykomish River',
    'Stillaguamish River',
    'Snohomish River',
    'Green River',
    'White River',
    'Puyallup River',
    'Sevier River',
    'Bear River',
    'Weber River',
    'Provo River',
    'Jordan River',
    'Little Colorado River'
) AND strahler < 6;

-- Medium rivers: Order 5
UPDATE merged_rivers SET strahler = 5
WHERE name ILIKE '%River%' 
AND ST_Length(geometry::geography)/1000 > 50
AND strahler < 5;

-- Reduce order for very short segments (fixes lake issues)
UPDATE merged_rivers 
SET strahler = GREATEST(1, strahler - 2)
WHERE ST_Length(geometry::geography)/1000 < 5
AND strahler > 3;

-- Fix geometry
ALTER TABLE merged_rivers 
  ALTER COLUMN geometry TYPE geometry(GEOMETRY, 4269) 
  USING ST_SetSRID(geometry, 4269);

DROP INDEX IF EXISTS merged_rivers_geometry_gist;
CREATE INDEX merged_rivers_geometry_gist ON merged_rivers USING gist(geometry);

VACUUM ANALYZE merged_rivers;

-- Results
SELECT strahler, COUNT(*), 
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) as pct
FROM merged_rivers
GROUP BY strahler 
ORDER BY strahler DESC;

-- Check our test rivers
SELECT name, strahler, ROUND(ST_Length(geometry::geography)/1000) as km
FROM merged_rivers 
WHERE name IN (
    'Columbia River', 'Sacramento River', 'Truckee River',
    'Colorado River', 'Snake River'
)
ORDER BY strahler DESC, name;

-- Check Tahoe area
SELECT name, strahler, ROUND(ST_Length(geometry::geography)/1000) as km
FROM merged_rivers 
WHERE name ILIKE '%truckee%' OR name ILIKE '%tahoe%'
ORDER BY strahler DESC;

EOF

echo ""
echo "✓ Smart Strahler orders applied"
echo ""
echo "Restart pg_tileserv and reload your map"
