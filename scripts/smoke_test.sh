#!/usr/bin/env bash
# smoke_test.sh URL [EXPECTED_COMMIT]
# Passes when URL/health answers 200 with ok=true (and, if given, is serving EXPECTED_COMMIT).
# Retries for ~30s, because a fresh alias can take a moment to settle.
set -euo pipefail

url="${1:?usage: smoke_test.sh URL [EXPECTED_COMMIT]}"
expected="${2:-}"
attempts="${SMOKE_ATTEMPTS:-10}"
delay="${SMOKE_DELAY:-3}"

for i in $(seq 1 "$attempts"); do
  body=$(curl -sS --max-time 5 -w '\n%{http_code}' "${url%/}/health" || printf '\n000')
  code=$(printf '%s' "$body" | tail -n1)
  json=$(printf '%s' "$body" | sed '$d')
  commit=$(printf '%s' "$json" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("commit",""))
except Exception: print("")')

  if [ "$code" = "200" ] && { [ -z "$expected" ] || [ "$commit" = "$expected" ]; }; then
    echo "✅ smoke test passed (attempt $i): HTTP 200, commit ${commit:0:7}"
    exit 0
  fi
  echo "… attempt $i/$attempts: HTTP $code, commit '${commit:0:7}'${expected:+ (want ${expected:0:7})}"
  [ "$i" -lt "$attempts" ] && sleep "$delay"
done

echo "❌ smoke test failed: ${url%/}/health never came back healthy${expected:+ on ${expected:0:7}}" >&2
exit 1
