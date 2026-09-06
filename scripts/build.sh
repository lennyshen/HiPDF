#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
HIPDF_PYTHON="${HIPDF_BUILD_PYTHON:-.venv/bin/python}"
test -x "$HIPDF_PYTHON" || { echo '请先运行 bash scripts/setup.sh'; exit 1; }
test -d .runtime/LibreOffice.app || { echo 'Office 引擎缺失，请运行 bash scripts/setup.sh'; exit 1; }
swift build -c release -j 2
HIPDF_DIST_DIR="${HIPDF_DIST_DIR:-dist}"
mkdir -p "$HIPDF_DIST_DIR"
HIPDF_APP="$HIPDF_DIST_DIR/HiPDF.app"
mkdir -p "$HIPDF_APP/Contents/MacOS" "$HIPDF_APP/Contents/Resources"
cp .build/release/HiPDF "$HIPDF_APP/Contents/MacOS/HiPDF"
cp .build/release/HiPDFOCR "$HIPDF_APP/Contents/Resources/HiPDFOCR"
cp Resources/Info.plist "$HIPDF_APP/Contents/Info.plist"
cp Resources/tools.json "$HIPDF_APP/Contents/Resources/tools.json"
cp Resources/HiPDF.icns "$HIPDF_APP/Contents/Resources/HiPDF.icns"
cp Resources/USER_GUIDE.html "$HIPDF_APP/Contents/Resources/USER_GUIDE.html"
cp docs/FEATURES.md THIRD_PARTY_NOTICES.md LICENSE "$HIPDF_APP/Contents/Resources/"
ditto engine "$HIPDF_APP/Contents/Resources/engine"
# A relocatable python-build-standalone runtime; no dependency on a user's Python installation.
"$HIPDF_PYTHON" scripts/bundle_runtime.py "$HIPDF_APP"
if [ ! -d "$HIPDF_APP/Contents/Resources/LibreOffice.app" ]; then
  ditto .runtime/LibreOffice.app "$HIPDF_APP/Contents/Resources/LibreOffice.app"
fi
# Local ad-hoc signature. Distribution with Developer ID/notarization is a separate release step.
codesign --force --deep --sign - "$HIPDF_APP"
codesign --verify --deep --strict "$HIPDF_APP"
echo "已构建：$HIPDF_APP"
if [ "${1:-}" = '--archive' ]; then
  ditto -c -k --sequesterRsrc --keepParent "$HIPDF_APP" "$HIPDF_DIST_DIR/HiPDF-macOS-arm64.zip"
  (cd "$HIPDF_DIST_DIR" && shasum -a 256 HiPDF-macOS-arm64.zip > SHA256SUMS.txt)
fi
