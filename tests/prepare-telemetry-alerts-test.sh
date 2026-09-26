#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(cd -- "$(dirname -- "$0")/.." && pwd -P)}
bash -n "$root/scripts/prepare-telemetry-alerts.sh"
python3 "$root/tests/fixtures/prepare-telemetry-alerts/driver.py" "$root"
