#!/bin/bash
# NELIA: unisce le registrazioni di Nelia Assistenza Remota (REC) in un .mp4
# che si apre con un doppio clic, con la voce della «Chiamata vocale».
#
# Gira da solo sul Mac (LaunchAgent it.mynelia.unisci-registrazioni): guarda
# la cartella delle registrazioni e, per ogni video .webm finito che non ha
# ancora il suo .mp4 (finito = il suo audio, riscritto ogni 200 ms mentre si
# registra, e' fermo da 10 secondi; senza audio: video fermo da 60 secondi):
#   - cerca l'audio della stessa registrazione (stesso computer, iniziato
#     entro 2 minuti dal video) e lo mette a tempo col video;
#   - crea «<nome del computer> <AAAA-MM-GG hh.mm>.mp4» sulla Scrivania, nella
#     cartella «Registrazioni lezioni» (se non si puo', nella stessa cartella).
# Gli originali (.webm e .wav) restano. Un video gia' fatto non si rifa'
# (elenco in .unite). Per tornare indietro: ANNULLA REGISTRA AUDIO.
# Quando un .mp4 e' pronto scrive il suo percorso in .pronti/<id>: l'app lo
# legge per mandarlo al cliente (ANNULLA MANDA REGISTRAZIONE).

set -u
# Numeri sempre col punto (col Mac in italiano printf e bc userebbero la virgola).
export LC_ALL=C
CARTELLA="${NELIA_CARTELLA:-$HOME/Movies/Nelia-Assistenza-Remota}"
PEERS="${NELIA_PEERS:-$HOME/Library/Preferences/com.carriez.Nelia-Assistenza-Remota/peers}"
FFMPEG="${NELIA_FFMPEG:-$HOME/.local/bin/ffmpeg}"
FFPROBE="${NELIA_FFPROBE:-$HOME/.local/bin/ffprobe}"
FATTE="$CARTELLA/.unite"
USCITE="${NELIA_USCITE:-$HOME/Desktop/Registrazioni lezioni}"
ATTESA="${NELIA_ATTESA:-60}"
ATTESA_AUDIO="${NELIA_ATTESA_AUDIO:-10}"

[ -d "$CARTELLA" ] || exit 0
[ -x "$FFMPEG" ] || { echo "ffmpeg mancante: $FFMPEG"; exit 1; }
touch "$FATTE"
exec 9>"$CARTELLA/.unisci.lock"
/usr/bin/lockf -t 0 9 2>/dev/null || exit 0

# «20261111143856935» -> secondi dal 1970 (con i millesimi)
secondi() {
  local t="$1"
  local base
  base=$(date -j -f "%Y%m%d%H%M%S" "${t:0:14}" "+%s" 2>/dev/null) || return 1
  echo "$base.${t:14:3}"
}

