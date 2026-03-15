#!/bin/bash
# Production build
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

source /home/opc/.oracle_env.sh 2>/dev/null || true

echo "Precompiling assets..."
RAILS_ENV=production bundle exec rails assets:precompile

echo "Build complete!"
