set -eu
export LC_ALL=C
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/normative-usage-test.XXXXXX")
trap 'rm -rf -- "$task_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
checks=0
assert_equal() {
  [ "$1" = "$2" ] || { printf 'FAIL: expected <%s>, got <%s>\n' "$1" "$2" >&2; exit 1; }
  checks=$((checks + 1))
}
assert_file_equal() {
  cmp -s "$1" "$2" || { printf 'FAIL: files differ: %s %s\n' "$1" "$2" >&2; exit 1; }
  checks=$((checks + 1))
}
assert_status() {
  want=$1
  shift
  actual=0
  "$@" > "$task_tmp/stdout" 2> "$task_tmp/stderr" || actual=$?
  if [ "$want" != "$actual" ]; then
    cat "$task_tmp/stderr" >&2
    printf 'FAIL: expected exit %s, got %s\n' "$want" "$actual" >&2
    exit 1
  fi
  checks=$((checks + 1))
}
new_fixture_repo() {
  git init -q "$1"
  git -C "$1" config user.name 'Usage test'
  git -C "$1" config user.email 'usage@example.invalid'
  git -C "$1" config commit.gpgsign false
  printf '# Rules\n\n1. Keep read-only scope.\n' > "$1/IMPERATIVES.md"
  git -C "$1" add IMPERATIVES.md
  git -C "$1" commit -qm '(ADD) Add fixture rules'
  fixture_base=$(git -C "$1" rev-parse HEAD)
}
finish() { printf 'PASS %s: %s checks\n' "$1" "$checks"; }
