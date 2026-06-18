#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Fusheng.xcodeproj"
SCHEME="Fusheng"
APP_NAME="Fusheng"
BUNDLE_ID="com.fusheng.voiceinput"
APP_DST="/Applications/浮声.app"
HOTKEY_DIAGNOSTICS_LOG="$HOME/Library/Logs/Fusheng/hotkey-diagnostics.log"
DERIVED_DATA_FUSHENG_PATTERN="$HOME/Library/Developer/Xcode/DerivedData/.*/Fusheng.app/Contents/MacOS/Fusheng"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_BASE="${DERIVED_DATA_BASE:-$HOME/Library/Developer/Xcode/DerivedData/FushengLocalPublish}"
TEST_DERIVED_DATA="$DERIVED_DATA_BASE/Test"
BUILD_DERIVED_DATA="$DERIVED_DATA_BASE/Build"
APP_SRC="$BUILD_DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

RUN_TESTS=1
LAUNCH_APP=1

usage() {
  cat <<USAGE
Usage: $0 [--skip-tests] [--no-launch] [--help]

Build, verify, clean-install, and launch Fusheng at:
  $APP_DST

Options:
  --skip-tests  Build and install without running the test suite.
  --no-launch   Install and verify the app without launching it.
  --help        Show this help.

Environment overrides:
  CONFIGURATION="$CONFIGURATION"
  DESTINATION="$DESTINATION"
  DERIVED_DATA_BASE="$DERIVED_DATA_BASE"
USAGE
}

log() {
  printf '[publish-local] %s\n' "$*"
}

die() {
  printf '[publish-local] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup_on_exit() {
  if [[ "${PUBLISH_KEEP_PROCESSES:-0}" != "1" ]]; then
    pkill -f "$DERIVED_DATA_FUSHENG_PATTERN" >/dev/null 2>&1 || true
  fi
}

trap cleanup_on_exit EXIT

while (($#)); do
  case "$1" in
    --skip-tests)
      RUN_TESTS=0
      ;;
    --no-launch)
      LAUNCH_APP=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

require_path() {
  local path="$1"
  local description="$2"
  [[ -e "$path" ]] || die "$description not found: $path"
}

stop_all_fusheng_processes() {
  log "stopping existing Fusheng processes if running"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -f "$DERIVED_DATA_FUSHENG_PATTERN" >/dev/null 2>&1 || true
  sleep 1
}

run_tests() {
  log "running tests with isolated DerivedData"
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$TEST_DERIVED_DATA"
  stop_all_fusheng_processes
}

build_app() {
  log "building clean app product"
  rm -rf "$APP_SRC"
  xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$BUILD_DERIVED_DATA"
  require_path "$APP_SRC" "built app"
}

install_app() {
  log "installing app to $APP_DST"
  rm -rf "$APP_DST"
  ditto "$APP_SRC" "$APP_DST"
  require_path "$APP_DST/Contents/MacOS/$APP_NAME" "installed executable"
}

verify_signature() {
  log "verifying installed app signature"
  codesign --verify --deep --strict --verbose=4 "$APP_DST"
}

verify_no_test_residue() {
  log "checking installed app for test residue"
  local residue
  residue="$(
    find "$APP_DST/Contents" \
      \( \
        -name 'FushengTests.xctest' -o \
        -name 'XCTest.framework' -o \
        -name 'XCTestCore.framework' -o \
        -name 'XCTestSupport.framework' -o \
        -name 'XCTAutomationSupport.framework' -o \
        -name 'XCUIAutomation.framework' -o \
        -name 'XCUnit.framework' -o \
        -name 'Testing.framework' -o \
        -name 'libXCTest*.dylib' \
      \) \
      -print
  )"

  if [[ -n "$residue" ]]; then
    printf '%s\n' "$residue" >&2
    die "installed app contains test residue"
  fi
}

reset_hotkey_diagnostics_log() {
  log "resetting hotkey diagnostics log"
  rm -f "$HOTKEY_DIAGNOSTICS_LOG" "$HOTKEY_DIAGNOSTICS_LOG.1"
}

launch_and_verify() {
  log "launching installed app"
  open "$APP_DST"
  sleep 2

  if [[ -z "$(installed_app_pids)" ]]; then
    die "installed app did not start"
  fi

  verify_only_installed_instance_is_running

  log "running process:"
  installed_app_pids | while read -r pid; do
    ps -p "$pid" -o pid=,command=
  done
}

installed_app_pids() {
  local pids
  pids="$(pgrep -x "$APP_NAME" || true)"
  [[ -n "$pids" ]] || return 0

  printf '%s\n' "$pids" | while read -r pid; do
    local command
    command="$(ps -p "$pid" -o command= || true)"
    if [[ "$command" == "$APP_DST/Contents/MacOS/$APP_NAME"* ]]; then
      printf '%s\n' "$pid"
    fi
  done
}

verify_only_installed_instance_is_running() {
  local pids
  local unexpected
  pids="$(pgrep -x "$APP_NAME" || true)"
  [[ -n "$pids" ]] || return 0

  unexpected="$(
    printf '%s\n' "$pids" | while read -r pid; do
      local command
      command="$(ps -p "$pid" -o command= || true)"
      if [[ -n "$command" && "$command" != "$APP_DST/Contents/MacOS/$APP_NAME"* ]]; then
        printf '%s %s\n' "$pid" "$command"
      fi
    done
  )"

  if [[ -n "$unexpected" ]]; then
    printf '%s\n' "$unexpected" >&2
    die "unexpected extra Fusheng process"
  fi
}

main() {
  require_path "$PROJECT_PATH" "Xcode project"
  stop_all_fusheng_processes

  if [[ "$RUN_TESTS" -eq 1 ]]; then
    run_tests
  else
    log "skipping tests by request"
  fi

  build_app
  stop_all_fusheng_processes
  install_app
  verify_signature
  verify_no_test_residue
  reset_hotkey_diagnostics_log

  if [[ "$LAUNCH_APP" -eq 1 ]]; then
    launch_and_verify
  else
    log "installed without launching"
  fi

  log "publish complete"
}

main "$@"
