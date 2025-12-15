#!/usr/bin/env bash
set -euo pipefail

#
# create-windows-install-usb.sh
# v1.0
#
# Creates a Windows bootable USB from a Windows installation ISO on macOS; follows the
# approach in https://lavacreeper.medium.com/how-to-make-a-windows-11-bootable-usb-on-a-mac-a52a7c8495dc
#
# Format USB as FAT (MS-DOS);
# copy everything EXCEPT sources/install.wim;
# split install.wim into <4GB chunks with wimlib so it fits on FAT32
#
# - Brandon Thomas (me@brandonthomas.net), December 2025
#

# ---------------------------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage:
  create-windows-install-usb.sh [--scheme gpt|mbr] [--name WIN11] [--split-size-mb 3500] [--force] <USB_PATH> <ISO_PATH>

Inputs:
  USB_PATH  Either a device like /dev/disk2 or a mounted volume path like /Volumes/MyUSB
  ISO_PATH  Path to the Windows 11 ISO file

Options:
  --scheme gpt|mbr       Partition scheme for the USB (GUID for UEFI and MBR for legacy).
                         Default: gpt
  --name NAME            Volume name to format the USB as. 
                         Default: WIN11
  --split-size-mb N      Chunk size (MB) for install.wim splitting. Must be < 4000 for FAT32. 
                         Default: 3500
  --force                Do not prompt for confirmation before erasing the USB
  -h, --help             Show help

Examples:
  ./create-windows-install-usb.sh /dev/disk2 ~/Downloads/Win11.iso
  ./create-windows-install-usb.sh --scheme mbr /Volumes/USBSTICK ~/Downloads/Win11.iso
USAGE
}

