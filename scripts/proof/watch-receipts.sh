#!/usr/bin/env bash
# Prints receipt count and last line whenever receipts.jsonl changes.
RECEIPTS="${1:-$HOME/Library/Application Support/Mumbli/proof/receipts.jsonl}"
echo "Watching: $RECEIPTS"
last_count=-1
while true; do
  if [[ -f "$RECEIPTS" ]]; then
    count=$(grep -c . "$RECEIPTS" 2>/dev/null || echo 0)
    if [[ "$count" != "$last_count" ]]; then
      last_count=$count
      echo "[$(date '+%H:%M:%S')] signed receipts: $count"
      tail -1 "$RECEIPTS" 2>/dev/null | python3 -c "
import json,sys
line=sys.stdin.read().strip()
if not line: sys.exit(0)
r=json.loads(line)
b=r.get('receipt',{}).get('body',{})
print('  latest:', b.get('function_name'), b.get('time_bucket'), 'commitment='+r.get('commitment','')[:16]+'…')
" 2>/dev/null || true
    fi
  else
    if [[ "$last_count" != "0" ]]; then
      echo "[$(date '+%H:%M:%S')] waiting for receipts file (dictate with proof enabled)..."
      last_count=0
    fi
  fi
  sleep 2
done
