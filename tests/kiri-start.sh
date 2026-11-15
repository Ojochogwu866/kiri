#!/bin/sh
# Kiri Linux's kiri-start (contrib/wsl/kiri-linux), in the Alpine it runs
# on: four started at once start one daemon, and the daemon does not keep
# their lock. The daemon is a stand-in that never makes its socket, so the
# one that starts it says so (exit 1: it may still come up); one that exits
# at once is exit 2. The check's own pgrep spells it "[k]iri", so as not to
# match the script it runs in. Usage: tests/kiri-start.sh
set -u
D=${D:-docker}
DIR=$(cd "$(dirname "$0")/.." && pwd)
# The script is for the container's sh: its $ are expanded there.
# shellcheck disable=SC2016
$D run --rm -v "$DIR/contrib/wsl/kiri-linux/kiri-start:/usr/local/bin/kiri-start:ro" alpine:3.24 sh -c '
  printf "#!/bin/sh\n[ \"\$1\" = daemon ] && echo x >>/tmp/launches; sleep 30\n" >/usr/local/bin/kiri
  chmod 755 /usr/local/bin/kiri
  for n in 1 2 3 4; do { sh /usr/local/bin/kiri-start >/tmp/out$n 2>&1; echo $? >/tmp/code$n; } & done
  wait
  fail=0
  [ "$(wc -l </tmp/launches)" -eq 1 ] || { echo "FAIL: $(wc -l </tmp/launches) daemons started"; fail=1; }
  [ "$(cat /tmp/out* | grep -c "did not create its socket")" -eq 1 ] || { echo "FAIL: not one start said why"; cat /tmp/out*; fail=1; }
  [ "$(cat /tmp/code* | sort | tr "\n" " ")" = "0 0 0 1 " ] || { echo "FAIL: exit codes $(cat /tmp/code* | tr "\n" " ")"; fail=1; }
  pid=$(pgrep -f "/usr/local/bin/[k]iri daemon" | head -1)
  if [ -z "$pid" ]; then
    echo "FAIL: no daemon is running"; fail=1
  elif ls -l "/proc/$pid/fd" | grep -q kiri-start.lock; then
    echo "FAIL: the daemon keeps the lock"; fail=1
  fi
  # A daemon that exits as it starts: exit 2, at once.
  pkill -f "/usr/local/bin/[k]iri daemon"
  printf "#!/bin/sh\nexit 1\n" >/usr/local/bin/kiri
  sh /usr/local/bin/kiri-start 2>/tmp/err; code=$?
  [ $code = 2 ] && grep -q "exited as it started" /tmp/err || { echo "FAIL: a daemon that exits: exit $code, $(cat /tmp/err)"; fail=1; }
  [ $fail = 0 ] && echo "ok: one daemon for four starts; one that exits is exit 2"
  exit $fail'