# ---------------------------------------------------------------------------------------------
# err
# ---------------------------------------------------------------------------------------------
err() { printf "Error: %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------------------------
# die
# Prefer returning (so wrappers like run_quiet_step can report/log nicely),
# but still work at top-level where 'return' is invalid
# ---------------------------------------------------------------------------------------------
die() {
  if [[ "${LOG_KEEP:-0}" == "0" ]]; then
    LOG_KEEP="1"
  fi
  err "$*"
  return 1 2>/dev/null || exit 1
}

# ---------------------------------------------------------------------------------------------
# Minimal TUI (progress)
# ---------------------------------------------------------------------------------------------

UI_IS_TTY=0
if [[ -t 1 ]]; then UI_IS_TTY=1; fi

UI_TOTAL_STEPS=12
UI_SPINNER_PID=""
UI_SPINNER_ACTIVE_STEP=""
UI_SPINNER_STATUS_FILE=""

# ---------------------------------------------------------------------------------------------
# ui__step_label
# ---------------------------------------------------------------------------------------------
ui__step_label() {
  local step="$1"
  # Pad single-digit steps so they visually align with double-digit steps, like:
  #  [9/12]
  # [10/12]
  if [[ "${UI_TOTAL_STEPS}" -ge 10 && "$step" -lt 10 ]]; then
    printf " [%s/%s]" "$step" "$UI_TOTAL_STEPS"
  else
    printf "[%s/%s]" "$step" "$UI_TOTAL_STEPS"
  fi
}

# ---------------------------------------------------------------------------------------------
# ui__clear_line
# ---------------------------------------------------------------------------------------------
ui__clear_line() {
  if (( UI_IS_TTY )); then
    printf "\r\033[2K"
  fi
}

# ---------------------------------------------------------------------------------------------
# ui__println
# ---------------------------------------------------------------------------------------------
ui__println() {
  # shellcheck disable=SC2059
  printf "%s\n" "$*"
}

# ---------------------------------------------------------------------------------------------
# ui_live_start
# ---------------------------------------------------------------------------------------------
ui_live_start() {
  local step="$1"
  local msg="$2"

  UI_SPINNER_ACTIVE_STEP="$step"

  # Stop any existing spinner
  if [[ -n "${UI_SPINNER_PID}" ]]; then
    kill "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    wait "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    UI_SPINNER_PID=""
  fi
  if [[ -n "${UI_SPINNER_STATUS_FILE}" && -f "${UI_SPINNER_STATUS_FILE}" ]]; then
    rm -f "${UI_SPINNER_STATUS_FILE}" >/dev/null 2>&1 || true
  fi

  UI_SPINNER_STATUS_FILE="$(mktemp -t win11usb.status.XXXXXX)"
  printf "%s" "$msg" >"${UI_SPINNER_STATUS_FILE}"

  if (( ! UI_IS_TTY )); then
    ui__println "$(ui__step_label "$step") $msg"
    return 0
  fi

  (
    local frames='|/-\'
    local i=0
    while true; do
      local f="${frames:i%4:1}"
      local cur=""
      if [[ -n "${UI_SPINNER_STATUS_FILE}" && -f "${UI_SPINNER_STATUS_FILE}" ]]; then
        cur="$(cat "${UI_SPINNER_STATUS_FILE}" 2>/dev/null || true)"
      fi
      printf "\r\033[2K%s %s %s" "$(ui__step_label "$step")" "$f" "$cur"
      sleep 0.12
      i=$((i+1))
    done
  ) &
  UI_SPINNER_PID="$!"
}

# ---------------------------------------------------------------------------------------------
# ui_live_set
# ---------------------------------------------------------------------------------------------
ui_live_set() {
  local msg="$1"
  if [[ -n "${UI_SPINNER_STATUS_FILE}" ]]; then
    printf "%s" "$msg" >"${UI_SPINNER_STATUS_FILE}" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------------------------
# ui_live_stop_ok
# ---------------------------------------------------------------------------------------------
ui_live_stop_ok() {
  local step="$1"
  local msg="$2"

  if [[ -n "${UI_SPINNER_PID}" ]]; then
    kill "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    wait "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    UI_SPINNER_PID=""
  fi
  if [[ -n "${UI_SPINNER_STATUS_FILE}" && -f "${UI_SPINNER_STATUS_FILE}" ]]; then
    rm -f "${UI_SPINNER_STATUS_FILE}" >/dev/null 2>&1 || true
  fi
  UI_SPINNER_STATUS_FILE=""

  ui__clear_line
  ui__println "$(ui__step_label "$step") $msg - done"
}

# ---------------------------------------------------------------------------------------------
# ui_live_stop_fail
# ---------------------------------------------------------------------------------------------
ui_live_stop_fail() {
  local step="$1"
  local msg="$2"

  if [[ -n "${UI_SPINNER_PID}" ]]; then
    kill "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    wait "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    UI_SPINNER_PID=""
  fi
  if [[ -n "${UI_SPINNER_STATUS_FILE}" && -f "${UI_SPINNER_STATUS_FILE}" ]]; then
    rm -f "${UI_SPINNER_STATUS_FILE}" >/dev/null 2>&1 || true
  fi
  UI_SPINNER_STATUS_FILE=""

  ui__clear_line
  ui__println "$(ui__step_label "$step") $msg - FAILED"
}

# ---------------------------------------------------------------------------------------------
# run_quiet_step <step> <msg> <log_file> <cmd...>
# ---------------------------------------------------------------------------------------------
run_quiet_step() {
  local step="$1"; shift
  local msg="$1"; shift
  local log_file="$1"; shift

  ui_live_start "$step" "$msg"
  set +e
  "$@" >"$log_file" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    ui_live_stop_fail "$step" "$msg"
    LOG_KEEP="1"
    err "Command failed (exit $rc). Last 40 log lines:"
    tail -n 40 "$log_file" >&2 || true
    exit $rc
  fi
  ui_live_stop_ok "$step" "$msg"
}

# ---------------------------------------------------------------------------------------------
# run_quiet_step_allow_fail <step> <msg> <log_file> <cmd...>
# Same as run_quiet_step but will not exit non-zero; used for best-effort cleanup/unmounts
# ---------------------------------------------------------------------------------------------
run_quiet_step_allow_fail() {
  local step="$1"; shift
  local msg="$1"; shift
  local log_file="$1"; shift

  ui_live_start "$step" "$msg"
  set +e
  "$@" >"$log_file" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    # Still mark done; this is best-effort; keep logs
    ui_live_stop_ok "$step" "$msg"
    return 0
  fi
  ui_live_stop_ok "$step" "$msg"
}

# ---------------------------------------------------------------------------------------------
# require_cmd
# ---------------------------------------------------------------------------------------------
require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing required command: $c"
}

# ---------------------------------------------------------------------------------------------
# rsync_major_version
# Prints the rsync major version number (e.g. 2, 3); returns 1 if unknown
# ---------------------------------------------------------------------------------------------
rsync_major_version() {
  local bin="$1"
  local line
  line="$("$bin" --version 2>/dev/null | head -n1 || true)"
  [[ -n "$line" ]] || return 1

  # Examples that I found:
  # - "rsync  version 2.6.9  protocol version 29"
  # - "rsync  version 3.2.7  protocol version 31"
  awk '
    {
      for (i=1; i<=NF; i++) {
        if ($i == "version") {
          split($(i+1), a, ".");
          if (a[1] ~ /^[0-9]+$/) { print a[1]; exit 0 }
        }
      }
      exit 1
    }
  ' <<<"$line"
}

# ---------------------------------------------------------------------------------------------
# rsync_supports_progress2
# Newer rsync accepts the option even when combined with --version
# Older Apple rsync errors with "unrecognized option"
# ---------------------------------------------------------------------------------------------
rsync_supports_progress2() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  "$bin" --info=progress2 --version >/dev/null 2>&1
}

