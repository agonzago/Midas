#!/bin/bash
# Quick validation script for MIDAS fixes

echo "=== MIDAS Implementation Fixes Validation ==="
echo ""
echo "This script checks that the key files have been updated correctly."
echo ""

# Check if key files exist
echo "1. Checking if modified files exist..."
files=(
    "gpm_now/R/midas_models.R"
    "gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R"
    "gpm_now/test_midas_fixes.R"
    "MIDAS_ANALYSIS.md"
    "IMPLEMENTATION_FIXES.md"
)

all_exist=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file exists"
    else
        echo "  ✗ $file NOT FOUND"
        all_exist=false
    fi
done

echo ""

# Check for key changes in midas_models.R
echo "2. Checking for key fixes in midas_models.R..."
if grep -q "y_name <- names(model_data)\[1\]" gpm_now/R/midas_models.R; then
    echo "  ✓ Variable name extraction added"
else
    echo "  ✗ Variable name extraction NOT FOUND"
fi

if grep -q "newdata\[\[y_name\]\] <- c(y_hist, NA)" gpm_now/R/midas_models.R; then
    echo "  ✓ NA placeholder for forecast period added"
else
    echo "  ✗ NA placeholder NOT FOUND"
fi

if grep -q "lag_map = NULL" gpm_now/R/midas_models.R; then
    echo "  ✓ lag_map parameter added to extract_forecast_data"
else
    echo "  ✗ lag_map parameter NOT FOUND"
fi

echo ""

# Check for improvements in vintage builder
echo "3. Checking for improvements in 01_build_pseudo_vintages.R..."
if grep -q "monthly_vintage <- rbindlist" gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R; then
    echo "  ✓ Explicit data slicing added"
else
    echo "  ✗ Explicit data slicing NOT FOUND"
fi

if grep -q "Validation: Week 2" gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R; then
    echo "  ✓ Validation logic added"
else
    echo "  ✗ Validation logic NOT FOUND"
fi

echo ""
echo "=== Validation Complete ==="
echo ""
echo "To test the implementation:"
echo "  1. cd gpm_now"
echo "  2. Rscript test_midas_fixes.R"
echo ""
echo "To run the full workflow:"
echo "  1. cd gpm_now/midas_model_selection/code"
echo "  2. Rscript 00_run_all.R"
echo ""
