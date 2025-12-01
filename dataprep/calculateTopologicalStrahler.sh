#!/bin/bash

# Calculate TRUE Strahler order from network topology
# This uses actual tributary counting, not just length

DB=rivers

echo "Calculating topological Strahler order..."
echo "This uses actual stream network structure"
echo "May take 15-30 minutes for Western US..."
echo ""

psql -d $DB << 'EOF'

-- First, we need to work with the original rivers table which has segments
-- Then aggregate up to merged_rivers

-- Add columns for topology-based calculation
ALTER TABLE rivers ADD COLUMN IF NOT EXISTS stream_order INT DEFAULT 1;
ALTER TABLE rivers ADD COLUMN IF NOT EXISTS endpoints_count INT DEFAULT 0;

-- Create a simplified topology
-- Identify headwater segments (no upstream connections)
CREATE TEMP TABLE headwaters AS
SELECT DISTINCT r1.gid
FROM rivers r1
LEFT JOIN rivers r2 ON ST_Intersects(
    ST_EndPoint(r2.geometry),
    ST_StartPoint(r1.geometry)
)
WHERE r2.gid IS NULL;

-- Start with headwaters = order 1
UPDATE rivers SET stream_order = 1
WHERE gid IN (SELECT gid FROM headwaters);

-- Iteratively calculate orders (simplified Strahler)
-- This is an approximation but much better than length alone
DO $$
DECLARE
    changes INT := 1;
    iteration INT := 0;
    max_order INT := 1;
BEGIN
    WHILE changes > 0 AND iteration < 10 LOOP
        iteration := iteration + 1;
        
        -- For each segment, look at what flows into it
        WITH upstream_orders AS (
            SELECT 
                r1.gid,
                ARRAY_AGG(r2.stream_order ORDER BY r2.stream_order DESC) as orders
            FROM rivers r1
            JOIN rivers r2 ON ST_Intersects(
                ST_EndPoint(r2.geometry),
                ST_StartPoint(r1.geometry)
            )
            WHERE r2.stream_order > 0
            GROUP BY r1.gid
        )
        UPDATE rivers r
        SET stream_order = CASE
            -- If two or more streams of same order join, increase by 1
            WHEN u.orders[1] = u.orders[2] THEN u.orders[1] + 1
            -- Otherwise keep the highest order
            ELSE COALESCE(u.orders[1], 1)
        END
        FROM upstream_orders u
        WHERE r.gid = u.gid
        AND r.stream_order < COALESCE(
            CASE WHEN u.orders[1] = u.orders[2] 
            THEN u.orders[1] + 1 
            ELSE u.orders[1] END, 1);
        
        GET DIAGNOSTICS changes = ROW_COUNT;
        
        SELECT MAX(stream_order) INTO max_order FROM rivers;
        
        RAISE NOTICE 'Iteration %: % segments updated, max order: %', 
            iteration, changes, max_order;
    END LOOP;
END $$;

-- Now update merged_rivers with the maximum stream order from its segments
UPDATE merged_rivers m
SET strahler = COALESCE(
    (SELECT MAX(r.stream_order) 
     FROM rivers r 
     WHERE r.gnis_id = m.gnis_id 
     AND r.gnis_id IS NOT NULL),
    (SELECT MAX(r.stream_order)
     FROM rivers r
     WHERE r.huc8 = m.huc8
     AND r.gnis_id IS NULL
     AND m.gnis_id IS NULL)
);

-- For any that didn't get assigned (shouldn't happen), use length-based
UPDATE merged_rivers 
SET strahler = CASE
    WHEN strahler IS NULL AND ST_Length(geometry::geography)/1000 > 100 THEN 5
    WHEN strahler IS NULL AND ST_Length(geometry::geography)/1000 > 50 THEN 4
    WHEN strahler IS NULL AND ST_Length(geometry::geography)/1000 > 20 THEN 3
    WHEN strahler IS NULL AND ST_Length(geometry::geography)/1000 > 5 THEN 2
    WHEN strahler IS NULL THEN 1
    ELSE strahler
END;

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
LIMIT 25;

EOF

echo ""
echo "✓ Topological Strahler order calculated"
echo ""
echo "Restart pg_tileserv and reload map"
