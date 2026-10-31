#!/bin/zsh
# Kills a writer with SIGKILL at random moments and checks the database after each kill.
#
#   ./scripts/crash-test.sh [rounds]   # default 20
set -euo pipefail

cd "$(dirname "$0")/.."
ROUNDS="${1:-20}"
swift build -c release --product tmd-store-stress >/dev/null
TOOL="$(swift build -c release --show-bin-path)/tmd-store-stress"
DIR="$(mktemp -d)"
DB="$DIR/thinkmyday.sqlite"

for i in $(seq 1 "$ROUNDS"); do
  "$TOOL" write "$DB" &
  PID=$!
  sleep "0.$(( RANDOM % 9 + 1 ))"
  kill -9 "$PID"
  wait "$PID" 2>/dev/null || true
  printf "round %2d: " "$i"
  "$TOOL" verify "$DB"
done
echo "all $ROUNDS rounds ok ($DIR)"
