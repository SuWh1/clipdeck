#!/usr/bin/env bash
# Starts the built app with a throwaway history, copies real content and checks what it saved.
# It uses your clipboard while it runs and puts the text that was on it back at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Clipdeck.app"
[[ -d "$APP" ]] || ./scripts/build-app.sh

WORK="$(mktemp -d -t clipdeck-e2e)"
DATA="$WORK/data"
DB="$DATA/history.sqlite"
pbpaste > "$WORK/clipboard.txt" 2>/dev/null || true

cleanup() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  pbcopy < "$WORK/clipboard.txt"
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL $1"
  cat "$WORK/app.log"
  exit 1
}

query() { sqlite3 "$DB" "$1" 2>/dev/null || true; }

expect() {
  for _ in $(seq 1 30); do
    [[ "$(query "$2")" == "$3" ]] && { echo "ok   $1"; return 0; }
    sleep 0.2
  done
  fail "$1: expected '$3', got '$(query "$2")'"
}

jxa() { osascript -l JavaScript -e "ObjC.import('AppKit'); $1" >/dev/null; }

CLIPDECK_SNAPSHOT="$WORK/panel.png" CLIPDECK_DATA_DIR="$DATA" "$APP/Contents/MacOS/Clipdeck" >"$WORK/app.log" 2>&1 &
APP_PID=$!
sleep 1.5
kill -0 "$APP_PID" 2>/dev/null || fail "the app did not start"

MARK="e2e-$RANDOM$RANDOM"

printf 'Clipdeck %s note' "$MARK" | pbcopy
expect "copied text is saved" "SELECT COUNT(*) FROM clips WHERE kind='text' AND text='Clipdeck $MARK note'" 1

printf 'https://example.com/%s' "$MARK" | pbcopy
expect "a copied address is saved as a link" "SELECT COUNT(*) FROM clips WHERE kind='link' AND text='https://example.com/$MARK'" 1

sips -s format png -Z 64 /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out "$WORK/image.png" >/dev/null
osascript -e "set the clipboard to (read (POSIX file \"$WORK/image.png\") as «class PNGf»)"
expect "a copied image is saved with its size" "SELECT COUNT(*) FROM clips WHERE kind='image' AND imageWidth=64" 1
IMAGE_FILE="$(query "SELECT imageFile FROM clips WHERE kind='image' AND imageWidth=64")"
[[ -f "$DATA/images/$IMAGE_FILE" ]] || fail "the image file was not written"
echo "ok   the image file is on disk"

osascript -e "set the clipboard to (POSIX file \"$WORK/image.png\")"
expect "a copied image file is saved as the same image" "SELECT COUNT(*) || '/' || MAX(copyCount) FROM clips WHERE kind='image' AND imageWidth=64" "1/2"

echo "report" > "$WORK/report-$MARK.txt"
osascript -e "set the clipboard to (POSIX file \"$WORK/report-$MARK.txt\")"
expect "a copied file is saved as a file" "SELECT COUNT(*) FROM clips WHERE kind='file' AND text LIKE '%report-$MARK.txt'" 1

jxa "var pb = \$.NSPasteboard.generalPasteboard; pb.clearContents; pb.setStringForType('secret-$MARK', 'public.utf8-plain-text'); pb.setStringForType('', 'org.nspasteboard.ConcealedType');"
sleep 1.2
[[ "$(query "SELECT COUNT(*) FROM clips WHERE text LIKE '%secret-$MARK%'")" == "0" ]] || fail "a password copy was saved"
echo "ok   copies marked as private are skipped"

printf 'Clipdeck %s note' "$MARK" | pbcopy
expect "copying the same text again moves it up instead of duplicating it" "SELECT COUNT(*) || '/' || MAX(copyCount) FROM clips WHERE text='Clipdeck $MARK note'" "1/2"

CLIPDECK_DATA_DIR="$DATA" "$APP/Contents/MacOS/Clipdeck" --show
for _ in $(seq 1 30); do [[ -s "$WORK/panel.png" ]] && break; sleep 0.2; done
[[ -s "$WORK/panel.png" ]] || fail "the history panel did not open"
kill -0 "$APP_PID" 2>/dev/null || fail "the app quit after opening the panel"
echo "ok   the history panel opens and draws"
if [[ -n "${SNAPSHOT:-}" ]]; then
  cp "$WORK/panel.png" "$SNAPSHOT" && echo "     panel image saved to $SNAPSHOT"
fi

echo "All end-to-end checks passed."