# ---------------------------------------------------------------------------------------------
# is_macos
# ---------------------------------------------------------------------------------------------
is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

# ---------------------------------------------------------------------------------------------
# DO: Parse args & check requirements
# ---------------------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"

SCHEME="gpt"
VOL_NAME="WIN11"
SPLIT_MB="3500"
FORCE="0"

USB_INPUT=""
ISO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme)
      SCHEME="${2:-}"; shift 2;;
    --name)
      VOL_NAME="${2:-}"; shift 2;;
    --split-size-mb)
      SPLIT_MB="${2:-}"; shift 2;;
    --force)
      FORCE="1"; shift;;
    -h|--help)
      usage; exit 0;;
    -*)
      err "Unknown option: $1"; usage; exit 1;;
    *)
      if [[ -z "${USB_INPUT}" ]]; then
        USB_INPUT="$1"; shift
      elif [[ -z "${ISO_PATH}" ]]; then
        ISO_PATH="$1"; shift
      else
        err "Unexpected extra argument: $1"; usage; exit 1
      fi
      ;;
  esac
done

if [[ -z "${USB_INPUT}" || -z "${ISO_PATH}" ]]; then
  usage
  exit 1
fi

if ! is_macos; then
  err "This script is intended to run on macOS (Darwin)."
  exit 1
fi

if [[ ! -f "${ISO_PATH}" ]]; then
  err "ISO not found: ${ISO_PATH}"
  exit 1
fi

case "${SCHEME}" in
  gpt|GPT) SCHEME="GPT";;
  mbr|MBR) SCHEME="MBR";;
  *)
    err "--scheme must be 'gpt' or 'mbr' (got: ${SCHEME})"
    exit 1
    ;;
esac

if ! [[ "${SPLIT_MB}" =~ ^[0-9]+$ ]]; then
  err "--split-size-mb must be an integer (got: ${SPLIT_MB})"
  exit 1
fi
if (( SPLIT_MB >= 4000 )); then
  err "--split-size-mb must be < 4000 for FAT32 compatibility (got: ${SPLIT_MB})"
  exit 1
fi

require_cmd diskutil
require_cmd hdiutil
require_cmd awk
require_cmd sed

INV_USER="${SUDO_USER:-$USER}"

# ---------------------------------------------------------------------------------------------
# run_as_user
# ---------------------------------------------------------------------------------------------
run_as_user() {
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    sudo -u "${SUDO_USER}" -H "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------------------------
# ensure_homebrew
# ---------------------------------------------------------------------------------------------
ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  # Homebrew install script refuses to run as root; try to run as the invoking user
  if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    die "Running as root without SUDO_USER; can't auto-install Homebrew safely. Re-run without sudo, or install Homebrew manually."
  fi

  # Homebrew install is chatty; log it and show a spinner to keep the UX "alive"
  # If Homebrew prompts for a password, the prompt will still appear
  run_as_user /bin/bash -c "$(cat <<'EOS'
set -euo pipefail
command -v curl >/dev/null 2>&1 || { echo "curl is required to install Homebrew"; exit 1; }
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
EOS
)" || return 1

  # Try common Homebrew locations if PATH wasn't updated in the current shell
  if ! command -v brew >/dev/null 2>&1; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [[ -x /usr/local/bin/brew ]]; then
      export PATH="/usr/local/bin:$PATH"
    fi
  fi

  command -v brew >/dev/null 2>&1 || {
    die "Homebrew installation completed but 'brew' is still not on PATH. Open a new terminal or add brew to PATH, then re-run."
  }
}

