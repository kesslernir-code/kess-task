#!/usr/bin/env bash
# Pushes apps-script/ to Apps Script and points the web app at the new code.
set -euo pipefail
cd "$(dirname "$0")"
clasp push --force
clasp update-deployment "$(tr -d '\r\n' < deployment-id.txt)" -d "$(date +%F-%H%M)"
