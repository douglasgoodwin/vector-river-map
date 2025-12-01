#!/bin/bash

# Super fast Strahler fix - works directly on merged_rivers only
# No joins, no complex queries - guaranteed under 2 minutes

DB=rivers

echo "Quick Strahler fix (under 2 minutes)..."

psql -d $DB << 'EOF'

-- Just update merged_rivers with better length thresholds
-- Plus manual fixes for major rivers
UPDATE merged_rivers SET strahler = CASE
    WHEN ST_Length(geometry::geography)/1000 > 400 THEN 8
    WHEN ST_Length(geometry::geography)/1000 > 200 THEN 7
    WHEN ST_Length(geometry::geography)/1000 > 100 THEN 6
    WHEN ST_Length(geometry::geography)/1000 > 50 THEN 5
    WHEN ST_Length(geometry::geography)/1000 > 20 THEN 4
    WHEN ST_Length(geometry::geography)/1000 > 8 THEN 3
    WHEN ST_Length(geometry::geography)/1000 > 3 THEN 2
    ELSE 1
END;

-- Manually set major rivers to order 8
UPDATE merged_rivers SET strahler = 8
WHERE name IN (
    'Columbia River', 'Colorado River', 'Snake River',
    'Sacramento River', 'San Joaquin River', 'Willamette River'
);

-- Order 7 for large rivers
UPDATE merged_rivers SET strahler = 7
WHERE name ILIKE '%River%' 
  AND ST_Length(geometry::geography)/1000 > 80
  AND strahler < 7;

-- Fix short segments (like around Tahoe)
UPDATE merged_rivers 
SET strahler = LEAST(strahler, 2)
WHERE ST_Length(geometry::geography)/1000 < 3;

-- Fix geometry
ALTER TABLE merged_rivers 
  ALTER COLUMN geometry TYPE geometry(GEOMETRY, 4269) 
  USING ST_SetSRID(geometry, 4269);

DROP INDEX IF EXISTS merged_rivers_geometry_gist;
CREATE INDEX merged_rivers_geometry_gist ON merged_rivers USING gist(geometry);

VACUUM ANALYZE merged_rivers;

-- Results
SELECT strahler, COUNT(*), ROUND(COUNT(*)*100.0/SUM(COUNT(*)) OVER(), 1) as pct
FROM merged_rivers GROUP BY strahler ORDER BY strahler DESC;

SELECT name, strahler, ROUND(ST_Length(geometry::geography)/1000) as km
FROM merged_rivers WHERE name IS NOT NULL ORDER BY strahler DESC, km DESC LIMIT 20;

EOF

echo "✓ Done! Restart pg_tileserv"
