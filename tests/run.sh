#!/usr/bin/env bash
#
# Runs mac-tune against a throwaway $HOME and checks what it deletes and what
# it keeps. Fake "Claude tabs" are sleep processes renamed to claude-test.
#
#   tests/run.sh             run everything that is safe on this machine
#   CI=1 tests/run.sh        also run the settings test, which flips the real
#                            Chrome/Brave BackgroundModeEnabled preference

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
BIN="$PWD/mac-tune"
SANDBOX=$(mktemp -d)
PIDS=()
cleanup(){ for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$p" 2>/dev/null; done; rm -rf "$SANDBOX"; }
trap cleanup EXIT

fails=0
check(){ # $1=name, rest=command that must succeed
  local name=$1; shift
  if "$@"; then printf '  ok    %s\n' "$name"; else printf '  FAIL  %s\n' "$name"; fails=$((fails+1)); fi
}
exists(){ [[ -e "$1" ]]; }
missing(){ [[ ! -e "$1" ]]; }
alive(){ local s; s=$(ps -o stat= -p "$1" 2>/dev/null); [[ -n "$s" && "$s" != Z* ]]; }
dead(){ ! alive "$1"; }
tune(){ HOME="$FAKE" /bin/bash "$BIN" "$@" >"$SANDBOX/out.txt" 2>&1; }
fresh(){ FAKE="$SANDBOX/home-$1"; mkdir -p "$FAKE"; }

echo "flags"
fresh flags
check "--help prints usage" tune --help
check "--help mentions --claude-stop" grep -q -- "--claude-stop" "$SANDBOX/out.txt"
tune --bogus; check "unknown flag exits 2" test $? -eq 2
tune --only nope; check "unknown step exits 2" test $? -eq 2
tune --days x; check "--days needs a number" test $? -eq 2

echo "claude-chats"
fresh chats
C="$FAKE/.claude"
python3 - "$C" > "$SANDBOX/ids" <<'PY'
import os, sys, json, time, uuid
C = sys.argv[1]; old = time.time() - 10 * 86400
u = {k: str(uuid.uuid4()) for k in ("old", "new", "live", "orphan", "env")}
def mk(p, t=None, text="x"):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(text)
    q = p
    while t and q != C:  # old files sit in old folders, as in real life
        os.utime(q, (t, t)); q = os.path.dirname(q)
mk(f"{C}/projects/A/{u['old']}.jsonl", old)
mk(f"{C}/projects/A/{u['old']}/subagents/a.jsonl", old)
mk(f"{C}/projects/A/{u['new']}.jsonl")
mk(f"{C}/projects/B/{u['old']}/workflows/w.json", old)
mk(f"{C}/projects/M/memory/MEMORY.md", old)
mk(f"{C}/projects/M/{u['orphan']}/workflows/w", old)
mk(f"{C}/projects/L/{u['live']}.jsonl", old)
mk(f"{C}/sessions/{os.getppid()}.json", text=json.dumps({"pid": os.getppid(), "sessionId": u["live"]}))
mk(f"{C}/file-history/{u['old']}/f", old)
mk(f"{C}/file-history/{u['new']}/f")
mk(f"{C}/session-env/{u['env']}/.k", old)
mk(f"{C}/history.jsonl", text="".join(json.dumps({"timestamp": t * 1000, "display": d}) + "\n"
                                      for t, d in ((old, "old"), (time.time(), "new"))))
os.chmod(f"{C}/history.jsonl", 0o600)
mk(os.path.join(os.path.dirname(C), "Documents/claude-chats-archive-2026-01-01.tar.gz"))
print(" ".join(u[k] for k in ("old", "new", "live", "orphan", "env")))
PY
read -r OLD NEW LIVE ORPHAN ENV < "$SANDBOX/ids"
find "$FAKE" | sort > "$SANDBOX/before"
tune --only claude-chats --days 5 -n
find "$FAKE" | sort > "$SANDBOX/after"
check "dry run changes nothing" cmp -s "$SANDBOX/before" "$SANDBOX/after"
check "dry run reports the old chat" grep -q "deleting chats: 1" "$SANDBOX/out.txt"
tune --only claude-chats --days 5
check "old transcript deleted"            missing "$C/projects/A/$OLD.jsonl"
check "its subfolder deleted"             missing "$C/projects/A/$OLD"
check "its leftovers elsewhere deleted"   missing "$C/projects/B"
check "its file history deleted"          missing "$C/file-history/$OLD"
check "orphan leftovers deleted"          missing "$C/projects/M/$ORPHAN"
check "old session-env deleted"           missing "$C/session-env/$ENV"
check "old archive deleted"               missing "$FAKE/Documents/claude-chats-archive-2026-01-01.tar.gz"
check "memory kept"                       exists  "$C/projects/M/memory/MEMORY.md"
check "recent chat kept"                  exists  "$C/projects/A/$NEW.jsonl"
check "recent file history kept"          exists  "$C/file-history/$NEW"
check "running chat kept although old"    exists  "$C/projects/L/$LIVE.jsonl"
check "old prompt dropped from history"   test "$(grep -c '"old"' "$C/history.jsonl")" -eq 0
check "recent prompt kept in history"     grep -q '"new"' "$C/history.jsonl"
check "history keeps its permissions"     test "$(stat -f '%Lp' "$C/history.jsonl")" = 600

echo "claude-tabs"
fresh tabs
mkdir -p "$FAKE/.claude/sessions"
tab(){ # $1=status $2=hours since last activity $3=hours since launch
  # without the redirect $(tab …) would wait for sleep to close stdout
  bash -c 'exec -a claude-test sleep 300' >/dev/null 2>&1 & local pid=$!
  python3 -c '
import json, sys, time
pid, status, idle, age = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
now = time.time() * 1000
json.dump({"pid": int(pid), "kind": "interactive", "status": status,
           "updatedAt": now - idle * 3600e3, "startedAt": now - age * 3600e3},
          open(sys.argv[5] + f"/{pid}.json", "w"))' "$pid" "$1" "$2" "$3" "$FAKE/.claude/sessions"
  echo "$pid"
}
IDLE_OLD=$(tab idle 20 30); IDLE_NEW=$(tab idle 1 30); BUSY_OLD=$(tab busy 20 30)
PIDS+=("$IDLE_OLD" "$IDLE_NEW" "$BUSY_OLD")
tune --only claude-tabs -n; sleep 0.3
check "dry run closes nothing" alive "$IDLE_OLD"
tune --only claude-tabs; sleep 0.3
check "tab idle for 20 h closed"     dead  "$IDLE_OLD"
check "tab idle for 1 h kept"        alive "$IDLE_NEW"
check "working tab kept"             alive "$BUSY_OLD"
check "working tab reported"         grep -q "left alone: 1" "$SANDBOX/out.txt"
YOUNG=$(tab idle 20 2); OLDLAUNCH=$(tab idle 0 8); PIDS+=("$YOUNG" "$OLDLAUNCH")
tune --claude-stop; sleep 0.3
check "--claude-stop closes tab launched 8 h ago" dead  "$OLDLAUNCH"
check "--claude-stop keeps tab launched 2 h ago"  alive "$YOUNG"
check "--claude-stop keeps working tab"           alive "$BUSY_OLD"
tune --claude-stop 1; sleep 0.3
check "--claude-stop 1 closes tab launched 2 h ago" dead "$YOUNG"

echo "settings"
if [[ -n "${CI:-}" ]]; then
  fresh settings
  V="$FAKE/Library/Application Support/Code/User"; mkdir -p "$V"
  printf '{\n  // keep me\n  "x.url": "https://example.com"\n}\n' > "$V/settings.json"
  cp "$V/settings.json" "$SANDBOX/jsonc"
  tune --only settings
  check "settings with comments are not rewritten" cmp -s "$V/settings.json" "$SANDBOX/jsonc"
  printf '{"x.url": "https://example.com", "files.watcherExclude": {"**/mine/**": true}}\n' > "$V/settings.json"
  tune --only settings
  check "URL survives the rewrite"  grep -q '"https://example.com"' "$V/settings.json"
  check "own watcherExclude kept"   grep -q 'mine' "$V/settings.json"
  check "backup written"            exists "$V/settings.json.mac-tune.bak"
else
  echo "  skip  (touches real browser preferences; run with CI=1)"
fi

echo
if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
