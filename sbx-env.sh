#!/bin/bash
#
# sbx-env.sh - naming rules, config resolution, and the approval gate shared by
# everything that launches the sandbox (bin/sbx, sbx-acp.sh).
#
# Usage: sourced, never executed.
#
#   . "$SBX_ROOT/sbx-env.sh"
#
# Guarantees:
#   - .devcontainer/sbx-defaults.conf, a project's .sbx/config, and each
#     bundle's tool.conf and allowed-domains.txt are read as `key = value`
#     data: nothing in them is sourced, eval'd, or executed;
#   - an unknown key, a malformed line, an unknown tool, or a value that fails
#     validation aborts resolution with a message naming the file and line;
#   - a project config that is new or changed since it was last approved takes
#     effect only after interactive confirmation, and never without a terminal.
#
# Config keys: tools, allow, deny, host-network, mount. Only settings that
# widen the sandbox are configurable; there is no key for a restriction.

SBX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SBX_DEVCONTAINER="$SBX_ROOT/.devcontainer"
SBX_DEFAULTS="$SBX_DEVCONTAINER/sbx-defaults.conf"
SBX_TOOLS_DIR="$SBX_DEVCONTAINER/tools"

# sbx_slug [path] - the volume/image name component for a workspace path,
# defaulting to $PWD.
#
# Strips the leading '/', lowercases, and maps every byte outside
# [a-z0-9_.-] to '-'. Lowercasing is not cosmetic: Docker image repository
# names must be lowercase, and one slug has to serve both the volumes and the
# image tag for them to sort together. LC_ALL=C makes the mapping bytewise, so
# a path with non-ASCII characters yields the same slug here and inside the
# container rather than depending on each side's locale.
#
# Trailing slashes are stripped first. $PWD never carries one, but a caller
# passing "$HOME/project/" would otherwise get a slug one '-' different from
# the same project launched without it - two volume sets for one workspace.
sbx_slug() {
    local path
    if [ "$#" -gt 0 ]; then path="$1"; else path="$PWD"; fi

    # An empty path would produce an empty slug, and an empty slug is the
    # failure this whole file exists to prevent. Fail loudly instead.
    if [ -z "$path" ]; then
        printf 'sbx_slug: empty workspace path - refusing to produce an unscoped name\n' >&2
        return 1
    fi

    while [ "${path%/}" != "$path" ]; do path="${path%/}"; done
    path="${path#/}"

    if [ -z "$path" ]; then
        printf 'sbx_slug: workspace path is the filesystem root - refusing to produce an empty name\n' >&2
        return 1
    fi

    printf '%s' "$path" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9_.-' '-'
}

# sbx_tag_image [path] - tag the running container's image `sbx-<slug>:latest`.
#
# `devcontainer up` has no --image-name, so the tag is applied after the fact:
# find the container the CLI just created for this workspace by the label it
# stamps on it, read its image, and move the tag onto it. Re-tagging on each
# launch moves the tag rather than adding one, so a project keeps exactly one.
sbx_tag_image() {
    local path slug cid img tag
    if [ "$#" -gt 0 ]; then path="$1"; else path="$PWD"; fi

    slug=$(sbx_slug "$path") || return 0
    tag="sbx-${slug}:latest"

    cid=$(docker ps --quiet --filter "label=devcontainer.local_folder=${path}" 2>/dev/null | head -n 1)
    if [ -z "$cid" ]; then
        printf 'sbx: no running container labelled for %s - image not tagged %s\n' "$path" "$tag" >&2
        return 0
    fi

    img=$(docker inspect --format '{{.Image}}' "$cid" 2>/dev/null)
    if [ -z "$img" ]; then
        printf 'sbx: could not read the image of container %s - image not tagged %s\n' "$cid" "$tag" >&2
        return 0
    fi

    if docker tag "$img" "$tag" 2>/dev/null; then
        printf 'sbx: tagged %s -> %s\n' "${img#sha256:}" "$tag" >&2
    else
        printf 'sbx: could not tag %s as %s\n' "${img#sha256:}" "$tag" >&2
    fi
    return 0
}

