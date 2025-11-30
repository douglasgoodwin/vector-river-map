#!/usr/bin/env python3

"""A very simple test + benchmark for serving vector tiles"""

import requests
import time
from typing import Tuple

# Configuration
URLBASE = 'http://127.0.0.1:8000'
TEST_TILE = 'rivers/8/41/98.json'

def test_single_request(urlbase: str = URLBASE, url: str = TEST_TILE) -> float:
    """Test a single tile request and return time in ms"""
    start = time.time()
    r = requests.get(f"{urlbase}/{url}")
    end = time.time()
    
    assert r.status_code == 200, f"Got status code {r.status_code}"
    j = r.json()
    assert j["type"] == "FeatureCollection", "Response is not a FeatureCollection"
    assert len(j["features"]) > 0, "No features in response"
    
    elapsed_ms = 1000 * (end - start)
    print(f"Single request took {elapsed_ms:.0f} ms")
    return elapsed_ms

def test_batch_requests(urlbase: str = URLBASE) -> Tuple[int, float]:
    """Test a batch of tile requests using asyncio"""
    batch = (
        'rivers/8/42/99.json', 'rivers/8/43/98.json', 'rivers/8/41/99.json',
        'rivers/8/42/98.json', 'rivers/8/42/97.json', 'rivers/8/41/98.json',
        'rivers/8/40/99.json', 'rivers/8/41/100.json', 'rivers/8/42/100.json',
        'rivers/8/40/98.json', 'rivers/8/43/97.json', 'rivers/8/43/99.json',
        'rivers/8/40/100.json', 'rivers/8/44/99.json', 'rivers/8/44/98.json',
        'rivers/8/39/98.json', 'rivers/8/39/99.json', 'rivers/8/44/97.json',
        'rivers/8/39/100.json', 'rivers/8/43/100.json', 'rivers/8/39/97.json',
        'rivers/8/40/97.json', 'rivers/8/44/100.json', 'rivers/8/41/97.json'
    )
    
    start = time.time()
    # Use session for connection pooling
    with requests.Session() as session:
        futures = [session.get(f"{urlbase}/{url}") for url in batch]
    end = time.time()
    
    # Verify all responses
    for r in futures:
        assert r.status_code == 200, f"Got status code {r.status_code}"
    
    elapsed_ms = 1000 * (end - start)
    print(f"{len(batch)} requests in {elapsed_ms:.0f}ms")
    return len(batch), elapsed_ms

if __name__ == "__main__":
    print("Testing vector tile server...")
    test_single_request()
    test_batch_requests()
    print("All tests passed!")
