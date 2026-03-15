#!/bin/bash
# Start development servers - Port Block 15 (3170-3179)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Source Oracle environment
source /home/opc/.oracle_env.sh 2>/dev/null || true
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

# Start via foreman (reads Procfile.dev and .env)
if command -v foreman &> /dev/null; then
  exec foreman start -f Procfile.dev
else
  echo "foreman not found. Starting Rails server only..."
  exec bin/rails server -p 3170
fi