# sbx_state_dir <slug> - host state for one project: approval, policy, config.
sbx_state_root() { printf '%s/.local/state/sbx' "$HOME"; }
sbx_state_dir() { printf '%s/%s' "$(sbx_state_root)" "$1"; }

# ----------------------------------------------------------------- parse ----

_SBX_ERRORS=0
_sbx_err() {
    printf 'sbx: %s:%s: %s\n' "$1" "$2" "$3" >&2
    _SBX_ERRORS=$((_SBX_ERRORS + 1))
}

# _sbx_parse <file> <allowed key>... - fill P_LINE/P_KEY/P_VAL with the file's
# entries. `#` starts a comment at the start of a line or after whitespace.
_sbx_parse() {
    local file="$1"; shift
    local allowed=" $* " raw line n=0 key value
    P_LINE=() P_KEY=() P_VAL=()

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        _sbx_err "$file" 0 "cannot read file"
        return 0
    fi

    while IFS= read -r raw || [ -n "$raw" ]; do
        n=$((n + 1))
        line="${raw%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        line="${line%%[[:space:]]#*}"

        if [[ "${line//$'\t'/ }" =~ [[:cntrl:]] ]]; then
            _sbx_err "$file" "$n" "control character in line"
            continue
        fi
        if ! [[ "$line" =~ ^[[:space:]]*([a-z][a-z-]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            _sbx_err "$file" "$n" "not a 'key = value' line"
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ "$allowed" != *" $key "* ]]; then
            _sbx_err "$file" "$n" "unknown key '$key' (allowed:${allowed% })"
            continue
        fi
        P_LINE+=("$n") P_KEY+=("$key") P_VAL+=("$value")
    done < "$file"
    return 0
}

# --------------------------------------------------------------- validate ----

_sbx_ip2int() {
    local IFS=. a b c d
    read -r a b c d <<<"$1"
    printf '%d' $(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d ))
}

# Ranges a whitelist entry may not touch. The Docker host is reached through
# `host-network` only; everything else here is never a provider.
_SBX_FORBIDDEN=(
    "0.0.0.0/8 reserved"
    "10.0.0.0/8 private"
    "100.64.0.0/10 shared-address (CGNAT)"
    "127.0.0.0/8 loopback"
    "169.254.0.0/16 link-local"
    "172.16.0.0/12 private"
    "192.168.0.0/16 private"
    "224.0.0.0/4 multicast"
    "240.0.0.0/4 reserved"
)

# _sbx_check_entry <entry> - 0 if <entry> is a valid hostname or public IPv4
# address / range no wider than /16; otherwise 1 with the reason in _SBX_WHY.
_sbx_check_entry() {
    local e="$1" o prefix ip mask f fnet fbits fmask
    _SBX_WHY=""

    if [[ "$e" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(/([0-9]{1,2}))?$ ]]; then
        # Captured before the loop: its own =~ resets BASH_REMATCH.
        local -a octets=("${BASH_REMATCH[@]:1:4}")
        prefix="${BASH_REMATCH[6]:-32}"
        for o in "${octets[@]}"; do
            if [[ "$o" =~ ^0[0-9] ]] || [ "$((10#$o))" -gt 255 ]; then
                _SBX_WHY="invalid IPv4 address '$e'"; return 1
            fi
        done
        if [ "$((10#$prefix))" -lt 16 ] || [ "$((10#$prefix))" -gt 32 ]; then
            _SBX_WHY="IPv4 range '$e' is wider than the /16 limit"; return 1
        fi
        prefix=$((10#$prefix))
        ip=$(_sbx_ip2int "${e%/*}")
        mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
        if [ $(( ip & ~mask & 0xFFFFFFFF )) -ne 0 ]; then
            _SBX_WHY="IPv4 range '$e' has host bits set; give the network address"; return 1
        fi
        # Every forbidden range is /16 or wider and the entry is /16 or
        # narrower, so they overlap exactly when the entry's network address
        # falls inside the forbidden range.
        for f in "${_SBX_FORBIDDEN[@]}"; do
            fnet="${f%% *}"
            fbits="${fnet#*/}"
            fmask=$(( (0xFFFFFFFF << (32 - fbits)) & 0xFFFFFFFF ))
            if [ $(( ip & fmask )) -eq "$(_sbx_ip2int "${fnet%/*}")" ]; then
                _SBX_WHY="'$e' is in the ${f#* } range $fnet; reach the Docker host with 'host-network = on'"
                return 1
            fi
        done
        return 0
    fi

    if [ "${#e}" -le 253 ] &&
       [[ "$e" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] &&
       ! [[ "$e" =~ \.[0-9]+$ ]]; then
        return 0
    fi
    _SBX_WHY="invalid hostname '$e'"
    return 1
}

# sbx_in <needle> <item>... - <needle> is one of the items. A loop, not
# `printf | grep -q`: under pipefail an early-exiting grep can SIGPIPE printf
# and turn a match into a failure.
sbx_in() {
    local needle="$1" x; shift
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}

# _sbx_under <path> <dir> - <path> is <dir> or inside it (both resolved).
_sbx_under() { [ "$1" = "$2" ] || [[ "$1" == "$2"/* ]]; }

# Container paths a host mount may not cover, contain, or sit inside: the
# image's own machinery and the mounts the sandbox's guarantees rest on.
_SBX_SYSTEM_PATHS=(/bin /boot /commandhistory /dev /etc /home/node /lib /lib32
                   /lib64 /libx32 /proc /root /run /sbin /sys /tmp /usr /var /workspace)

# _sbx_check_mount <value> <workspace> - sets _SBX_MOUNT ("<resolved>|ro|rw")
# or returns 1 with the reason in _SBX_WHY.
_sbx_check_mount() {
    local v="$1" ws="$2" path mode real wsr p prot
    _SBX_WHY="" _SBX_MOUNT=""

    if [[ "$v" == *:rw ]]; then path="${v%:rw}" mode=rw; else path="$v" mode=ro; fi

    if [[ "$path" != /* ]]; then
        _SBX_WHY="mount path '$path' is not absolute"; return 1
    fi
    # These break, or are interpreted inside, the devcontainer mount string.
    if [[ "$path" == *[,\$\"\'\\=]* ]]; then
        _SBX_WHY="mount path '$path' contains one of: , \$ \" ' \\ ="; return 1
    fi
    if ! real=$(realpath -e -- "$path" 2>/dev/null); then
        _SBX_WHY="mount path '$path' does not exist"; return 1
    fi
    if [ "$real" = "/" ]; then
        _SBX_WHY="mount path '$path' is the root folder"; return 1
    fi

    for p in "${_SBX_SYSTEM_PATHS[@]}"; do
        if _sbx_under "$real" "$p" || _sbx_under "$p" "$real"; then
            _SBX_WHY="mount path '$path' ($real) would cover $p inside the container"; return 1
        fi
    done

    wsr=$(realpath -e -- "$ws")
    if _sbx_under "$wsr" "$real"; then
        _SBX_WHY="mount path '$path' ($real) contains the workspace and would cover its read-only .git and .sbx"
        return 1
    fi
    for p in "$wsr/.git" "$wsr/.sbx"; do
        p=$(realpath -m -- "$p")
        if _sbx_under "$real" "$p"; then
            _SBX_WHY="mount path '$path' ($real) is inside the workspace's $(basename "$p")"; return 1
        fi
    done

    if [ "$mode" = rw ]; then
        for prot in "$SBX_ROOT" "$(realpath -m -- "$(sbx_state_root)")"; do
            if _sbx_under "$real" "$prot" || _sbx_under "$prot" "$real"; then
                _SBX_WHY="read-write mount '$path' ($real) would expose the protected path $prot"; return 1
            fi
        done
    fi

    _SBX_MOUNT="$real|$mode"
    return 0
}

# ------------------------------------------------------------------ tools ----

sbx_available_tools() {
    local d
    for d in "$SBX_TOOLS_DIR"/*/; do
        [ -f "$d/tool.conf" ] || continue
        d="${d%/}"; printf '%s\n' "${d##*/}"
    done
}

_sbx_reset_tools() {
    declare -gA SBX_TOOL_TYPE=() SBX_TOOL_ACP=() SBX_TOOL_BINS=() SBX_TOOL_PROBE=()
    SBX_TOOL_VOLUMES=() SBX_TOOL_TMPFS=() SBX_TOOL_ENV=() SBX_TOOL_DOMAINS=()
}

# _sbx_load_tool <name> - parse and validate one bundle's tool.conf and
# allowed-domains.txt into the SBX_TOOL_* globals.
_sbx_load_tool() {
    local t="$1" dir="$SBX_TOOLS_DIR/$1" conf="$SBX_TOOLS_DIR/$1/tool.conf"
    local i n key v kinds=" " words acp_line=0 first
    local bins=" "

    _sbx_parse "$conf" type bin acp volume tmpfs env probe
    for i in "${!P_KEY[@]}"; do
        n="${P_LINE[$i]}" key="${P_KEY[$i]}" v="${P_VAL[$i]}"
        case "$key" in
            type)
                if [ -n "${SBX_TOOL_TYPE[$t]:-}" ]; then _sbx_err "$conf" "$n" "type given twice"
                elif [ "$v" != agent ] && [ "$v" != tool ]; then _sbx_err "$conf" "$n" "type must be 'agent' or 'tool'"
                else SBX_TOOL_TYPE[$t]="$v"; fi ;;
            bin)
                if [[ "$v" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then bins+="$v "
                else _sbx_err "$conf" "$n" "invalid bin name '$v'"; fi ;;
            acp)
                if [ "$acp_line" -ne 0 ]; then _sbx_err "$conf" "$n" "acp given twice"; continue; fi
                acp_line="$n"
                read -r -a words <<<"$v"
                if [ "${#words[@]}" -eq 0 ]; then _sbx_err "$conf" "$n" "acp is empty"; continue; fi
                for first in "${words[@]}"; do
                    if ! [[ "$first" =~ ^[A-Za-z0-9._+=:/@,-]+$ ]]; then
                        _sbx_err "$conf" "$n" "acp word '$first' has characters outside [A-Za-z0-9._+=:/@,-]"
                    fi
                done
                SBX_TOOL_ACP[$t]="$v" ;;
            volume)
                if ! [[ "$v" =~ ^([a-z0-9]+):(/home/node/[A-Za-z0-9._/-]+)$ ]] || [[ "$v" == *..* ]]; then
                    _sbx_err "$conf" "$n" "volume must be <kind>:/home/node/<path>"
                elif [[ "$kinds" == *" ${v%%:*} "* ]]; then
                    _sbx_err "$conf" "$n" "volume kind '${v%%:*}' given twice"
                else
                    kinds+="${v%%:*} "
                    SBX_TOOL_VOLUMES+=("$t|${v%%:*}|${v#*:}")
                fi ;;
            tmpfs)
                if ! [[ "$v" =~ ^/home/node/[A-Za-z0-9._/-]+$ ]] || [[ "$v" == *..* ]]; then
                    _sbx_err "$conf" "$n" "tmpfs must be /home/node/<path>"
                else SBX_TOOL_TMPFS+=("$t|$v"); fi ;;
            env)
                if ! [[ "$v" =~ ^[A-Z_][A-Z0-9_]*= ]]; then _sbx_err "$conf" "$n" "env must be KEY=VALUE"
                elif [[ "${v%%=*}" =~ ^(PATH|SBX_.*|LD_.*)$ ]]; then _sbx_err "$conf" "$n" "env may not set ${v%%=*}"
                elif [[ "${v#*=}" == *'$'* ]]; then _sbx_err "$conf" "$n" "env value may not contain '\$'"
                else SBX_TOOL_ENV+=("$v"); fi ;;
            probe)
                if [ -n "${SBX_TOOL_PROBE[$t]:-}" ]; then _sbx_err "$conf" "$n" "probe given twice"
                elif ! [[ "$v" =~ ^https://[a-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/?=\&%-]*)?$ ]]; then _sbx_err "$conf" "$n" "probe must be an https:// URL"
                else SBX_TOOL_PROBE[$t]="$v"; fi ;;
        esac
    done

    SBX_TOOL_BINS[$t]="$(printf '%s' "$bins" | sed 's/^ //; s/ $//')"
    if [ -z "${SBX_TOOL_TYPE[$t]:-}" ]; then
        _sbx_err "$conf" 0 "no 'type = agent | tool'"
    elif [ "${SBX_TOOL_TYPE[$t]}" = agent ] && [ -z "${SBX_TOOL_ACP[$t]:-}" ]; then
        _sbx_err "$conf" 0 "tool '$t' is an agent and declares no 'acp' command"
    fi
    if [ -n "${SBX_TOOL_ACP[$t]:-}" ]; then
        first="${SBX_TOOL_ACP[$t]%% *}"
        if [[ "$bins" != *" $first "* ]]; then
            _sbx_err "$conf" "$acp_line" "acp command '$first' is not one of the 'bin' entries"
        fi
    fi

    if [ -e "$dir/allowed-domains.txt" ]; then
        n=0
        while IFS= read -r v || [ -n "$v" ]; do
            n=$((n + 1))
            v="${v%$'\r'}"
            [[ "$v" =~ ^[[:space:]]*(#|$) ]] && continue
            v="${v%%[[:space:]]#*}"
            v="${v#"${v%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"
            if _sbx_check_entry "$v"; then
                SBX_TOOL_DOMAINS+=("$t|$v")
            else
                _sbx_err "$dir/allowed-domains.txt" "$n" "$_SBX_WHY"
            fi
        done < "$dir/allowed-domains.txt"
    fi
}

# ---------------------------------------------------------------- resolve ----

# sbx_resolve [--defaults-only] <workspace> - resolve the effective config.
#
# Sets:
#   SBX_TOOLS           enabled tools, sorted
#   SBX_WHITELIST       effective whitelist entries, in order, unique
#   SBX_HOST_NETWORK    0 or 1
#   SBX_MOUNTS          "<resolved path>|ro" or "<resolved path>|rw"
#   SBX_PROJECT_CONFIG  the project config file, or empty when there is none
#   SBX_TOOL_*          per-tool declarations of the enabled tools
#
# Returns 1 after printing every error, each naming its file and line.
sbx_resolve() {
    local defaults_only=0 ws file i n key v t tools_seen hn_seen
    local -a files=() avail=() req_tools=() allow=() deny=() deny_origin=() mounts=()
    local tools_value="" tools_origin="" hn_value=""

    if [ "${1:-}" = "--defaults-only" ]; then defaults_only=1; shift; fi
    ws="$1"
    _SBX_ERRORS=0
    SBX_TOOLS=() SBX_WHITELIST=() SBX_HOST_NETWORK=0 SBX_MOUNTS=() SBX_PROJECT_CONFIG=""
    _sbx_reset_tools

    mapfile -t avail < <(sbx_available_tools)

    files=("$SBX_DEFAULTS")
    if [ "$defaults_only" -eq 0 ] && [ -e "$ws/.sbx/config" ]; then
        SBX_PROJECT_CONFIG="$ws/.sbx/config"
        files+=("$SBX_PROJECT_CONFIG")
    fi

    for file in "${files[@]}"; do
        _sbx_parse "$file" tools allow deny host-network mount
        tools_seen=0 hn_seen=0
        for i in "${!P_KEY[@]}"; do
            n="${P_LINE[$i]}" key="${P_KEY[$i]}" v="${P_VAL[$i]}"
            case "$key" in
                tools)
                    if [ "$tools_seen" -eq 1 ]; then _sbx_err "$file" "$n" "tools given twice"; continue; fi
                    tools_seen=1 tools_value="$v" tools_origin="$file:$n" ;;
                allow|deny)
                    if ! _sbx_check_entry "$v"; then _sbx_err "$file" "$n" "$_SBX_WHY"; continue; fi
                    if [ "$key" = allow ]; then allow+=("$v"); else deny+=("$v") deny_origin+=("$file:$n"); fi ;;
                host-network)
                    if [ "$hn_seen" -eq 1 ]; then _sbx_err "$file" "$n" "host-network given twice"; continue; fi
                    hn_seen=1
                    if [ "$v" != on ] && [ "$v" != off ]; then _sbx_err "$file" "$n" "host-network must be 'on' or 'off'"
                    else hn_value="$v"; fi ;;
                mount)
                    if _sbx_check_mount "$v" "$ws"; then mounts+=("$_SBX_MOUNT")
                    else _sbx_err "$file" "$n" "$_SBX_WHY"; fi ;;
            esac
        done
    done

    # tools: the last file that sets it wins (the project replaces the default).
    read -r -a req_tools <<<"$tools_value"
    for t in "${req_tools[@]}"; do
        if ! [[ "$t" =~ ^[a-z0-9][a-z0-9-]*$ ]] || ! sbx_in "$t" "${avail[@]}"; then
            _sbx_err "${tools_origin%:*}" "${tools_origin##*:}" \
                "unknown tool '$t' (available: $(printf '%s ' "${avail[@]}" | sed 's/ $//'))"
        fi
    done
    mapfile -t SBX_TOOLS < <(printf '%s\n' "${req_tools[@]}" | grep -v '^$' | sort -u)

    if [ "$hn_value" = on ]; then SBX_HOST_NETWORK=1; fi

    if [ "$_SBX_ERRORS" -eq 0 ]; then
        for t in "${SBX_TOOLS[@]}"; do _sbx_load_tool "$t"; done
    fi

    # Whitelist: defaults and project allows plus the tools' entries, minus
    # denies. A deny may not remove what an enabled tool requires.
    local -a wl=()
    local entry d
    for entry in "${allow[@]}"; do wl+=("$entry"); done
    for entry in "${SBX_TOOL_DOMAINS[@]}"; do wl+=("${entry#*|}"); done
    for i in "${!deny[@]}"; do
        d="${deny[$i]}"
        for entry in "${SBX_TOOL_DOMAINS[@]}"; do
            if [ "${entry#*|}" = "$d" ]; then
                _sbx_err "${deny_origin[$i]%:*}" "${deny_origin[$i]##*:}" \
                    "cannot deny '$d': enabled tool '${entry%%|*}' requires it"
            fi
        done
    done
    for entry in "${wl[@]}"; do
        sbx_in "$entry" "${deny[@]}" && continue
        sbx_in "$entry" "${SBX_WHITELIST[@]}" && continue
        SBX_WHITELIST+=("$entry")
    done
    if [ "$_SBX_ERRORS" -eq 0 ] && [ "${#SBX_WHITELIST[@]}" -eq 0 ]; then
        _sbx_err "${files[-1]}" 0 "the effective whitelist is empty; firewall setup would abort"
    fi

    # Two declarations of one container path cannot both be honoured.
    local -a paths=()
    for entry in "${SBX_TOOL_VOLUMES[@]}"; do paths+=("${entry##*|}"); done
    for entry in "${SBX_TOOL_TMPFS[@]}"; do paths+=("${entry#*|}"); done
    for entry in "${mounts[@]}"; do paths+=("${entry%|*}"); done
    d=$(printf '%s\n' "${paths[@]}" | sort | uniq -d | grep -v '^$' | head -n 1 || true)
    if [ -n "$d" ]; then
        _sbx_err "${files[-1]}" 0 "container path $d is declared more than once (tool volume, tmpfs, or mount)"
    fi
    SBX_MOUNTS=("${mounts[@]}")

    [ "$_SBX_ERRORS" -eq 0 ]
}

# sbx_dump - the resolved config, one fact per line (tests, hashing).
sbx_dump() {
    local x
    printf 'tools: %s\n' "${SBX_TOOLS[*]}"
    printf 'host-network: %s\n' "$SBX_HOST_NETWORK"
    for x in "${SBX_WHITELIST[@]}"; do printf 'allow: %s\n' "$x"; done
    for x in "${SBX_MOUNTS[@]}"; do printf 'mount: %s\n' "$x"; done
    for x in "${SBX_TOOL_VOLUMES[@]}"; do printf 'volume: %s\n' "$x"; done
    for x in "${SBX_TOOL_TMPFS[@]}"; do printf 'tmpfs: %s\n' "$x"; done
    for x in "${SBX_TOOL_ENV[@]}"; do printf 'env: %s\n' "$x"; done
    for x in "${SBX_TOOLS[@]}"; do
        [ -n "${SBX_TOOL_ACP[$x]:-}" ] && printf 'acp: %s|%s\n' "$x" "${SBX_TOOL_ACP[$x]}"
    done
    return 0
}

# --------------------------------------------------------------- approval ----

# sbx_approve <workspace> - the approval gate. Call after a successful
# sbx_resolve of <workspace>; leaves that resolution in place.
#
# Returns 0 when there is no project config or its current content was
# approved before (or is approved now), 1 otherwise. Without a terminal on
# stdin and stderr it never prompts: piped input cannot approve a config.
sbx_approve() {
    local ws="$1" cfg="$1/.sbx/config" slug state hash ans x
    local -a def_tools def_wl def_mounts cur_tools cur_wl cur_mounts
    local def_hn cur_hn

    [ -e "$cfg" ] || return 0
    slug=$(sbx_slug "$ws") || return 1
    state=$(sbx_state_dir "$slug")
    hash=$(sha256sum < "$cfg" | cut -d' ' -f1)

    if [ -r "$state/approved" ] && [ "$(cat "$state/approved")" = "$hash" ]; then
        return 0
    fi

    cur_tools=("${SBX_TOOLS[@]}") cur_wl=("${SBX_WHITELIST[@]}")
    cur_mounts=("${SBX_MOUNTS[@]}") cur_hn="$SBX_HOST_NETWORK"
    if ! sbx_resolve --defaults-only "$ws"; then
        printf 'sbx: the defaults do not resolve on their own\n' >&2
        return 1
    fi
    def_tools=("${SBX_TOOLS[@]}") def_wl=("${SBX_WHITELIST[@]}") def_hn="$SBX_HOST_NETWORK"
    sbx_resolve "$ws" || return 1

    {
        printf '\nsbx: %s is new or changed since it was last approved.\n' "$cfg"
        printf 'It changes this project'"'"'s sandbox relative to the defaults:\n\n'
        if [ "${cur_tools[*]}" != "${def_tools[*]}" ]; then
            printf '  tools:         %s   (defaults: %s)\n' "${cur_tools[*]:-none}" "${def_tools[*]:-none}"
        fi
        for x in "${cur_wl[@]}"; do
            sbx_in "$x" "${def_wl[@]}" || printf '  + egress:      %s\n' "$x"
        done
        for x in "${def_wl[@]}"; do
            sbx_in "$x" "${cur_wl[@]}" || printf '  - egress:      %s\n' "$x"
        done
        if [ "$cur_hn" != "$def_hn" ]; then
            printf '  host-network:  %s   (defaults: %s)\n' \
                "$([ "$cur_hn" = 1 ] && echo on || echo off)" "$([ "$def_hn" = 1 ] && echo on || echo off)"
        fi
        for x in "${cur_mounts[@]}"; do
            printf '  + mount:       %s (%s)\n' "${x%|*}" \
                "$([ "${x##*|}" = rw ] && echo READ-WRITE || echo read-only)"
        done
        if [ "${cur_tools[*]}" = "${def_tools[*]}" ] && [ "$cur_hn" = "$def_hn" ] &&
           [ "${cur_wl[*]}" = "${def_wl[*]}" ] && [ "${#cur_mounts[@]}" -eq 0 ]; then
            printf '  (nothing: it resolves to the defaults)\n'
        fi
        printf '\n'
    } >&2

    if ! [ -t 0 ] || ! [ -t 2 ]; then
        printf 'sbx: refusing to apply an unapproved config without a terminal.\n' >&2
        printf 'sbx: run `sbx --up` once in %s from a terminal to review and approve it.\n' "$ws" >&2
        return 1
    fi

    read -r -p "Apply this config? [y/N] " ans || ans=""
    case "$ans" in
        y|Y|yes|YES) ;;
        *) printf 'sbx: not approved; nothing was started.\n' >&2; return 1 ;;
    esac

    # The prompt showed the content hashed above; refuse if it moved since.
    if [ "$(sha256sum < "$cfg" | cut -d' ' -f1)" != "$hash" ]; then
        printf 'sbx: %s changed while waiting for approval; run sbx again.\n' "$cfg" >&2
        return 1
    fi
    mkdir -p -m 700 "$state"
    printf '%s\n' "$hash" > "$state/approved"
    printf 'sbx: approved.\n' >&2
    return 0
}
