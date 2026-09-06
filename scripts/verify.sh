#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
HIPDF_PYTHON="${HIPDF_BUILD_PYTHON:-.venv/bin/python}"
swift build -j 2
swiftc -parse-as-library Sources/HiPDF/PDFLoader.swift scripts/preview_smoke.swift -o .build/preview-smoke
.build/preview-smoke
PYTHONPATH=engine "$HIPDF_PYTHON" -m unittest discover -s tests -v
codesign --verify --deep --strict dist/HiPDF.app
dist/HiPDF.app/Contents/Resources/python/bin/python3 dist/HiPDF.app/Contents/Resources/engine/worker.py <<'EOF'
{"action":"health"}
EOF
echo '构建、集成测试、应用签名与内置引擎检查通过。'
