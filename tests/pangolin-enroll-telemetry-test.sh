#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(cd "$(dirname "$0")/.." && pwd -P)}
bash -n "$root/scripts/pangolin-enroll-telemetry.sh"
command -v python3 >/dev/null
command -v yq >/dev/null
python3 "$root/tests/fixtures/pangolin-enroll/driver.py" "$root"
