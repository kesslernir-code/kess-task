#!/usr/bin/env bash
# Runs an action of the Kess Task Gmail script through its web app.
#   ./run.sh status
#   ./run.sh dryRun '{"days":14,"offset":0,"limit":30}'
# Actions: setup, checkGmail, dryRun, startBackfill, stopBackfill, status.
# The secret is read from ~/.kess-task/runner-token.txt and never stored in the repo.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
id="$(tr -d '\r\n' < "$here/deployment-id.txt")"
extra="${2:-}"
[ -z "$extra" ] && extra='{}'
python -c '
import json, os, sys
d = json.loads(sys.argv[2])
d["action"] = sys.argv[1]
d["token"] = open(os.path.expanduser("~/.kess-task/runner-token.txt")).read().strip()
print(json.dumps(d))
' "$1" "$extra" |
  curl -sSL -m 400 -H 'Content-Type: application/json' --data-binary @- \
    "https://script.google.com/macros/s/$id/exec"
