# verify-lib.sh - result reporting shared by verify.sh and the bundle checks.
#
# Sourced, never executed. Baked at /usr/local/lib/sbx/verify-lib.sh.
#
# Guarantees:
#   - one output format and one set of counters (PASS, FAIL, WARN,
#     FAILED_CHECKS) for every check, base or bundle;
#   - a child check reports through a trailer that only verify_finish prints,
#     so a child that dies before the end reports no trailer, and the parent
#     (verify_merge) can tell "ran and passed" from "never finished".
#
# A bundle's tools/<name>/verify.sh:
#
#   . /usr/local/lib/sbx/verify-lib.sh
#   ok  "<tool>: ..."   |  bad "<tool>: ..."  |  warn "..."  |  info "..."
#   verify_finish        # last line; prints the trailer and sets the exit code
#
# It runs as node, in a child process of verify.sh, after every base check.
# It should not use `set -e`: one failing probe must not hide the rest.

PASS=0
FAIL=0
WARN=0
FAILED_CHECKS=()

if [ -n "${VERIFY_FORCE_COLOR:-}" ] || { [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; }; then
  C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'
  C_C=$'\033[36m'; C_B=$'\033[1m';  C_0=$'\033[0m'
else
  C_G=""; C_R=""; C_Y=""; C_C=""; C_B=""; C_0=""
fi

# Paths bundle checks commonly assert against; the base owns them.
HOST_ONLY_LIST=/usr/local/etc/host-only-commands.txt
HOST_ONLY_CHECK=/usr/local/bin/host-only-check
HOST_ONLY_POLICY=/etc/sbx/sandbox-policy.md

section() { printf '\n%s%s== %s ==%s\n' "$C_B" "$C_C" "$1" "$C_0"; }
ok()      { printf '  %s[ PASS ]%s %s\n' "$C_G" "$C_0" "$1"; PASS=$((PASS + 1)); }
warn()    { printf '  %s[ WARN ]%s %s\n' "$C_Y" "$C_0" "$1"; WARN=$((WARN + 1)); }
bad()     { printf '  %s[ FAIL ]%s %s\n' "$C_R" "$C_0" "$1"; FAIL=$((FAIL + 1)); FAILED_CHECKS+=("$1"); }
info()    { printf '           %s\n' "$1"; }

# verify_finish - print the trailer and exit 0 if nothing failed, else 1.
verify_finish() {
  local c
  for c in ${FAILED_CHECKS+"${FAILED_CHECKS[@]}"}; do printf '__VERIFY_FAILED__ %s\n' "$c"; done
  printf '__VERIFY_COUNTS__ %d %d %d\n' "$PASS" "$FAIL" "$WARN"
  [ "$FAIL" -eq 0 ]
  exit $?
}

# verify_merge <child output> - print the child's lines and fold its counts
# and failures into ours. Returns 1, printing nothing, when there is no
# trailer: the caller decides how that fails.
verify_merge() {
  local out="$1" line p f w
  grep -q '^__VERIFY_COUNTS__ ' <<<"$out" || return 1
  printf '%s\n' "$out" | grep -v '^__VERIFY_'
  read -r _ p f w < <(grep '^__VERIFY_COUNTS__ ' <<<"$out" | tail -n 1)
  # A child can only add results, never subtract from ours.
  [[ "$p $f $w" =~ ^[0-9]+\ [0-9]+\ [0-9]+$ ]] || return 1
  PASS=$((PASS + p)); FAIL=$((FAIL + f)); WARN=$((WARN + w))
  while IFS= read -r line; do
    FAILED_CHECKS+=("${line#__VERIFY_FAILED__ }")
  done < <(grep '^__VERIFY_FAILED__ ' <<<"$out")
  return 0
}
