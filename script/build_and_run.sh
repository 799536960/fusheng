#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_SCRIPT="$ROOT_DIR/script/publish_local.sh"
APP_PATH="/Applications/浮声.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Fusheng"
BUNDLE_ID="com.fusheng.voiceinput"
APP_PROCESS="Fusheng"
MODE="${1:-run}"

usage() {
  cat <<USAGE
Usage: $0 [run|--verify|--logs|--telemetry|--debug] [publish options]

Modes:
  run          Publish locally and launch the app.
  --verify    Publish locally and verify the app process is running.
  --logs      Publish locally, then stream process logs.
  --telemetry Publish locally, then stream app subsystem logs.
  --debug     Publish locally without launch, then open lldb for the app binary.

Publish options after the mode are passed to script/publish_local.sh.
USAGE
}

run_publish() {
  "$PUBLISH_SCRIPT" "$@"
}

case "$MODE" in
  run)
    shift || true
    run_publish "$@"
    ;;
  --verify|verify)
    shift || true
    run_publish "$@"
    pgrep -fl "$APP_EXECUTABLE" >/dev/null
    ;;
  --logs|logs)
    shift || true
    run_publish "$@"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PROCESS\""
    ;;
  --telemetry|telemetry)
    shift || true
    run_publish "$@"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --debug|debug)
    shift || true
    run_publish --no-launch "$@"
    lldb -- "$APP_EXECUTABLE"
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
