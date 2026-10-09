#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL
umask 077
program_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
codec="$program_dir/lib/usage-toon.awk"
die() { printf 'usage: %s\n' "$2" >&2; exit "$1"; }
need_value() { [ "$1" -ge 2 ] || die 2 'missing option value'; }
valid_limit() {
  case "$max_events" in ''|*[!0-9]*|0*) die 2 'max-events must be a positive integer' ;; esac
  [ "${#max_events}" -le 9 ] || die 2 'max-events exceeds supported integer range'
}
check_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || die 2 'log is absent or not a regular file'
  awk -v mode=check -f "$codec" "$1" || die 2 'log validation failed'
  rows=$(awk 'END { print NR-1 }' "$1")
  [ "$rows" -le "$max_events" ] || die 2 'log exceeds max-events'
}
setup_state() {
  [ -n "$repo" ] && [ -n "$state_dir" ] || die 2 'repo and state-dir are required'
  repo=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || die 2 'repo is not a worktree'
  repo=$(CDPATH= cd -- "$repo" && pwd -P)
  case "$state_dir" in /*) ;; *) die 2 'state-dir must be absolute' ;; esac
  [ ! -L "$state_dir" ] || die 2 'state-dir must not be a symlink'
  mkdir -p -- "$state_dir"
  state_dir=$(CDPATH= cd -- "$state_dir" && pwd -P)
  case "$state_dir" in /|"$repo"|"$repo"/*) die 2 'state-dir must be outside the repository' ;; esac
  if [ -e "$state_dir/repo" ]; then
    [ ! -L "$state_dir/repo" ] && [ "$(cat "$state_dir/repo")" = "$repo" ] || die 2 'state belongs to another repository'
  else
    printf '%s\n' "$repo" > "$state_dir/repo"
  fi
}
acquire_lock() {
  mkdir "$state_dir/lock" 2>/dev/null || die 4 'state is locked; inspect before retrying'
  scratch=
  trap 'if [ -n "$scratch" ]; then rm -rf -- "$scratch"; fi; rmdir "$state_dir/lock"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  scratch=$(mktemp -d "$state_dir/txn.XXXXXX")
}
read_receipt() {
  receipt=$1
  case "$receipt" in "$state_dir"/snapshots/*) ;; *) die 2 'snapshot is outside this state' ;; esac
  [ -d "$receipt" ] && [ ! -L "$receipt" ] || die 2 'snapshot is absent or redirected'
  resolved=$(CDPATH= cd -- "$receipt" && pwd -P)
  [ "$resolved" = "$receipt" ] || die 2 'snapshot path is not canonical'
  for field in base blob rules-path rules.snapshot; do
    [ -f "$receipt/$field" ] && [ ! -L "$receipt/$field" ] || die 2 'invalid snapshot receipt'
  done
  receipt_base=$(cat "$receipt/base")
  receipt_blob=$(cat "$receipt/blob")
  receipt_rules=$(cat "$receipt/rules-path")
  case "$receipt_base:$receipt_blob" in *[!0-9a-f:]*) die 2 'invalid snapshot object ID' ;; esac
  actual_base=$(git -C "$repo" rev-parse --verify "$receipt_base^{commit}" 2>/dev/null) || die 2 'snapshot commit is unavailable'
  [ "$actual_base" = "$receipt_base" ] || die 2 'snapshot needs a full commit ID'
  actual_entry=$(git -C "$repo" ls-tree "$receipt_base" -- "$receipt_rules")
  actual_blob=$(printf '%s\n' "$actual_entry" | awk '$2 == "blob" && $1 ~ /^100/ { print $3 }')
  [ "$actual_blob" = "$receipt_blob" ] && [ -n "$actual_blob" ] || die 2 'snapshot path does not match its commit'
  [ "$(git -C "$repo" hash-object --no-filters "$receipt/rules.snapshot")" = "$receipt_blob" ] || die 2 'snapshot content differs from its commit'
}
snapshot() {
  case "$rules_path" in ''|/*|..|../*|*/../*|*/..|./*|*/./*) die 2 'rules-path must stay inside repo' ;; esac
  [ -f "$repo/$rules_path" ] && [ ! -L "$repo/$rules_path" ] || die 2 'rules must be a regular tracked file'
  parent=$(CDPATH= cd -- "$(dirname -- "$repo/$rules_path")" && pwd -P)
  case "$parent/" in "$repo/"*) ;; *) die 2 'rules resolve outside repo' ;; esac
  base=$(git -C "$repo" rev-parse HEAD)
  entry=$(git -C "$repo" ls-tree "$base" -- "$rules_path")
  blob=$(printf '%s\n' "$entry" | awk '$2 == "blob" && $1 ~ /^100/ { print $3 }')
  [ -n "$blob" ] || die 2 'rules are not committed'
  git -C "$repo" cat-file blob "$blob" > "$scratch/rules.snapshot"
  cmp -s "$scratch/rules.snapshot" "$repo/$rules_path" || die 2 'rules differ from committed text'
  git -C "$repo" diff --cached --quiet -- "$rules_path" || die 2 'rules have staged edits'
  key=$(printf '%s\n%s\n' "$base" "$rules_path" | git -C "$repo" hash-object --stdin)
  mkdir -p "$state_dir/snapshots"
  target="$state_dir/snapshots/$key"
  if [ ! -e "$target" ]; then
    mkdir "$scratch/receipt"
    printf '%s\n' "$base" > "$scratch/receipt/base"
    printf '%s\n' "$blob" > "$scratch/receipt/blob"
    printf '%s\n' "$rules_path" > "$scratch/receipt/rules-path"
    mv "$scratch/rules.snapshot" "$scratch/receipt/rules.snapshot"
    mv "$scratch/receipt" "$target"
  fi
  read_receipt "$target"
  printf '%s\n' "$target"
}
operation=${1:-}
[ "$#" -gt 0 ] || die 2 'expected snapshot, record, check or publish'
shift
repo= state_dir= rules_path= file= session= batch= session_name= github_repo=
max_events=5000
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) need_value "$#"; repo=$2 ;;
    --state-dir) need_value "$#"; state_dir=$2 ;;
    --rules-path) need_value "$#"; rules_path=$2 ;;
    --file) need_value "$#"; file=$2 ;;
    --max-events) need_value "$#"; max_events=$2 ;;
    --session) need_value "$#"; session=$2 ;;
    --batch) need_value "$#"; batch=$2 ;;
    --session-name) need_value "$#"; session_name=$2 ;;
    --github-repo) need_value "$#"; github_repo=$2 ;;
    --event) break ;;
    *) die 2 'unknown option' ;;
  esac
  shift 2
done
valid_limit
case "$operation" in
  check) [ "$#" -eq 0 ] || die 2 'unexpected event'; check_file "$file" ;;
  snapshot) [ "$#" -eq 0 ] || die 2 'unexpected event'; setup_state; acquire_lock; snapshot ;;
  *) die 2 'operation is not implemented' ;;
esac
