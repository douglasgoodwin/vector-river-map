# Data Preparation Scripts

This directory contains scripts for downloading and importing NHDPlus High Resolution (HR) river data into PostGIS.

## Quick Start

```bash
# 1. Download river data (choose one option below)
./downloadWestUS.sh       # Western US only (~30GB, 1-2 hours)
# OR
./downloadAllRegions.sh   # All contiguous 48 states (~100GB, 4-8 hours)

# 2. Create the rivers table
./createRiversTable.sh

# 3. Merge river segments
python3 mergeRivers.py

# 4. Check your data
cd .. && ./checkStatus.sh
```

## Scripts Overview

### Download Scripts

#### `downloadWestUS.sh` ⭐ Recommended for Getting Started
Downloads NHDPlus HR data for Western United States regions:
- California (Regions 1801-1811)
- Pacific Northwest - Oregon, Washington (1701-1712)
- Great Basin - Nevada, Utah (1601-1605)
- Lower Colorado - Arizona (1501-1507)
- Upper Colorado - Colorado (1401-1408)

**Size:** ~30GB  
**Time:** 1-2 hours  
**Coverage:** Western US states

```bash
./downloadWestUS.sh
```

#### `downloadAllRegions.sh`
Downloads data for all HUC4 regions in the contiguous 48 states (~200+ regions).

**Size:** ~100GB  
**Time:** 4-8 hours  
**Coverage:** Complete US

```bash
./downloadAllRegions.sh
```

#### `downloadNhdModern.sh`
Basic download script - downloads a single region for testing.

**Use for:** Testing or downloading specific individual regions

```bash
./downloadNhdModern.sh
```

### Import Scripts

#### `createRiversTable.sh` ⭐ Use This One
Creates the `rivers` table from imported NHDFlowline data with correct field mappings for NHDPlus HR.

**What it does:**
- Creates `rivers` table with standardized fields
- Estimates Strahler stream order from segment length
- Creates spatial indices
- Filters out coastlines

```bash
./createRiversTable.sh
```

**Output fields:**
- `gid` - Unique identifier
- `gnis_id` - Geographic Names ID (text)
- `name` - River/stream name
- `reachcode` - Hydrologic unit code
- `huc8` - 8-digit watershed code
- `strahler` - Stream order (1-6, estimated)
- `geometry` - Line geometry

#### `importNhdHR.sh`
Comprehensive import script that handles the full pipeline. Currently has field name issues - use `createRiversTable.sh` instead after manual import.

#### `mergeRivers.py` ⭐ Required
Python script that merges individual river segments into continuous features.

**What it does:**
- Groups segments by GNIS ID (river name)
- Merges geometries into continuous LineStrings
- Groups unnamed segments by watershed (HUC8)
- Creates optimized `merged_rivers` table for tile serving

**Time:** 5-60 minutes depending on data size

```bash
python3 mergeRivers.py
```

### Legacy Scripts (Old NHDPlus V2)

#### `downloadNhd.sh` ⚠️ Deprecated
Original download script for NHDPlus V2 - URLs are broken, use new scripts instead.

#### `importNhd.sh` ⚠️ Deprecated
Original import for NHDPlus V2 format.

#### `importAus.sh`
Import script for Australian river data (experimental).

#### `processNhd.sql`
SQL processing for NHDPlus V2 format.

### Utility Scripts

#### `inspectNhdFields.sh`
Diagnostic script to examine the database schema and field names.

```bash
./inspectNhdFields.sh
```

## Data Pipeline Workflow

### Full Pipeline

```
1. Download Data
   └─> downloadWestUS.sh or downloadAllRegions.sh
        └─> Creates NHD/*.gdb files

2. Import to PostGIS
   └─> ogr2ogr (automatic via importNhdHR.sh)
        └─> Creates 'nhdflowline' table

3. Create Rivers Table
   └─> createRiversTable.sh
        └─> Creates 'rivers' table with standardized fields

4. Merge Segments
   └─> mergeRivers.py
        └─> Creates 'merged_rivers' table for serving

5. Serve Tiles
   └─> pg_tileserv
        └─> http://localhost:7800/public.merged_rivers/{z}/{x}/{y}.pbf
```

### Database Tables

After a successful import, you'll have:

| Table | Rows | Purpose |
|-------|------|---------|
| `nhdflowline` | ~15M (West US) | Raw imported data from GDB files |
| `rivers` | ~15M | Standardized schema, filtered data |
| `merged_rivers` | ~500K | Merged continuous rivers for serving |

## Data Sources

### NHDPlus High Resolution (HR)
- **Source:** USGS National Hydrography Dataset
- **Format:** File Geodatabase (.gdb)
- **URL Pattern:** `https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHDPlusHR/Beta/GDB/NHDPLUS_H_{HUCID}_HU4_GDB.zip`
- **Documentation:** https://www.usgs.gov/national-hydrography/nhdplus-high-resolution

### HUC Region Codes

Rivers are organized by Hydrologic Unit Code (HUC) regions:

- **Region 01:** New England
- **Region 02:** Mid-Atlantic
- **Region 03:** South Atlantic-Gulf
- **Region 04:** Great Lakes
- **Region 05:** Ohio
- **Region 06:** Tennessee
- **Region 07:** Upper Mississippi
- **Region 08:** Lower Mississippi
- **Region 09:** Souris-Red-Rainy
- **Region 10:** Missouri
- **Region 11:** Arkansas-White-Red
- **Region 12:** Texas-Gulf
- **Region 13:** Rio Grande
- **Region 14:** Upper Colorado
- **Region 15:** Lower Colorado
- **Region 16:** Great Basin
- **Region 17:** Pacific Northwest
- **Region 18:** California

