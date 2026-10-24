#!/bin/bash
#
# install-tools.sh - build-time installer for the tool bundles selected by the
# TOOLS build arg. Runs only from the Dockerfile.
#
# Guarantees:
#   - only the named bundles are installed; an unknown name fails the build;
#   - a bundle bin/ script never shadows a base command (anything on the base
#     image's PATH, recorded before any bundle is installed) nor another
#     selected bundle's script or declared binary; either fails the build
#     naming the script and the bundles;
#   - each declared volume and tmpfs mount point exists and is owned by node,
#     so a fresh named volume inherits node's ownership;
#   - /usr/local/share/sbx/tools.list names exactly the installed bundles, and
#     the bundle directories of unselected tools are removed from the image.
#
# Nothing here grants anything at runtime: every runtime grant is a tool.conf
# key that the host launcher validates.
#
# Usage:
#   install-tools.sh snapshot          root, before any bundle: record base commands
#   install-tools.sh user <tool>...    node: each bundle's install.sh
#   install-tools.sh root <tool>...    root: install-root.sh, bin/, mount points, tools.list

set -euo pipefail

SBX=/usr/local/share/sbx
TOOLS_DIR="$SBX/tools"
BIN_DIR="$SBX/bin"
BASE_COMMANDS="$SBX/base-commands.txt"

die() { printf 'install-tools: %s\n' "$*" >&2; exit 1; }

# conf_values <tool.conf> <key> - every value of <key>, one per line. The host
# launcher has already validated the file; this only reads it.
conf_values() {
  local file="$1" want="$2" line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%[[:space:]]#*}"
    [[ "$line" =~ ^[[:space:]]*([a-z][a-z-]*)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
    key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
    [ "$key" = "$want" ] && printf '%s\n' "$value"
  done < "$file"
  return 0
}

check_tools() {
  local t
  for t in "$@"; do
    [[ "$t" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid tool name: '$t'"
    [ -f "$TOOLS_DIR/$t/tool.conf" ] || die "unknown tool '$t' (no $TOOLS_DIR/$t/tool.conf)"
  done
}

mode="${1:-}"
[ "$#" -gt 0 ] && shift

case "$mode" in
  snapshot)
    mkdir -p "$SBX" "$BIN_DIR"
    # Every name on the base PATH. The bundle bin dir is first on PATH but
    # still empty here, so it contributes nothing.
    IFS=: read -r -a dirs <<<"$PATH"
    for d in "${dirs[@]}"; do
      [ -d "$d" ] && find "$d" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n'
    done | sort -u > "$BASE_COMMANDS"
    ;;

  user)
    check_tools "$@"
    for t in "$@"; do
      [ -f "$TOOLS_DIR/$t/install.sh" ] || die "$t: bundle has no install.sh"
      printf 'install-tools: %s: install.sh\n' "$t"
      ( cd "$TOOLS_DIR/$t" && bash ./install.sh )
    done
    ;;

  root)
    check_tools "$@"
    [ -r "$BASE_COMMANDS" ] || die "no base command snapshot ($BASE_COMMANDS)"

    # name -> owning bundle, for scripts and for declared binaries.
    declare -A SCRIPT_OWNER=() BIN_OWNER=()
    for t in "$@"; do
      while IFS= read -r b; do BIN_OWNER["$b"]="$t"; done < <(conf_values "$TOOLS_DIR/$t/tool.conf" bin)
    done

    for t in "$@"; do
      dir="$TOOLS_DIR/$t"

      if [ -f "$dir/install-root.sh" ]; then
        printf 'install-tools: %s: install-root.sh\n' "$t"
        ( cd "$dir" && bash ./install-root.sh )
      fi

      if [ -d "$dir/bin" ]; then
        for f in "$dir/bin"/*; do
          [ -f "$f" ] || continue
          name="${f##*/}"
          own=$(conf_values "$dir/tool.conf" bin | grep -Fxq -- "$name" && echo 1 || echo 0)
          if [ -n "${SCRIPT_OWNER[$name]:-}" ]; then
            die "bin/$name is shipped by both '${SCRIPT_OWNER[$name]}' and '$t'"
          fi
          if [ -n "${BIN_OWNER[$name]:-}" ] && [ "${BIN_OWNER[$name]}" != "$t" ]; then
            die "bin/$name in '$t' shadows a binary of bundle '${BIN_OWNER[$name]}'"
          fi
          if [ "$own" -eq 0 ] && grep -Fxq -- "$name" "$BASE_COMMANDS"; then
            die "bin/$name in '$t' shadows the base command '$name'"
          fi
          SCRIPT_OWNER["$name"]="$t"
          install -m 0755 "$f" "$BIN_DIR/$name"
        done
      fi

      while IFS= read -r v; do
        install -d -o node -g node "${v#*:}"
      done < <(conf_values "$dir/tool.conf" volume)
      while IFS= read -r p; do
        install -d -o node -g node "$p"
      done < <(conf_values "$dir/tool.conf" tmpfs)
    done

    printf '%s\n' "$@" | grep -v '^$' > "$SBX/tools.list" || : > "$SBX/tools.list"

    # Unselected bundles leave nothing behind, shell.sh included.
    for d in "$TOOLS_DIR"/*/; do
      t="${d%/}"; t="${t##*/}"
      grep -Fxq -- "$t" "$SBX/tools.list" || rm -rf "$d"
    done

    chmod -R a+rX,go-w "$SBX"
    ;;

  *)
    die "usage: install-tools.sh snapshot | user <tool>... | root <tool>..."
    ;;
esac
