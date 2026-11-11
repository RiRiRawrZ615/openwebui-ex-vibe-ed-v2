#!/usr/bin/env bash
# Build the Open Web Vibes v2 RPM from the committed tree. The frontend must be built first; the
# package ships a prebuilt build/, so node is build-time only.
#
# v2 packages as openwebvibes-v2, deliberately not openwebvibes, so a machine can carry both the
# v1 gate fork and the v2 visual fork at the same time. Every path in the spec is under a v2
# name-space, so this build cannot produce a package that fights the v1 one for the same files.
set -Eeuo pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
REPO="$(dirname "$ROOT")"
VERSION="${OWV_RPM_VERSION:-1.2.0}"
RELEASE="${OWV_RPM_RELEASE:-1.rc1}"
BUILDDIR="${OWV_RPM_BUILDDIR:-$ROOT/rpmbuild}"

# OOM guard, before anything is written. A build killed mid-archive leaves a half-written tarball
# in BUILDDIR and the next build inherits it, which is how one failed build turns into a run of
# empty packages. Headroom counts free swap as well as free memory because zram is what is actually
# available on a machine that is already holding a loaded model.
MIN_FREE_MIB="${OWV_BUILD_MIN_FREE_MIB:-4096}"
SWAP_FILE="${OWV_BUILD_SWAP:-/var/tmp/owv-build-swap}"
SWAP_ADDED=0

headroom_mib() {
    free -b | awk '/^Mem:/ {a=$7} /^Swap:/ {s=$4} END {print int((a+s)/1048576)}'
}

release_swap() {
    if [ "$SWAP_ADDED" = "1" ]; then
        swapoff "$SWAP_FILE" 2>/dev/null || true
        rm -f "$SWAP_FILE" 2>/dev/null || true
        echo "[guard] temporary swap released"
    fi
}
trap release_swap EXIT

have="$(headroom_mib)"
if [ "${OWV_BUILD_NO_SWAP:-0}" != "1" ] && [ "${have:-0}" -lt "$MIN_FREE_MIB" ]; then
    need=$((MIN_FREE_MIB - have))
    echo "[guard] headroom ${have} MiB, floor ${MIN_FREE_MIB} MiB; trying ${need} MiB temporary swap"
    if command -v sudo >/dev/null 2>&1 && sudo truncate -s "${need}M" "$SWAP_FILE" 2>/dev/null \
        && sudo mkswap "$SWAP_FILE" >/dev/null 2>&1 && sudo swapon "$SWAP_FILE" 2>/dev/null; then
        SWAP_ADDED=1
        have="$(headroom_mib)"
        echo "[guard] headroom now ${have} MiB"
    else
        echo "[ERROR] headroom below the floor and no way to add swap. Stop the engine, or lower" >&2
        echo "        OWV_BUILD_MIN_FREE_MIB, or build with OWV_BUILD_NO_SWAP=1 and accept the risk." >&2
        exit 1
    fi
fi
echo "[guard] headroom ${have} MiB (floor ${MIN_FREE_MIB} MiB)"

if [ ! -d "$REPO/build" ]; then
    echo "[ERROR] no prebuilt frontend at $REPO/build. Run npm run build first." >&2
    exit 1
fi

mkdir -p "$BUILDDIR"/SPECS "$BUILDDIR"/SOURCES "$BUILDDIR"/BUILD "$BUILDDIR"/RPMS "$BUILDDIR"/BUILDROOT

# The archive must not contain itself, and no byte-compiled caches: a .pyc carried from the build
# machine is a stale copy of a source file, and python prefers the cache when the recorded mtime and
# size match, so a packaged install can run code that is not the code in the archive.
# 'tests' is not part of the v2 tree, so it is not requested; asking for a missing member is what
# made an earlier tar call fail with a usage error instead of building.
tar -C "$REPO" --exclude=.git --exclude="$BUILDDIR" --exclude=node_modules --exclude=.svelte-kit \
    --exclude=__pycache__ --transform 's#^#openwebvibes-v2/#' \
    -cf "$BUILDDIR/SOURCES/openwebvibes-v2.tar.gz" backend build packaging engine CHANGELOG.md

cp "$ROOT/openwebvibes-v2.spec" "$BUILDDIR/SPECS/openwebvibes-v2.spec"
rpmbuild -bb \
    --define "_topdir $BUILDDIR" \
    --define "_version $VERSION" \
    --define "_release $RELEASE" \
    "$BUILDDIR/SPECS/openwebvibes-v2.spec"

echo
find "$BUILDDIR/RPMS" -name '*.rpm' -type f
