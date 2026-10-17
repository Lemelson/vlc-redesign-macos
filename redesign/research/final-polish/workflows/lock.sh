#!/bin/zsh
# Serializes native builds/installs and real-app sessions.
# usage: lock.sh acquire <who> | release | status | path
#
# The lock is a directory. Its location comes from MXR_LOCK_DIR; the default is
# the shared build directory next to the checkout, which survives session
# scratchpads being deleted. Every agent of a wave must see the same value.
L=${MXR_LOCK_DIR:-${TMPDIR:-/tmp}/vlc-redesign-locks/native.lock}
case "$1" in
  acquire)
    mkdir -p "${L:h}" || exit 1
    until mkdir "$L" 2>/dev/null; do
      # a holder that died leaves the lock behind: break it after 45 min
      # (holders refresh it with `touch "$L"` during long sessions)
      if [ -n "$(find "$L" -maxdepth 0 -mmin +45 2>/dev/null)" ]; then echo "breaking stale lock: $(cat "$L/owner" 2>/dev/null)"; rm -rf "$L"; continue; fi
      sleep 20
    done
    echo "$2 $(date)" > "$L/owner"; echo "locked by $2";;
  release) rm -rf "$L"; echo released;;
  status) if [ -d "$L" ]; then echo "held: $(cat "$L/owner" 2>/dev/null)"; else echo free; fi;;
  path) echo "$L";;
  *) echo "usage: lock.sh acquire <who> | release | status | path"; exit 64;;
esac
