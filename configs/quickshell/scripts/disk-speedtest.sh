#!/usr/bin/env bash
# disk throughput behind a dir: "disk <model>", then "read <MB/s>" and "write <MB/s>" each second, steady mean last
set -e
source "$(dirname "$(readlink -f "$0")")/lib/speedtest.sh"

if [[ -n ${1:-} && ! -d $1 ]]; then
  echo "Usage: disk-speedtest.sh [target-dir]" >&2
  exit 2
fi

target_dir="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/quickshell}"
phase_seconds=8
parallel=4
chunk_mb=4
file_mb=256

mkdir -p "$target_dir"

chunk_file=""
test_files=()

cleanup() {
  # unlink first so a SIGKILL mid-cleanup leaves no files
  rm -f ${chunk_file:+"$chunk_file"} "${test_files[@]}"
  workers_stop
  rm -f ${chunk_file:+"$chunk_file"} "${test_files[@]}"
}
trap cleanup EXIT

# mktemp: no clobbering, symlink races or overlapping runs
chunk_file=$(mktemp /dev/shm/quickshell-disk-speedtest-XXXXXX.src)
for (( i = 0; i < parallel; i++ )); do
  file=$(mktemp "$target_dir/disk-speedtest-XXXXXX.dat")
  chattr +C "$file" 2>/dev/null || true
  test_files+=("$file")
done

source_dev=$(findmnt -no SOURCE --target "$target_dir" 2>/dev/null)
# strip btrfs subvolume suffix
source_dev=${source_dev%%\[*}

if [[ $source_dev != /dev/* ]]; then
  echo "Cannot find a disk behind $target_dir" >&2
  exit 1
fi

dev=$(readlink -f "$source_dev")
dev=${dev##*/}

if [[ ! -r /sys/class/block/$dev/stat ]]; then
  echo "No I/O statistics for $dev" >&2
  exit 1
fi

available_mb=$(df --output=avail -m "$target_dir" | tail -1 | tr -d ' ')
if (( available_mb < parallel * file_mb * 2 )); then
  echo "Need at least $((parallel * file_mb * 2))MB free on $target_dir" >&2
  exit 1
fi

# walk dm-crypt/lvm and partitions up to the physical disk
disk=$dev
while slave=$(ls "/sys/class/block/$disk/slaves" 2>/dev/null | head -1); [[ -n $slave ]]; do
  disk=$slave
done
if [[ -f /sys/class/block/$disk/partition ]]; then
  parent=$(readlink -f "/sys/class/block/$disk")
  parent=${parent%/*}
  disk=${parent##*/}
fi
model=$(lsblk -dno MODEL "/dev/$disk" 2>/dev/null | sed 's/^ *//; s/ *$//')
echo "disk ${model:-$disk}"

# incompressible data
dd if=/dev/urandom of="$chunk_file" bs=${chunk_mb}M count=$((file_mb / chunk_mb)) status=none

# workers die with the main script even if cleanup loses a race
write_worker() {
  local file=$1
  while kill -0 $$ 2>/dev/null; do
    dd if="$chunk_file" of="$file" bs=${chunk_mb}M oflag=direct conv=notrunc status=none 2>/dev/null || return
  done
}

read_worker() {
  local file=$1
  while kill -0 $$ 2>/dev/null; do
    dd if="$file" of=/dev/null bs=${chunk_mb}M iflag=direct status=none 2>/dev/null || return
  done
}

device_sectors() {
  local -a stats
  read -r -a stats < "/sys/class/block/$dev/stat"
  if [[ $1 == "read" ]]; then
    echo "${stats[2]}"
  else
    echo "${stats[6]}"
  fi
}

run_phase() {
  local phase=$1
  local file before after deadline rate alive samples=0
  local baseline_sectors baseline_time end_time

  for file in "${test_files[@]}"; do
    "${phase}_worker" "$file" 2>/dev/null &
    worker_pids+=("$!")
  done

  before=$(device_sectors "$phase")
  deadline=$((SECONDS + phase_seconds))

  while (( SECONDS < deadline )) && (( $(workers_alive_count) > 0 )); do
    sleep 1
    after=$(device_sectors "$phase")
    end_time=$EPOCHREALTIME
    rate=$(awk -v before="$before" -v after="$after" 'BEGIN {
      if (after < before) print 0
      else print (after - before) * 512 / 1000000
    }')
    echo "$phase $(rate_format "$rate")"
    samples=$((samples + 1))
    # first second is warm-up
    if (( samples == 1 )); then
      baseline_sectors=$after
      baseline_time=$end_time
    fi
    before=$after
  done

  # a worker gone before the deadline means dd failed
  alive=$(workers_alive_count)
  workers_stop
  if (( alive < parallel )); then
    echo "Disk $phase test failed before finishing" >&2
    exit 1
  fi

  # final figure is the steady-state mean
  if (( samples > 1 )); then
    rate=$(awk -v before="$baseline_sectors" -v after="$after" -v start="$baseline_time" -v end="$end_time" 'BEGIN {
      secs = end - start
      if (secs <= 0 || after < before) print 0
      else print (after - before) * 512 / 1000000 / secs
    }')
    echo "$phase $(rate_format "$rate")"
  fi
}

# stage data, the read phase runs first
for file in "${test_files[@]}"; do
  dd if="$chunk_file" of="$file" bs=${chunk_mb}M oflag=direct conv=notrunc status=none 2>/dev/null &
  worker_pids+=("$!")
done

stage_failed=0
for pid in "${worker_pids[@]}"; do
  wait "$pid" || stage_failed=1
done
worker_pids=()

if (( stage_failed )) || [[ ! -s ${test_files[0]} ]]; then
  echo "Direct disk I/O is not available on $target_dir" >&2
  exit 1
fi

run_phase read
run_phase write
