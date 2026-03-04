#!/bin/bash
set -euo pipefail

NED_DIR="/neds"
PKG_DIR="/packages"
OUTPUT_DIR="/nso/run/packages"
WORK_DIR="/tmp/ned-build"

cleanup() {
  rm -rf "${WORK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

log() {
  echo "$*"
}

warn() {
  echo "WARNING: $*" >&2
}

err() {
  echo "ERROR: $*" >&2
}

unpack_neds() {
  local ned_count=0

  shopt -s nullglob
  local bins=("${NED_DIR}"/*.bin)
  shopt -u nullglob

  if [[ ${#bins[@]} -eq 0 ]]; then
    return 0
  fi

  mkdir -p "${WORK_DIR}"

  for bin_file in "${bins[@]}"; do
    local base_name
    base_name="$(basename "${bin_file}")"
    log "Unpacking NED: ${base_name}"

    local extract_dir="${WORK_DIR}/${base_name}.d"
    mkdir -p "${extract_dir}"

    (cd "${extract_dir}" && sh "${bin_file}" --skip-verification)

    shopt -s nullglob
    local tarballs=("${extract_dir}"/*.tar.gz)
    shopt -u nullglob

    if [[ ${#tarballs[@]} -eq 0 ]]; then
      err "No tarball found after unpacking ${base_name}"
      rm -rf "${extract_dir}"
      exit 1
    fi

    if [[ ${#tarballs[@]} -gt 1 ]]; then
      warn "Multiple tarballs found for ${base_name}, using first: $(basename "${tarballs[0]}")"
    fi

    tar -xzf "${tarballs[0]}" -C "${OUTPUT_DIR}"
    ned_count=$((ned_count + 1))

    rm -rf "${extract_dir}"
  done

  rm -rf "${WORK_DIR}"
  log "Unpacked ${ned_count} NED(s)"
}

copy_custom_packages() {
  local pkg_count=0

  shopt -s nullglob
  local pkgs=("${PKG_DIR}"/*/)
  shopt -u nullglob

  for pkg in "${pkgs[@]}"; do
    local pkg_name
    pkg_name="$(basename "${pkg}")"
    log "Copying custom package: ${pkg_name}"
    cp -a "${pkg}" "${OUTPUT_DIR}/${pkg_name}"
    pkg_count=$((pkg_count + 1))
  done

  if [[ ${pkg_count} -gt 0 ]]; then
    log "Copied ${pkg_count} custom package(s)"
  fi
}

compile_packages() {
  local compiled_count=0

  shopt -s nullglob
  local src_dirs=("${OUTPUT_DIR}"/*/src/)
  shopt -u nullglob

  for src_dir in "${src_dirs[@]}"; do
    if [[ ! -f "${src_dir}/Makefile" ]]; then
      continue
    fi

    local pkg_name
    pkg_name="$(basename "$(dirname "${src_dir}")")"
    log "Compiling package: ${pkg_name}"
    make -C "${src_dir}" all || { err "Failed to compile package: ${pkg_name}"; exit 1; }
    compiled_count=$((compiled_count + 1))
  done

  if [[ ${compiled_count} -gt 0 ]]; then
    log "Compiled ${compiled_count} package(s)"
  fi
}

# --- Main ---

if [[ -d "${OUTPUT_DIR}" ]]; then
  rm -rf "${OUTPUT_DIR:?}"/*
fi
mkdir -p "${OUTPUT_DIR}"

unpack_neds
copy_custom_packages

shopt -s nullglob
all_packages=("${OUTPUT_DIR}"/*/)
shopt -u nullglob

if [[ ${#all_packages[@]} -eq 0 ]]; then
  warn "No packages found to compile"
  exit 0
fi

compile_packages
log "Build complete"
