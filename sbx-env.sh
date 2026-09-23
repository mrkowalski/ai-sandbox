#!/bin/bash
#
# sbx-env.sh - naming rules shared by everything that launches the sandbox.
#
# Usage: sourced, never executed.
#
#   source ~/tools/sandbox/sbx-env.sh   # from .bashrc, and from sbx-acp.sh
#

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
