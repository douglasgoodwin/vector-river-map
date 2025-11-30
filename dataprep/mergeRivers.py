#!/usr/bin/env python3

"""Merge river records from NHDPlus.
NHDPlus breaks a river up into lots of separate little LineStrings,
separate rows in the database. This makes for inefficient queries
and tiles, so we merge them here. Rivers are merged on gnis_id
if one is present, or else the HUC8 from reachcode."""

import psycopg2
import time
from typing import Optional

# Database connection - can be overridden via environment variable
import os
DB_CONNECTION = os.getenv('DATABASE_URL', 'dbname=rivers')

conn = psycopg2.connect(DB_CONNECTION)
conn.autocommit = True      # required for Postgres bug workaround below
cur = conn.cursor()

start = time.time()
def log(msg: str) -> None:
    """Log a message with some reporting on time elapsed"""
    print(f"{time.time()-start:>7.2f}s {msg}")

# Create the schema
cur.execute("""drop table if exists merged_rivers;""")
cur.execute("""
create table merged_rivers (
    gnis_id text,
    name text,
    huc8 text,
    strahler smallint,
    geometry geometry);
""")
log("Table created")

# Need a separate cursor for inserts
insertCursor = conn.cursor()

### Merge rivers on gnis_id if gnis_id is not null
# Iterate through each unique gnis_id and create merged geometry
# grouping on the Strahler number.
# The HUC8 we're inserting is somewhat bogus; a single gnis_id river
# could span multiple HUC8s. We just pick one.
cur.execute("select distinct(gnis_id) from rivers where gnis_id is not null;")
count = cur.rowcount
log(f"Merging {count} unique gnis_ids, roughly {count/70:.0f} seconds")
for (gnisId,) in cur:
    insertCursor.execute("""
        insert into merged_rivers(gnis_id, name, strahler, huc8, geometry)
        select
            MAX(gnis_id) as gnis_id,
            MAX(name) as name,
            MAX(strahler) as strahler,
            MIN(huc8) as huc8,
            ST_LineMerge(ST_Union(geometry)) as geometry
        from rivers
        where gnis_id = %s
        group by strahler""", (gnisId,))
    # Partial status report
    count -= 1
    if (count % 10000 == 0):
        log(f"{count:7} gnis_ids to go {insertCursor.rowcount:5} rows added for gnis_id {gnisId}")

### Merge rivers on HUC8 if gnis_id is null.
# Iterate through each unique HUC8 and create merged geometry
# grouping on the Strahler number. We may be merging unrelated
# flowlines on occasion here, but they should be nearby.

cur.execute("select distinct(huc8) from rivers where gnis_id is null;")
count = cur.rowcount
log(f"Merging {count} unique HUC8s, roughly {count/6:.0f} seconds")
for (huc8,) in cur:
    # Try each insert several times; working around Postgres bug #8167
    tries = 3
    success = False
    while tries > 0 and not success:
        tries -= 1
        try:
            insertCursor.execute("""
                insert into merged_rivers(gnis_id, name, strahler, huc8, geometry)
                select
                    MAX(gnis_id) as gnis_id,
                    MAX(name) as name,
                    MAX(strahler),
                    MAX(huc8) as huc8,
                    ST_LineMerge(ST_Union(geometry)) as geometry
                from rivers
                where gnis_id is null and huc8 = %s
                group by strahler""", (huc8,))
            success = True
        except psycopg2.InternalError as e:
            # Work around Postgres bug #8167 on MacOS. Details at
            # https://gist.github.com/NelsonMinar/5588719
            if str(e).strip().endswith("Invalid argument"):
                log(f"Postgres bug #8167 on insert for HUC8 {huc8}. Tries left: {tries}")
            else:
                raise e
    if not success:
        log(f"Failed to insert HUC8 {huc8}, skipping.")

    # Partial status report
    count -= 1
    if (count % 100 == 0):
        log(f"{count:5} HUC8s to go {insertCursor.rowcount:5} rows added for HUC8 {huc8}")

# Commit the new table
conn.commit()

# Build some indices
log("Creating indices")
insertCursor.execute("create index merged_rivers_geometry_gist on merged_rivers using gist(geometry);")
insertCursor.execute("create index merged_rivers_strahler_idx ON merged_rivers(strahler);")
conn.commit()

# Can't vacuum in a transaction
conn.autocommit = True
insertCursor.execute("vacuum analyze merged_rivers;")

log("All done!")