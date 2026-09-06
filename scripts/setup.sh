#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
HIPDF_UV="$(command -v uv || true)"
if [ -z "$HIPDF_UV" ] && [ -x "$HOME/.local/bin/uv" ]; then HIPDF_UV="$HOME/.local/bin/uv"; fi
test -x "$HIPDF_UV" || { echo '请先安装 uv：https://docs.astral.sh/uv/'; exit 1; }
"$HIPDF_UV" venv --python 3.12 .venv
"$HIPDF_UV" pip install --python .venv/bin/python -r engine/requirements.lock.txt
.venv/bin/python scripts/catalog.py
mkdir -p .runtime
if [ ! -d .runtime/LibreOffice.app ]; then
  echo '下载并校验项目独立的 Office 引擎（约 285 MB）…'
  curl --fail --location --retry 5 --retry-all-errors --continue-at - --output .runtime/LibreOffice.dmg 'https://mirrors.tuna.tsinghua.edu.cn/libreoffice/libreoffice/stable/26.8.0/mac/aarch64/LibreOffice_26.8.0_MacOS_aarch64.dmg'
  echo '8858d8058da4f862f47559486814e65efc27294da67c5e4bb56b006b1ee59f89  .runtime/LibreOffice.dmg' | shasum -a 256 -c -
  hdiutil attach .runtime/LibreOffice.dmg -nobrowse -readonly -mountpoint .runtime/libreoffice-volume
  trap 'hdiutil detach .runtime/libreoffice-volume >/dev/null 2>&1 || true' EXIT
  ditto .runtime/libreoffice-volume/LibreOffice.app .runtime/LibreOffice.app
  hdiutil detach .runtime/libreoffice-volume
  trap - EXIT
fi
echo '依赖准备完成。运行 bash scripts/build.sh 构建应用。'
