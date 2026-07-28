#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
exec python3 "$ROOT/scripts/import-project-vocabulary.py"
