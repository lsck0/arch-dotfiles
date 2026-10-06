# load workers and rate format for the speedtest scripts; a subdir because link.sh puts scripts/*.sh on PATH

worker_pids=()

# the exit trap runs on a stop from the overlay too
trap 'exit 143' TERM INT

# "0.0", one decimal under 10, whole numbers above
rate_format() {
  awk -v value="$1" 'BEGIN {
    if (value <= 0) print "0.0"
    else if (value < 10) printf "%.1f\n", value
    else printf "%.0f\n", value
  }'
}

workers_alive_count() {
  local pid count=0
  for pid in "${worker_pids[@]}"; do
    kill -0 "$pid" 2>/dev/null && count=$((count + 1))
  done
  echo "$count"
}

workers_stop() {
  local pid
  for pid in "${worker_pids[@]}"; do
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${worker_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  worker_pids=()
}
