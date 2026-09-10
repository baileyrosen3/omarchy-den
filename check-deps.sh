#!/usr/bin/env bash
# Read-only preflight; no dependencies are downloaded or installed here.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo 'Den requires Python 3.9 or newer. Install Python before continuing.' >&2
  exit 1
fi

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' || {
  echo 'Den requires Python 3.9 or newer.' >&2
  exit 1
}

den_plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 -B "$den_plugin_dir/collie.py" check
