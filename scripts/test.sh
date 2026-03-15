#!/bin/bash
# Run all tests
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

source /home/opc/.oracle_env.sh 2>/dev/null || true
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

echo "Running Rails tests..."
bundle exec rails test

echo "Running Brakeman security scan..."
bundle exec brakeman --no-pager -q

echo "All tests complete!"