adesso=$(date +%s)
for video in "$CARTELLA"/outgoing_*_display*.webm; do
  [ -f "$video" ] || continue
  nome=$(basename "$video")
  grep -qxF "$nome" "$FATTE" && continue
  # ancora in scrittura?
  eta_video=$(( adesso - $(stat -f %m "$video") ))
  [ "$eta_video" -ge "$ATTESA_AUDIO" ] || continue

  # outgoing_<id>_<tempo>_display<n>_<codec>.webm
  resto="${nome#outgoing_}"
  tempo=$(echo "$resto" | sed -E 's/^.*_([0-9]{17})_display[0-9]+_[a-z0-9]+\.webm$/\1/')
  id="${resto%_${tempo}_*}"
  [ ${#tempo} -eq 17 ] || continue
  t_video=$(secondi "$tempo") || continue

  # L'audio: stesso computer, iniziato entro 2 minuti; il piu' vicino.
  audio=""
  meglio=999999
  for a in "$CARTELLA"/outgoing_"$id"_*_audio.wav; do
    [ -f "$a" ] || continue
    [ $(( adesso - $(stat -f %m "$a") )) -ge "$ATTESA_AUDIO" ] || continue 2
    ta=$(basename "$a" | sed -E 's/^.*_([0-9]{17})_audio\.wav$/\1/')
    t_audio=$(secondi "$ta") || continue
    d=$(echo "$t_video - $t_audio" | bc)
    ad=$(echo "if ($d < 0) -1 * $d else $d" | bc)
    if [ "$(echo "$ad <= 120 && $ad < $meglio" | bc)" = "1" ]; then
      meglio=$ad
      audio=$a
      sposta=$(printf "%.3f" "$d")
    fi
  done
  [ -n "$audio" ] || [ "$eta_video" -ge "$ATTESA" ] || continue

  # Il nome: il nome del computer (dalla rubrica del programma) e l'ora.
  alias=""
  [ -f "$PEERS/$id.toml" ] && alias=$(grep -E "^alias = " "$PEERS/$id.toml" | head -1 | sed -E "s/^alias = '(.*)'$/\1/")
  [ -n "$alias" ] || alias="Assistenza $id"
  alias=$(echo "$alias" | tr '/:' '--')
  quando="${tempo:0:4}-${tempo:4:2}-${tempo:6:2} ${tempo:8:2}.${tempo:10:2}"
  schermo=$(echo "$nome" | sed -E 's/.*_display([0-9]+)_.*/\1/')
  extra=""
  [ "$schermo" != "0" ] && extra=" schermo $((schermo + 1))"
  dove="$CARTELLA"
  mkdir -p "$USCITE" 2>/dev/null && [ -w "$USCITE" ] && dove="$USCITE"
  uscita="$dove/$alias $quando$extra.mp4"
  temp="$CARTELLA/.in-corso-$$.mp4"

  # Video: H.264 (si apre ovunque), mai piu' largo di 1920, fotogrammi solo
  # quando lo schermo cambia (file piccoli). Audio: AAC, a tempo col video.
  durata=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$video" 2>/dev/null)
  if [ -n "$audio" ]; then
    if [ "$(echo "$sposta >= 0" | bc)" = "1" ]; then
      # il video e' partito dopo l'audio: si salta l'inizio dell'audio
      ingresso_audio=(-ss "$sposta" -i "$audio")
    else
      ingresso_audio=(-itsoffset "$(printf "%.3f" "$(echo "0 - $sposta" | bc)")" -i "$audio")
    fi
    "$FFMPEG" -hide_banner -loglevel error -y -i "$video" "${ingresso_audio[@]}" \
      -map 0:v:0 -map 1:a:0 -vf "scale='min(1920,iw)':-2" -fps_mode vfr \
      -c:v libx264 -preset medium -crf 26 -pix_fmt yuv420p \
      -c:a aac -b:a 96k ${durata:+-t "$durata"} -movflags +faststart "$temp"
  else
    "$FFMPEG" -hide_banner -loglevel error -y -i "$video" \
      -map 0:v:0 -vf "scale='min(1920,iw)':-2" -fps_mode vfr \
      -c:v libx264 -preset medium -crf 26 -pix_fmt yuv420p -movflags +faststart "$temp"
  fi
  if [ $? -eq 0 ] && [ -s "$temp" ]; then
    if ! mv -f "$temp" "$uscita" 2>/dev/null; then
      uscita="$CARTELLA/$(basename "$uscita")"
      mv -f "$temp" "$uscita"
    fi
    echo "$nome" >> "$FATTE"
    mkdir -p "$CARTELLA/.pronti"
    printf '%s' "$uscita" > "$CARTELLA/.pronti/.$id.tmp" && mv -f "$CARTELLA/.pronti/.$id.tmp" "$CARTELLA/.pronti/$id"
    echo "$(date '+%F %T') fatto: $(basename "$uscita")${audio:+ (con audio)}"
  else
    rm -f "$temp"
    echo "$(date '+%F %T') non riuscito: $nome"
  fi
done