# ---------------------------------------------------------------------------------------------
# ensure_brew_pkg
# ---------------------------------------------------------------------------------------------
ensure_brew_pkg() {
  local pkg="$1"
  if run_as_user brew list --formula "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  # Reduce noise as much as Homebrew allows; keep logs
  # - Disable auto-update chatter
  # - Disable cleanup chatter
  run_as_user env \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    brew install "$pkg"
}

# ---------------------------------------------------------------------------------------------
# ensure_modern_rsync
# ---------------------------------------------------------------------------------------------
ensure_modern_rsync() {
  # Sets RSYNC_BIN to an rsync that supports --info=progress2 (rsync 3.x)
  # Prefers system rsync if it supports progress2; otherwise installs/uses Homebrew rsync
  local sys_rsync
  sys_rsync="$(command -v rsync 2>/dev/null || true)"
  if [[ -n "$sys_rsync" ]] && rsync_supports_progress2 "$sys_rsync"; then
    RSYNC_BIN="$sys_rsync"
    return 0
  fi

  # Need Homebrew rsync; install it
  ensure_brew_pkg rsync || return 1
  RSYNC_BIN="$(run_as_user brew --prefix rsync 2>/dev/null)/bin/rsync"
  if [[ ! -x "${RSYNC_BIN}" ]]; then
    die "Homebrew rsync not found at expected path: ${RSYNC_BIN}"
  fi

  if ! rsync_supports_progress2 "${RSYNC_BIN}"; then
    local ver
    ver="$("${RSYNC_BIN}" --version 2>/dev/null | head -n1 || true)"
    die "Installed rsync does not support --info=progress2 (unexpected). rsync='${RSYNC_BIN}' version='${ver:-unknown}'"
  fi
}

# ---------------------------------------------------------------------------------------------
# resolve_usb_device
# ---------------------------------------------------------------------------------------------
resolve_usb_device() {
  local input="$1"
  local dev=""

  if [[ "$input" == /dev/disk* ]]; then
    # If a slice was provided (e.g. /dev/disk2s1), resolve to the whole disk
    local whole
    whole="$(diskutil info "$input" 2>/dev/null | awk -F: '/Part of Whole/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
    if [[ -n "$whole" ]]; then
      dev="/dev/${whole}"
    else
      dev="$input"
    fi
  else
    # Could be /Volumes/NAME or any mount path; diskutil can resolve
    if [[ ! -e "$input" ]]; then
      err "USB path not found: $input"
      exit 1
    fi
    local whole
    whole="$(diskutil info "$input" 2>/dev/null | awk -F: '/Part of Whole/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
    if [[ -z "$whole" ]]; then
      # Fallback: if they passed a device node without /dev prefix
      if [[ "$input" =~ ^disk[0-9]+$ ]]; then
        whole="$input"
      fi
    fi
    if [[ -z "$whole" ]]; then
      err "Could not resolve a disk device from: $input"
      err "Pass a device like /dev/disk2 (recommended) or a mounted volume like /Volumes/WIN11."
      exit 1
    fi
    dev="/dev/${whole}"
  fi

  if [[ ! -e "$dev" ]]; then
    err "Device does not exist: $dev"
    exit 1
  fi

  echo "$dev"
}

USB_DEV="$(resolve_usb_device "$USB_INPUT")"

USB_INFO="$(diskutil info "$USB_DEV" 2>/dev/null || true)"
USB_WHOLE="$(echo "$USB_INFO" | awk -F: '/Part of Whole/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
if [[ -z "$USB_WHOLE" ]]; then
  # If a whole disk is provided, Part of Whole may be empty; extract identifier.
  USB_WHOLE="$(basename "$USB_DEV")"
fi

USB_IS_INTERNAL="$(echo "$USB_INFO" | awk -F: '/Internal/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
USB_MEDIA_NAME="$(echo "$USB_INFO" | awk -F: '/Media Name/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"

