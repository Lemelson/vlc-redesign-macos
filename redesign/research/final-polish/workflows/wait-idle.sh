#!/bin/zsh
# Waits until nobody has touched the Mac (keyboard/mouse) for 120 s.
# usage: wait-idle.sh [max_wait_seconds=900]  -> exit 0 when idle, 1 if still in use after max wait
max=${1:-900}; waited=0
while true; do
  t=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "$t" -ge 120 ]; then echo "idle ${t}s"; exit 0; fi
  if [ $waited -ge $max ]; then echo "Mac in use (idle ${t}s) after ${max}s"; exit 1; fi
  sleep 10; waited=$((waited+10))
done
