#!/bin/env bash
set -x -e -o verbose

cowfs_container_is_running() {
    docker ps -q -f name=^cowfs\$ --filter status=running | grep "" > /dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

cowfs_cleanup() {
    if cowfs_container_is_running; then
        docker stop cowfs
    fi

    sudo umount $(readlink -f fs/merged)

    unset -f cowfs_preview_fs cowfs_container_is_running

    exit 0
}

cowfs_preview_fs() {
    local TREECMD='tree -I work/ -s fs'
    local FINDCMD="find $(pwd)/fs \( -type d -path '$(pwd)/fs/work' -prune \) -o \( -type f -exec du -s {} \; \)"

    which tree > /dev/null && $TREECMD || eval "$FINDCMD"
}

# Create overlay fs directories, short summary:
#  lower: the base filesystem (read-only)
#  upper: the delta filesystem stores changes to lower including whiteouts and new files etc. (read-write)
#  merged: the merged view of lower and upper (read-write, writes are handled uniquely by the FS).
#  work: a working directory for overlayfs (arcane internals :^))
mkdir -p fs/{upper,lower,work,merged}

# These are just to experiment.
touch fs/{upper/up,lower/low}
mkdir -p fs/lower/dirmovetest
head -c 5MB /dev/urandom > fs/lower/contentful

# Only mount the "frontend" merged view, lookups are uniquely handled by
# overlayfs as described here:
# https://docs.kernel.org/filesystems/overlayfs.html.
sudo mount -t overlay overlay -olowerdir=fs/lower,upperdir=fs/upper,workdir=fs/work fs/merged/

trap cowfs_cleanup SIGINT

docker run --rm -v $(pwd)/fs/merged:/cowfs --name cowfs ubuntu:jammy sh -c 'tail -f /dev/null' &

for i in 1 2 3 4 5; do cowfs_container_is_running && break || sleep 1; done

# Observe
# Note: Explicitly exclude work because it will be owned by root
# Todo: Maybe just `while cowfs_container_is_running; do` instead of this?
export -f cowfs_preview_fs cowfs_container_is_running
watch -e -n 1 --exec bash -c 'cowfs_container_is_running && cowfs_preview_fs' || kill -s SIGINT $$