if [[ "${USB_IS_INTERNAL}" == "Yes" ]]; then
  err "Refusing to erase an internal disk (${USB_DEV})."
  err "Resolved media name: ${USB_MEDIA_NAME:-unknown}"
  exit 1
fi

if [[ "${FORCE}" != "1" ]]; then
  ui__println ""
  ui__println "About to ERASE: ${USB_DEV} (${USB_MEDIA_NAME:-unknown})"
  ui__println "This will format it as '${VOL_NAME}' using scheme ${SCHEME} (MS-DOS/FAT)."
  printf "Type the disk identifier (%s) to confirm: " "${USB_DEV}"
  read -r confirm
  if [[ "$confirm" != "$USB_DEV" ]]; then
    err "Confirmation did not match. Aborting."
    exit 1
  fi
fi

LOG_DIR="$(mktemp -d -t win11usb.XXXXXX)"
LOG_KEEP="0"

# ---------------------------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------------------------
cleanup() {
  set +e

  # Stop spinner if still running
  if [[ -n "${UI_SPINNER_PID}" ]]; then
    kill "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    wait "${UI_SPINNER_PID}" >/dev/null 2>&1 || true
    UI_SPINNER_PID=""
  fi
  if [[ -n "${UI_SPINNER_STATUS_FILE:-}" && -f "${UI_SPINNER_STATUS_FILE:-}" ]]; then
    rm -f "${UI_SPINNER_STATUS_FILE}" >/dev/null 2>&1 || true
    UI_SPINNER_STATUS_FILE=""
  fi

  if [[ -n "${ISO_MOUNT:-}" && -d "${ISO_MOUNT:-}" ]]; then
    hdiutil detach "${ISO_MOUNT}" >/dev/null 2>&1 || true
  fi

  if [[ "${LOG_KEEP}" == "0" && -n "${LOG_DIR:-}" && -d "${LOG_DIR:-}" ]]; then
    rm -rf "${LOG_DIR}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------------------------
# Step 1: validate quickly (visible UX checkpoint)
# ---------------------------------------------------------------------------------------------
ui__println "$(ui__step_label 1) Validating inputs - done"

# ---------------------------------------------------------------------------------------------
# Step 2/3: dependencies
# ---------------------------------------------------------------------------------------------
ui_live_start 2 "Checking Homebrew"
if command -v brew >/dev/null 2>&1; then
  ui_live_stop_ok 2 "Checking Homebrew"
else
  ui_live_stop_ok 2 "Checking Homebrew"
  run_quiet_step 2 "Installing Homebrew" "${LOG_DIR}/homebrew-install.log" ensure_homebrew
fi

ui_live_start 3 "Checking wimlib"
if run_as_user brew list --formula wimlib >/dev/null 2>&1; then
  ui_live_stop_ok 3 "Checking wimlib"
else
  ui_live_stop_ok 3 "Checking wimlib"
  run_quiet_step 3 "Installing wimlib via Homebrew" "${LOG_DIR}/brew-wimlib.log" ensure_brew_pkg wimlib
fi

# ---------------------------------------------------------------------------------------------
# Step 4: rsync (need rsync 3.x for --info=progress2)
# ---------------------------------------------------------------------------------------------
ui_live_start 4 "Checking rsync (needs 3.x)"
RSYNC_BIN="$(command -v rsync 2>/dev/null || true)"
if [[ -n "${RSYNC_BIN}" ]] && rsync_supports_progress2 "${RSYNC_BIN}"; then
  ui_live_stop_ok 4 "Checking rsync (needs 3.x)"
else
  ui_live_stop_ok 4 "Checking rsync (needs 3.x)"
  run_quiet_step 4 "Installing/using rsync (progress2-capable)" "${LOG_DIR}/brew-rsync.log" ensure_modern_rsync
fi

# At this point ensure_modern_rsync has set RSYNC_BIN if the system one was insufficient.
if [[ -z "${RSYNC_BIN:-}" || ! -x "${RSYNC_BIN}" ]]; then
  ensure_modern_rsync
fi

require_cmd wimlib-imagex

ISO_MOUNT=""
USB_MOUNT="/Volumes/${VOL_NAME}"

# ---------------------------------------------------------------------------------------------
# Step 5: unmount (best-effort)
# ---------------------------------------------------------------------------------------------
run_quiet_step_allow_fail 5 "Unmounting USB (if mounted)" "${LOG_DIR}/unmount.log" diskutil unmountDisk "${USB_DEV}"

# ---------------------------------------------------------------------------------------------
# Step 6: erase/format
# ---------------------------------------------------------------------------------------------
run_quiet_step 6 "Erasing and formatting USB" "${LOG_DIR}/erase.log" diskutil eraseDisk MS-DOS "${VOL_NAME}" "${SCHEME}" "${USB_DEV}"

# ---------------------------------------------------------------------------------------------
# Step 7: Wait for USB to mount
# ---------------------------------------------------------------------------------------------
ui_live_start 7 "Waiting for USB to mount at ${USB_MOUNT}"
for _ in {1..80}; do
  [[ -d "${USB_MOUNT}" ]] && break
  sleep 0.15
done
ui_live_stop_ok 7 "Waiting for USB to mount at ${USB_MOUNT}"
if [[ ! -d "${USB_MOUNT}" ]]; then
  err "USB volume did not mount at ${USB_MOUNT}. Check Disk Utility / diskutil output."
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# Step 8: mount ISO
# ---------------------------------------------------------------------------------------------
ui_live_start 8 "Mounting ISO (read-only)"
set +e
ATTACH_OUT="$(hdiutil attach -nobrowse -readonly "${ISO_PATH}" 2>&1)"
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  ui_live_stop_fail 8 "Mounting ISO (read-only)"
  LOG_KEEP="1"
  err "hdiutil attach failed. Output:"
  printf "%s\n" "${ATTACH_OUT}" >&2
  exit $RC
fi
ui_live_stop_ok 8 "Mounting ISO (read-only)"

ISO_MOUNT="$(printf "%s\n" "${ATTACH_OUT}" | sed -n 's/.*[[:space:]]\(\/*Volumes\/.*\)$/\1/p' | head -n1)"
if [[ -z "${ISO_MOUNT}" || ! -d "${ISO_MOUNT}" ]]; then
  err "Failed to find ISO mount point from hdiutil output."
  err "hdiutil output:"
  printf "%s\n" "${ATTACH_OUT}" >&2
  exit 1
fi

mkdir -p "${USB_MOUNT}/sources"

# ---------------------------------------------------------------------------------------------
# Step 9: rsync copy with single-line progress (log + parse)
# ---------------------------------------------------------------------------------------------
RSYNC_LOG="${LOG_DIR}/rsync-copy.log"
RSYNC_CUR="?"
RSYNC_TOTAL="?"
RSYNC_PCT="?"
RSYNC_SPEED="?"

ui_live_start 9 "Copying ISO files"

set +e
"${RSYNC_BIN}" -aH --info=progress2 --exclude='sources/install.wim' "${ISO_MOUNT}/" "${USB_MOUNT}/" 2>&1 \
  | tee "${RSYNC_LOG}" \
  | tr '\r' '\n' \
  | while IFS= read -r line; do
      if [[ "$line" =~ xfr#([0-9]+) ]]; then RSYNC_CUR="${BASH_REMATCH[1]}"; fi
      if [[ "$line" =~ to-check=[0-9]+/([0-9]+) ]]; then RSYNC_TOTAL="${BASH_REMATCH[1]}"; fi
      if [[ "$line" =~ ([0-9]+)% ]]; then RSYNC_PCT="${BASH_REMATCH[1]}%"; fi
      if [[ "$line" =~ ([0-9.]+[KMG]B/s) ]]; then RSYNC_SPEED="${BASH_REMATCH[1]}"; fi

      if [[ "$line" =~ xfr# && "$line" =~ to-check= ]]; then
        ui_live_set "Copying ISO files - file ${RSYNC_CUR}/${RSYNC_TOTAL} - ${RSYNC_SPEED} - ${RSYNC_PCT}"
      fi
    done
RSYNC_RC="${PIPESTATUS[0]}"
set -e

if [[ "${RSYNC_RC}" != "0" ]]; then
  ui_live_stop_fail 9 "Copying ISO files"
  LOG_KEEP="1"
  err "rsync failed (exit ${RSYNC_RC}). Last 40 log lines:"
  tail -n 40 "${RSYNC_LOG}" >&2 || true
  exit "${RSYNC_RC}"
fi

ui_live_stop_ok 9 "Copying ISO files"

if [[ -f "${ISO_MOUNT}/sources/install.wim" ]]; then
  # ---------------------------------------------------------------------------------------------
   # Step 10: split WIM with progress (best-effort)
  # ---------------------------------------------------------------------------------------------
  WIMLIB_LOG="${LOG_DIR}/wimlib-split.log"
  ui_live_start 10 "Splitting install.wim"
  set +e
  wimlib-imagex split "${ISO_MOUNT}/sources/install.wim" "${USB_MOUNT}/sources/install.swm" "${SPLIT_MB}" 2>&1 \
    | tee "${WIMLIB_LOG}" \
    | tr '\r' '\n' \
    | while IFS= read -r line; do
        if [[ "$line" =~ ([0-9]{1,3})% ]]; then
          ui_live_set "Splitting install.wim - ${BASH_REMATCH[1]}%"
        fi
      done
  WIMLIB_RC="${PIPESTATUS[0]}"
  set -e

  if [[ "${WIMLIB_RC}" != "0" ]]; then
    ui_live_stop_fail 10 "Splitting install.wim"
    LOG_KEEP="1"
    err "wimlib-imagex split failed (exit ${WIMLIB_RC}). Last 60 log lines:"
    tail -n 60 "${WIMLIB_LOG}" >&2 || true
    exit "${WIMLIB_RC}"
  fi

  ui_live_stop_ok 10 "Splitting install.wim"
elif [[ -f "${ISO_MOUNT}/sources/install.esd" ]]; then
  # ---------------------------------------------------------------------------------------------
   # Step 10: copy ESD
  # ---------------------------------------------------------------------------------------------
  ESD_LOG="${LOG_DIR}/rsync-esd.log"
  ui_live_start 10 "Copying install.esd"
  set +e
  "${RSYNC_BIN}" -aH --info=progress2 "${ISO_MOUNT}/sources/install.esd" "${USB_MOUNT}/sources/" 2>&1 \
    | tee "${ESD_LOG}" \
    | tr '\r' '\n' \
    | while IFS= read -r line; do
        if [[ "$line" =~ xfr#([0-9]+) ]]; then RSYNC_CUR="${BASH_REMATCH[1]}"; fi
        if [[ "$line" =~ to-check=[0-9]+/([0-9]+) ]]; then RSYNC_TOTAL="${BASH_REMATCH[1]}"; fi
        if [[ "$line" =~ ([0-9]+)% ]]; then RSYNC_PCT="${BASH_REMATCH[1]}%"; fi
        if [[ "$line" =~ ([0-9.]+[KMG]B/s) ]]; then RSYNC_SPEED="${BASH_REMATCH[1]}"; fi

        if [[ "$line" =~ xfr# && "$line" =~ to-check= ]]; then
          ui_live_set "Copying install.esd - file ${RSYNC_CUR}/${RSYNC_TOTAL} - ${RSYNC_SPEED} - ${RSYNC_PCT}"
        fi
      done
  ESD_RC="${PIPESTATUS[0]}"
  set -e

  if [[ "${ESD_RC}" != "0" ]]; then
    ui_live_stop_fail 10 "Copying install.esd"
    LOG_KEEP="1"
    err "rsync failed (exit ${ESD_RC}). Last 40 log lines:"
    tail -n 40 "${ESD_LOG}" >&2 || true
    exit "${ESD_RC}"
  fi

  ui_live_stop_ok 10 "Copying install.esd"
else
  err "Neither sources/install.wim nor sources/install.esd found in ISO. Is this a valid Windows ISO?"
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# Step 11: detach ISO
# ---------------------------------------------------------------------------------------------
run_quiet_step 11 "Detaching ISO" "${LOG_DIR}/detach.log" hdiutil detach "${ISO_MOUNT}"
ISO_MOUNT=""

# ---------------------------------------------------------------------------------------------
# Step 12: eject USB
# ---------------------------------------------------------------------------------------------
run_quiet_step 12 "Ejecting USB" "${LOG_DIR}/eject.log" diskutil eject "${USB_DEV}"

ui__println ""
ui__println "Done. Your Windows 11 installer USB is ready."
