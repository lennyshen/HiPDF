import os
from pathlib import Path
import shutil
import sys

app=Path(sys.argv[1]).resolve()
resources=app/'Contents/Resources'
runtime=resources/'python'
base=Path(sys.base_prefix).resolve()
if not (runtime/'bin/python3').exists():
    shutil.copytree(base,runtime,symlinks=True,dirs_exist_ok=True)
site=runtime/'lib/python3.12/site-packages'
source=Path(sys.prefix)/'lib/python3.12/site-packages'
if not (runtime/'.hipdf-dependencies').exists():
    if site.exists():shutil.rmtree(site)
    shutil.copytree(source,site,symlinks=False,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    (runtime/'.hipdf-dependencies').write_text('Python 3.12 / engine/requirements.txt\n')
# Retain component license files in the installed packages; remove only transient caches.
for directory in list(runtime.rglob('__pycache__')):
    shutil.rmtree(directory,ignore_errors=True)
for path in runtime.rglob('*.pyc'):
    path.unlink(missing_ok=True)
