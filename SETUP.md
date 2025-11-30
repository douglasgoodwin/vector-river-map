# Setup Guide - Modernized Vector River Map

## Quick Start with Docker (Recommended)

### Prerequisites
- Docker and Docker Compose
- ~50GB free disk space for NHD data
- Python 3.12+ (for data preparation)

### Step 1: Start the Database

```bash
# Start PostGIS container
docker-compose up -d postgis

# Wait for PostgreSQL to be ready
docker-compose logs -f postgis
# Look for "database system is ready to accept connections"
```

### Step 2: Download and Import River Data

```bash
# Install Python dependencies
pip install -r requirements.txt

# Download NHD data (this will take a while - ~30GB download)
cd dataprep
./downloadNhd.sh

# Import into PostGIS
./importNhd.sh

# Merge river segments
python3 mergeRivers.py
```

### Step 3: Start the Tile Server

```bash
# Start pg_tileserv
docker-compose up -d pg_tileserv

# Check it's running
curl http://localhost:7800/index.json
```

### Step 4: View the Map

Open in your browser:
- Modern client: `clients/rivers-maplibre.html`
- Legacy client: `clients/rivers-leaflet.html`

## Manual Setup (Without Docker)

### Install PostgreSQL/PostGIS

**macOS:**
```bash
brew install postgresql postgis
brew services start postgresql
createdb rivers
psql rivers -c "CREATE EXTENSION postgis;"
```

**Ubuntu/Debian:**
```bash
sudo apt-get install postgresql-16 postgresql-16-postgis-3
sudo systemctl start postgresql
sudo -u postgres createdb rivers
sudo -u postgres psql rivers -c "CREATE EXTENSION postgis;"
```

### Install pg_tileserv

**From binary:**
```bash
# Download from https://github.com/CrunchyData/pg_tileserv/releases
wget https://github.com/CrunchyData/pg_tileserv/releases/download/vX.X.X/pg_tileserv_linux_amd64.zip
unzip pg_tileserv_linux_amd64.zip
chmod +x pg_tileserv

# Run it
DATABASE_URL="postgresql://user:pass@localhost/rivers" ./pg_tileserv --config server/pg_tileserv.toml
```

**From source (requires Go):**
```bash
git clone https://github.com/CrunchyData/pg_tileserv.git
cd pg_tileserv
go build
DATABASE_URL="postgresql://user:pass@localhost/rivers" ./pg_tileserv
```

### Data Preparation

```bash
cd dataprep

# Download NHD data
./downloadNhd.sh

# Import to PostGIS
./importNhd.sh

# Merge river segments
python3 mergeRivers.py
```

## Testing

### Test the Database

```bash
psql rivers -c "SELECT COUNT(*) FROM merged_rivers;"
psql rivers -c "SELECT name, strahler FROM merged_rivers LIMIT 5;"
```

### Test the Tile Server

```bash
# Using pg_tileserv (MVT tiles)
curl http://localhost:7800/public.merged_rivers.json

# Test a specific tile
curl http://localhost:7800/public.merged_rivers/13/1316/3169.pbf | wc -c
```

### Test the Client

```bash
# Serve the clients directory
python3 -m http.server 8080 --directory clients

# Open browser to http://localhost:8080/rivers-maplibre.html
```

### Run Python Tests

```bash
# Update serverTest.py for pg_tileserv endpoint
python3 clients/serverTest.py
```

## Upgrading from Old Version

### Key Differences

1. **Tile Format**: GeoJSON → MVT (Mapbox Vector Tiles)
   - Much smaller file sizes (~75% reduction)
   - Faster parsing in browser
   - Industry standard

2. **Tile Server**: TileStache → pg_tileserv
   - No Python server code needed
   - Better performance
   - Automatic layer discovery

3. **Client Library**: Leaflet → MapLibre GL JS
   - WebGL rendering (much faster)
   - Native MVT support
   - Better mobile performance

4. **Python**: 2.7 → 3.12+
   - Modern syntax (f-strings, type hints)
   - Better performance
   - Security updates

### Migration Path

If you have existing TileStache setup:

1. Keep TileStache running temporarily
2. Set up pg_tileserv on different port (7800)
3. Create new MapLibre client pointing to pg_tileserv
4. Compare tile sizes and performance
5. Once satisfied, shut down TileStache

## Troubleshooting

### Database Connection Issues

```bash
# Check if PostgreSQL is running
docker-compose ps
# or
pg_isready

# Check connection
psql postgresql://rivers:rivers_password@localhost:5432/rivers
```

### Tile Server Issues

```bash
# Check pg_tileserv logs
docker-compose logs -f pg_tileserv

# Verify tables are visible
curl http://localhost:7800/index.json

# Check specific table
curl http://localhost:7800/public.merged_rivers.json
```

### Client Issues

```bash
# Check browser console for errors
# Common issues:
# - CORS errors: pg_tileserv needs CORS enabled
# - 404 on tiles: Check table name in client config
# - Slow rendering: Enable browser hardware acceleration
```

### Data Import Issues

```bash
# Check NHD download
ls -lh NHD/

# Verify shapefile import
psql rivers -c "\dt"  # List tables
psql rivers -c "SELECT COUNT(*) FROM rivers;"

# Check geometry validity
psql rivers -c "SELECT COUNT(*) FROM rivers WHERE NOT ST_IsValid(geometry);"
```

## Performance Tips

### Database Optimization

```sql
-- Vacuum and analyze after data import
VACUUM ANALYZE merged_rivers;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan 
FROM pg_stat_user_indexes 
WHERE schemaname = 'public';

-- Add additional indices if needed
CREATE INDEX merged_rivers_huc8_idx ON merged_rivers(huc8);
CREATE INDEX merged_rivers_name_idx ON merged_rivers(name);
```

### Tile Server Optimization

```toml
# In pg_tileserv.toml
CacheMaxAge = 86400  # Cache tiles for 24 hours
DbPoolMaxConns = 20  # Increase connection pool
```

### Client Optimization

```javascript
// In your HTML client
map.setMaxBounds([...]);  // Limit pan area
map.setMinZoom(4);  // Don't render huge zoomed-out tiles
// Use tile size 512 for retina displays
```

## Next Steps

1. **Custom Styling**: Modify the MapLibre style in `rivers-maplibre.html`
2. **Add Features**: River name search, watershed filtering
3. **Extend Data**: Add more attributes (flow rate, elevation)
4. **Mobile App**: Use MapLibre Native for iOS/Android
5. **Analytics**: Add usage tracking with pg_tileserv metrics

## Resources

- [pg_tileserv Documentation](https://github.com/CrunchyData/pg_tileserv)
- [MapLibre GL JS Examples](https://maplibre.org/maplibre-gl-js/docs/examples/)
- [MVT Specification](https://github.com/mapbox/vector-tile-spec)
- [PostGIS Documentation](https://postgis.net/documentation/)
- [NHDPlus Data Portal](https://www.usgs.gov/national-hydrography)
