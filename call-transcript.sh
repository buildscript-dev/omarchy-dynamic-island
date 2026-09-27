#!/bin/bash
# Call transcripts for the Dynamic Island (callTranscript setting).
#
#   call-transcript.sh start
#       Record both sides of the call that just connected: the PC's sound
#       output (the other person, carried over Bluetooth hands-free) and the
#       microphone (you). 16 kHz mono WAVs in the private run directory.
#   call-transcript.sh stop <note-file> <header> <model>
#       Stop recording, transcribe each side with whisper-cli, put the lines
#       in time order and join each speaker's run into one turn (Caller / Me,
#       turn by turn, as said), and append a Transcript section to
#       the call's note (created with <header> if it doesn't exist yet). The
#       recordings are deleted afterwards either way.
set -u
run="${XDG_RUNTIME_DIR:?}/omarchy-dynamic-island/call"

stop_recorders() {
  for p in "$run"/*.pid; do
    [ -f "$p" ] || continue
    kill -INT "$(cat "$p")" 2>/dev/null
    rm -f "$p"
  done
  sleep 0.5
}

# whisper-cli's "[00:01:02.340 --> 00:01:04.000]  text" lines, as
# "<seconds>\t<who>\t<text>" so both sides can be sorted together.
lines() {
  /usr/bin/whisper-cli -m "$2" -f "$1" -np -t 4 2>/dev/null | /usr/bin/awk -v who="$3" '
    match($0, /^\[([0-9]+):([0-9]+):([0-9.]+) -->/, t) {
      text = substr($0, index($0, "]") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", text)
      if (text == "" || text ~ /^\[.*\]$|^\(.*\)$/) next
      printf "%.2f\t%s\t%s\n", t[1] * 3600 + t[2] * 60 + t[3], who, text
    }'
}

case "${1:-}" in
start)
  umask 077
  /usr/bin/mkdir -p -- "$run" || exit 1
  [ -O "$run" ] && [ ! -L "$run" ] || exit 1
  stop_recorders
  rm -f -- "$run"/*.wav
  sink=$(/usr/bin/pactl get-default-sink 2>/dev/null)
  /usr/bin/pw-record --rate 16000 --channels 1 -P '{ stream.capture.sink = true }' \
    ${sink:+--target "$sink"} "$run/them.wav" >/dev/null 2>&1 & echo $! > "$run/them.pid"
  /usr/bin/pw-record --rate 16000 --channels 1 "$run/me.wav" >/dev/null 2>&1 & echo $! > "$run/me.pid"
  ;;
stop)
  note="$2" header="$3" model="$4"
  stop_recorders
  [ -f "$run/them.wav" ] || [ -f "$run/me.wav" ] || exit 0
  out=$( { [ -s "$run/them.wav" ] && lines "$run/them.wav" "$model" "Caller"
           [ -s "$run/me.wav" ] && lines "$run/me.wav" "$model" "Me"; } |
         /usr/bin/sort -t $'\t' -k1,1n |
         /usr/bin/awk -F '\t' '
           $2 != who { if (who != "") printf "\n\n"; who = $2
                       printf "**%s** (%02d:%02d): %s", who, int($1 / 60), int($1 % 60), $3; next }
           { printf " %s", $3 }
           END { if (who != "") printf "\n" }')
  rm -f -- "$run"/*.wav
  umask 077
  /usr/bin/mkdir -p -- "$(dirname -- "$note")" || exit 1
  exec 9>>"$(dirname -- "$note")/.lock"
  /usr/bin/flock 9
  [ -e "$note" ] || printf '%s' "$header" > "$note"
  printf '\n## Transcript\n\n%s\n' "${out:-_Nothing was picked up._}" >> "$note"
  ;;
*)
  echo "usage: call-transcript.sh start | stop <note-file> <header> <model>" >&2
  exit 2
  ;;
esac
