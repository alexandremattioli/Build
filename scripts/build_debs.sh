#!/bin/bash
################################################################################
# Script: build_debs.sh
# Purpose: Build DEB packages for Apache CloudStack from a working tree
# Default: Always build DEBs after a successful Maven build
# Usage: ./build_debs.sh [--repo <cloudstack_dir>] [--out <output_dir>] [--no-equivs]
#
# Notes:
# - For Ubuntu 22.04/24.04. On 24.04, legacy build-dep 'python-setuptools' is unavailable.
#   This script uses 'equivs' to install a dummy package that Provides: python-setuptools
#   so dpkg-checkbuilddeps can pass.
# - Prefers packaging/build-deb.sh. Falls back to dpkg-buildpackage -d if necessary.
################################################################################

set -euo pipefail

REPO_DIR="/root/cloudstack"
OUT_DIR=""
USE_EQUIVS=1

while [[ ${1:-} =~ ^- ]]; do
  case "$1" in
    --repo)
      REPO_DIR="$2"; shift 2 ;;
    --out)
      OUT_DIR="$2"; shift 2 ;;
    --no-equivs)
      USE_EQUIVS=0; shift 1 ;;
    -h|--help)
      echo "Usage: $0 [--repo <cloudstack_dir>] [--out <output_dir>] [--no-equivs]"; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: Repo directory not found: $REPO_DIR" >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  OUT_DIR="/root/artifacts/$(hostname)/debs/$TS"
fi

echo "[build_debs] Repo: $REPO_DIR"
echo "[build_debs] Output: $OUT_DIR"

mkdir -p "$OUT_DIR"

ensure_deps() {
  echo "[build_debs] Ensuring packaging dependencies..."
  apt-get update -y >/dev/null 2>&1 || true
  DEPS=(dpkg-dev debhelper devscripts lsb-release fakeroot genisoimage python3 python3-setuptools python-is-python3)
  OPT=(build-essential libssl-dev libffi-dev)
  apt-get install -y "${DEPS[@]}" "${OPT[@]}" >/dev/null 2>&1 || true

  if [[ $USE_EQUIVS -eq 1 ]]; then
    if ! dpkg -s python-setuptools >/dev/null 2>&1; then
      echo "[build_debs] Installing equivs and creating dummy python-setuptools..."
      apt-get install -y equivs >/dev/null 2>&1 || true
      TMPDIR=$(mktemp -d)
      pushd "$TMPDIR" >/dev/null
      equivs-control python-setuptools
      sed -i 's/^Package: .*/Package: python-setuptools/' python-setuptools
      sed -i 's/^# Version:.*/Version: 9999/' python-setuptools
      sed -i 's/^# Maintainer:.*/Maintainer: Build Scripts <root@local>/' python-setuptools
      sed -i 's/^# Description:.*/Description: Dummy python-setuptools to satisfy build-deps/' python-setuptools
      sed -i 's/^# Provides:.*/Provides: python-setuptools/' python-setuptools
      equivs-build python-setuptools >/dev/null 2>&1 || true
      dpkg -i python-setuptools_*.deb >/dev/null 2>&1 || true
      popd >/dev/null
      rm -rf "$TMPDIR"
    fi
  fi
}

package_with_script() {
  echo "[build_debs] Attempting packaging/build-deb.sh ..."
  pushd "$REPO_DIR" >/dev/null
  if [[ -x packaging/build-deb.sh ]]; then
    if packaging/build-deb.sh -o "$OUT_DIR"; then
      echo "[build_debs] Packaging via packaging/build-deb.sh succeeded."
      popd >/dev/null
      return 0
    else
      echo "[build_debs] packaging/build-deb.sh failed, will try dpkg-buildpackage -d fallback." >&2
      popd >/dev/null
      return 1
    fi
  else
    echo "[build_debs] packaging/build-deb.sh not found or not executable." >&2
    popd >/dev/null
    return 1
  fi
}

package_with_fallback() {
  echo "[build_debs] Fallback: dpkg-buildpackage -d -uc -us -b ..."
  pushd "$REPO_DIR" >/dev/null
  if dpkg-buildpackage -d -uc -us -b; then
    echo "[build_debs] dpkg-buildpackage succeeded. Collecting artifacts..."
    mkdir -p "$OUT_DIR"
    shopt -s nullglob
    for f in ../*.deb ../*.changes ../*.buildinfo; do
      mv -f "$f" "$OUT_DIR/" 2>/dev/null || true
    done
    shopt -u nullglob
    popd >/dev/null
    return 0
  else
    echo "[build_debs] dpkg-buildpackage failed." >&2
    popd >/dev/null
    return 1
  fi
}

ensure_deps

if ! package_with_script; then
  package_with_fallback || { echo "[build_debs] ERROR: All packaging attempts failed." >&2; exit 1; }
fi

echo "[build_debs] Artifacts in: $OUT_DIR"
ls -lh "$OUT_DIR" || true

exit 0