Each region contains multiple HUC4 sub-regions (e.g., 1801, 1802, etc.)

## Requirements

### Software
- PostgreSQL 14+ with PostGIS extension
- Python 3.12+
- GDAL/OGR tools (`ogr2ogr`, `ogrinfo`)
- `wget` or `curl` for downloads
- `unzip` for extracting archives

### Python Packages
```bash
pip install -r ../requirements.txt
```

Required packages:
- `psycopg2-binary` - PostgreSQL adapter
- `requests` - HTTP library (for testing)

### Disk Space
- **Western US:** ~30GB download + ~50GB database = ~80GB total
- **Full US:** ~100GB download + ~150GB database = ~250GB total

## Troubleshooting

### Download Issues

**Problem:** Download fails or times out
```bash
# Downloads are resumable - just re-run the script
./downloadWestUS.sh
```

**Problem:** URL not found (404 error)
```bash
# HUC region codes may have changed
# Check current data catalog at:
# https://www.usgs.gov/national-hydrography/access-national-hydrography-products
```

### Import Issues

**Problem:** `ogr2ogr: command not found`
```bash
# Install GDAL
brew install gdal              # macOS
sudo apt install gdal-bin      # Ubuntu/Debian
```

**Problem:** `ERROR: column "streamorde" does not exist`
```bash
# Use createRiversTable.sh instead of importNhdHR.sh
./createRiversTable.sh
```

**Problem:** Database connection refused
```bash
# Check PostgreSQL is running
brew services list | grep postgresql    # macOS
systemctl status postgresql             # Linux

# Verify database exists
psql -l | grep rivers
```

### Merge Issues

**Problem:** `mergeRivers.py` takes too long
```bash
# This is normal for large datasets
# Western US: ~30-60 minutes
# Full US: ~2-4 hours

# Monitor progress - it prints updates every 10,000 features
# You can stop with Ctrl+C and restart - it will recreate the table
```

**Problem:** Out of memory during merge
```bash
# Increase PostgreSQL memory settings in postgresql.conf
shared_buffers = 2GB
work_mem = 256MB

# Or process regions in smaller batches
```

### Data Quality Issues

**Problem:** Rivers appear disconnected
```bash
# This is normal - NHDPlus HR has gaps at watershed boundaries
# The ST_LineMerge function in mergeRivers.py handles most cases
```

**Problem:** Strahler order seems wrong
```bash
# We estimate order from segment length since NHDPlus HR doesn't include it
# This is approximate - if you need accurate stream order, you'd need to
# calculate it from the network topology (more complex)
```

## Advanced Usage

### Download Specific Regions

```bash
cd NHD

# Download just the San Francisco Bay Area (HUC 1805)
wget https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHDPlusHR/Beta/GDB/NHDPLUS_H_1805_HU4_GDB.zip
unzip NHDPLUS_H_1805_HU4_GDB.zip

# Import just this region
cd ..
./createRiversTable.sh
python3 mergeRivers.py
```

### Custom Strahler Order Calculation

To calculate true Strahler order from network topology, you'd need to:

1. Build a network topology graph
2. Identify headwaters (no upstream segments)
3. Calculate order recursively downstream
4. Use PostGIS topology functions or a graph library

This is beyond the scope of these scripts but possible with more advanced SQL.

### Filtering by Watershed

```sql
-- Import only specific watersheds
CREATE TABLE rivers AS
SELECT 
    gid, gnis_id, gnis_name as name, reachcode,
    substring(reachcode from 1 for 8) as huc8,
    CASE WHEN lengthkm > 50 THEN 5
         WHEN lengthkm > 20 THEN 4
         WHEN lengthkm > 5 THEN 3
         ELSE 2 END as strahler,
    geom as geometry
FROM nhdflowline
WHERE ftype = 460
  AND substring(reachcode from 1 for 4) IN ('1805', '1806', '1807')  -- SF Bay, Sacramento, San Joaquin
  AND fcode NOT IN (56600);
```

## Performance Tips

### Database Optimization

```sql
-- After import, optimize the database
VACUUM ANALYZE rivers;
VACUUM ANALYZE merged_rivers;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan 
FROM pg_stat_user_indexes 
WHERE schemaname = 'public';
```

### Faster Merging

```python
# In mergeRivers.py, you can adjust the batch size
# Larger batches = faster but more memory
# Current: processes one gnis_id at a time
```

### Tile Generation

```sql
-- Create a materialized view for faster tile serving at low zoom levels
CREATE MATERIALIZED VIEW rivers_simplified AS
SELECT 
    gnis_id, name, huc8, strahler,
    ST_Simplify(geometry, 0.001) as geometry
FROM merged_rivers
WHERE strahler >= 4;

CREATE INDEX rivers_simplified_geom_idx ON rivers_simplified USING gist(geometry);
```

## Data Attribution

When using this data, please attribute:

**NHDPlus High Resolution (NHDPlus HR)**  
U.S. Geological Survey, 2019, National Hydrography Dataset (ver. USGS National Hydrography Dataset Best Resolution (NHD) for Hydrologic Unit (HU) 4 - 2001 (published 20191002)), accessed [date], at https://www.usgs.gov/national-hydrography/access-national-hydrography-products

## Related Documentation

- [Main Project README](../README.md)
- [Setup Guide](../SETUP.md)
- [Modernization Guide](../MODERNIZATION.md)
- [USGS NHDPlus HR Documentation](https://www.usgs.gov/national-hydrography/nhdplus-high-resolution)

## Questions?

If you run into issues:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Run `../checkStatus.sh` to see current status
3. Check PostgreSQL logs for database errors
4. Verify disk space with `df -h`

---

*Last Updated: November 2025*  
*For the 2025 modernization of Nelson Minar's 2013 Vector River Map tutorial*