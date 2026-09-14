#!/bin/bash
# Generate test data files for SendCUIEmail testing
# Run this script to create/recreate all test files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$SCRIPT_DIR"

echo "Generating test data files..."

# ============================================================================
# Small test files
# ============================================================================

# Small text file (~100 bytes)
echo "Creating small_text.txt..."
cat > small_text.txt << 'EOF'
This is a sample text file for testing SendCUIEmail encryption.
It contains plain text that should be preserved exactly after decryption.
EOF

# Empty file (0 bytes)
echo "Creating empty.txt..."
> empty.txt

# Binary sample with null bytes (~1 KB)
echo "Creating binary_sample.bin..."
dd if=/dev/urandom bs=1024 count=1 of=binary_sample.bin 2>/dev/null
# Inject some null bytes to test binary handling
printf '\x00\x00\x00' | dd of=binary_sample.bin bs=1 seek=100 conv=notrunc 2>/dev/null

# ============================================================================
# Medium/Large binary files
# ============================================================================

# Medium file (~1 MB)
echo "Creating medium_file.bin..."
dd if=/dev/urandom bs=1024 count=1024 of=medium_file.bin 2>/dev/null

# Large file (10 MB - maximum supported)
echo "Creating large_file_10mb.bin (this may take a moment)..."
dd if=/dev/urandom bs=1048576 count=10 of=large_file_10mb.bin 2>/dev/null

# ============================================================================
# README in multiple formats (always uses latest README.md)
# ============================================================================

echo "Generating README files from README.md..."

# README.txt - plain text copy
echo "  Creating README.txt..."
cp "$REPO_ROOT/README.md" README.txt

# README.pdf, README.docx, README.png via pandoc/convert
if command -v pandoc &> /dev/null; then
    # README.pdf
    echo "  Creating README.pdf..."
    pandoc "$REPO_ROOT/README.md" \
        -o README.pdf \
        --pdf-engine=pdflatex \
        -V geometry:margin=1in \
        -V fontsize=11pt \
        -V colorlinks=true \
        --metadata title="SendCUIEmail Documentation" \
        2>/dev/null || echo "    WARNING: PDF generation failed"

    # README.docx
    echo "  Creating README.docx..."
    pandoc "$REPO_ROOT/README.md" \
        -o README.docx \
        --metadata title="SendCUIEmail Documentation" \
        2>/dev/null || echo "    WARNING: DOCX generation failed"

    # README.png - convert first page of PDF to image
    echo "  Creating README.png..."
    PNG_CREATED=0

    # Try ImageMagick first
    if command -v convert &> /dev/null; then
        if convert -density 150 README.pdf[0] -quality 90 README.png 2>/dev/null; then
            PNG_CREATED=1
        fi
    fi

    # Fall back to pdftoppm (Poppler) if ImageMagick failed or not available
    if [ $PNG_CREATED -eq 0 ] && command -v pdftoppm &> /dev/null; then
        if pdftoppm -png -f 1 -l 1 -r 150 README.pdf README_page 2>/dev/null && \
           mv README_page-1.png README.png 2>/dev/null; then
            PNG_CREATED=1
        fi
    fi

    if [ $PNG_CREATED -eq 0 ]; then
        echo "    WARNING: PNG generation failed (install imagemagick or poppler)"
    fi
    # sample.xlsx - Excel file for format testing
    echo "  Creating sample.xlsx..."
    if command -v python3 &> /dev/null; then
        python3 << 'PYTHON_SCRIPT'
try:
    from openpyxl import Workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Sample Data"
    ws['A1'] = "SendCUIEmail Test Spreadsheet"
    ws['A2'] = "This file tests XLSX format encryption."
    ws['A4'] = "Row"
    ws['B4'] = "Data"
    for i in range(1, 11):
        ws[f'A{i+4}'] = i
        ws[f'B{i+4}'] = f"Sample data row {i}"
    wb.save('sample.xlsx')
except ImportError:
    print("    WARNING: openpyxl not installed (pip install openpyxl)")
except Exception as e:
    print(f"    WARNING: XLSX generation failed: {e}")
PYTHON_SCRIPT
    else
        echo "    WARNING: python3 not found, skipping XLSX"
    fi
else
    echo "  WARNING: pandoc not installed"
    echo "  Install with: brew install pandoc"
    echo "  Skipping PDF, DOCX, PNG, and XLSX generation"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "Test data files generated:"
ls -lh *.txt *.bin *.pdf *.docx 2>/dev/null || ls -lh *.txt *.bin 2>/dev/null

echo ""
echo "Done!"
