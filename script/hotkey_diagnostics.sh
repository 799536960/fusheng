#!/usr/bin/env bash
set -euo pipefail

LINES="300"
MODE="show"

usage() {
  cat <<USAGE
Usage: $0 [--stream] [lines]

Show recent Fusheng hotkey diagnostics from:
  ~/Library/Logs/Fusheng/hotkey-diagnostics.log

Examples:
  $0
  $0 500
  $0 --stream
USAGE
}

while (($#)); do
  case "$1" in
    --stream)
      MODE="stream"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    ''|*[!0-9]*)
      usage >&2
      exit 2
      ;;
    *)
      LINES="$1"
      ;;
  esac
  shift
done

LOG_FILE="$HOME/Library/Logs/Fusheng/hotkey-diagnostics.log"

if [[ "$MODE" == "stream" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  tail -F "$LOG_FILE"
else
  if [[ ! -f "$LOG_FILE" ]]; then
    printf 'No diagnostics log found yet: %s\n' "$LOG_FILE" >&2
    exit 0
  fi
  tail -n "$LINES" "$LOG_FILE"
fi
