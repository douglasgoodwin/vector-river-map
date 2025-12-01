#!/bin/bash

# Fix Strahler order joining from NHDPlus V2 to HR
# Uses multiple join strategies to maximize matches

DB=rivers

echo "Checking NHDPlus V2 import status..."

psql -d $DB << 'EOF'

-- Check if V2 data exists
SELECT 'V2 records: ' || COUNT(*) FROM nhdplusv2.plusflowlinevaa;

-- Show V2 Strahler distribution
SELECT 'V2 Strahler distribution:' as info;
SELECT streamorde, COUNT(*) 
FROM nhdplusv2.plusflowlinevaa 
WHERE streamorde IS NOT NULL
GROUP BY streamorde 
ORDER BY streamorde DESC 
LIMIT 10;

-- Try multiple join strategies

-- Strategy 1: Direct reachcode match
UPDATE rivers r
SET strahler = v2.streamorde
FROM nhdplusv2.plusflowlinevaa v2
WHERE r.reachcode = v2.reachcode
AND v2.streamorde IS NOT NULL
AND v2.streamorde BETWEEN 1 AND 10;

SELECT 'After direct reachcode join:' as status;
SELECT COUNT(*) FILTER (WHERE strahler BETWEEN 1 AND 10) as matched,
       COUNT(*) as total
FROM rivers;

-- Strategy 2: Try 14-character prefix match (HR uses longer codes)
UPDATE rivers r
SET strahler = v2.streamorde
FROM nhdplusv2.plusflowlinevaa v2
WHERE substring(r.reachcode from 1 for 14) = v2.reachcode
AND v2.streamorde IS NOT NULL
AND v2.streamorde BETWEEN 1 AND 10
AND (r.strahler IS NULL OR r.strahler NOT BETWEEN 1 AND 10);

SELECT 'After 14-char prefix join:' as status;
SELECT COUNT(*) FILTER (WHERE strahler BETWEEN 1 AND 10) as matched,
       COUNT(*) as total
FROM rivers;

-- Strategy 3: Try by COMID if we have it
-- Check if gid matches comid
UPDATE rivers r
SET strahler = v2.streamorde
FROM nhdplusv2.plusflowlinevaa v2
WHERE r.gid = v2.comid
AND v2.streamorde IS NOT NULL
AND v2.streamorde BETWEEN 1 AND 10
AND (r.strahler IS NULL OR r.strahler NOT BETWEEN 1 AND 10);

SELECT 'After COMID join:' as status;
SELECT COUNT(*) FILTER (WHERE strahler BETWEEN 1 AND 10) as matched,
       COUNT(*) as total
FROM rivers;

-- Show what we got
SELECT 'Final rivers Strahler distribution:' as info;
SELECT strahler, COUNT(*) 
FROM rivers 
WHERE strahler IS NOT NULL
GROUP BY strahler 
ORDER BY strahler DESC;

-- Now update merged_rivers
UPDATE merged_rivers m
SET strahler = (
    SELECT MAX(r.strahler)
    FROM rivers r
    WHERE r.gnis_id = m.gnis_id
    AND r.strahler BETWEEN 1 AND 10
)
WHERE m.gnis_id IS NOT NULL;

-- For unnamed, use HUC8
UPDATE merged_rivers m
SET strahler = (
    SELECT MAX(r.strahler)
    FROM rivers r
    WHERE r.huc8 = m.huc8
    AND r.gnis_id IS NULL
    AND m.gnis_id IS NULL
    AND r.strahler BETWEEN 1 AND 10
)
WHERE m.gnis_id IS NULL;

-- Fix geometry
ALTER TABLE merged_rivers 
  ALTER COLUMN geometry TYPE geometry(GEOMETRY, 4269) 
  USING ST_SetSRID(geometry, 4269);

DROP INDEX IF EXISTS merged_rivers_geometry_gist;
CREATE INDEX merged_rivers_geometry_gist ON merged_rivers USING gist(geometry);

VACUUM ANALYZE merged_rivers;

-- Final results
SELECT 'Final merged_rivers Strahler distribution:' as info;
SELECT strahler, COUNT(*) 
FROM merged_rivers
WHERE strahler IS NOT NULL
GROUP BY strahler 
ORDER BY strahler DESC;

-- Check Truckee
SELECT 'Truckee River area:' as info;
SELECT name, strahler, ROUND(ST_Length(geometry::geography)/1000) as km
FROM merged_rivers 
WHERE name ILIKE '%truckee%' OR name ILIKE '%tahoe%'
ORDER BY strahler DESC NULLS LAST;

EOF

echo ""
echo "If Truckee River is still order 1, the V2 data doesn't match the HR data"
echo "This can happen if different versions were used"
