#!/bin/bash
# Download NHDPlus High Resolution data
# New USGS data source (replaces old AWS links)

mkdir -p NHD
cd NHD

# NHDPlus HR is organized by HUC4 regions
# For the contiguous US, you'll need multiple regions
# Here's California (HUC4: 1801-1811) as an example:

BASE_URL="https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHDPlusHR/Beta/GDB"

# Example: Download one region to test
# Region 18 (California)
wget "${BASE_URL}/NHDPLUS_H_1801_HU4_GDB.zip"

# Unzip
unzip NHDPLUS_H_1801_HU4_GDB.zip

echo "Downloaded NHDPlus HR for region 1801"
echo "For full US coverage, you'll need to download all HUC4 regions"
