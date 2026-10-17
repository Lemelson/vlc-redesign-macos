#!/bin/zsh
# Waits until nobody has touched the Mac (keyboard/mouse) for <threshold> seconds.
# usage: wait-idle.sh [max_wait_seconds=540] [threshold_seconds=300]
#   exit 0 when idle, 1 if still in use after max wait
max=${1:-540}; need=${2:-300}; waited=0
while true; do
  t=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "$t" -ge "$need" ]; then echo "idle ${t}s"; exit 0; fi
  if [ $waited -ge $max ]; then echo "Mac in use (idle ${t}s, need ${need}s) after ${max}s"; exit 1; fi
  sleep 15; waited=$((waited+15))
done
