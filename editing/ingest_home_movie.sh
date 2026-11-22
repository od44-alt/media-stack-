#!/usr/bin/env bash
# ==============================================================================
# Personal Home Movie Ingest & Optimization Script (macOS)
#
# Processes finished exports from DaVinci Resolve / LosslessCut / iPhone clips
# in 03_ingest_ready, optimizes them for Apple TV + Infuse + Plex, normalizes
# audio loudness, preserves original creation dates, files them cleanly into
# HomeMovies/YYYY/YYYY-MM-DD - Title.mp4, and archives originals safely.
#
# Requirements on Mac:
#   brew install ffmpeg
#
# Usage:
#   ./ingest_home_movie.sh [--lossless] [INPUT_DIR] [OUTPUT_DIR] [ARCHIVE_DIR]
#
# Modes:
#   Default    : Apple Silicon hardware H.265 (hevc_videotoolbox) + EBU R128
#                loudness normalization (-16 LUFS) + Apple TV +faststart.
#   --lossless : Instant remux only (no video re-encode), keeps DaVinci Resolve
#                or LosslessCut video quality 100% untouched + adds +faststart.
# ==============================================================================

set -euo pipefail

LOSSLESS=false
if [[ "${1:-}" == "--lossless" ]]; then
  LOSSLESS=true
  shift
fi

# Default paths assume Windows 11 SMB shares are mounted on your Mac under /Volumes
INPUT_DIR="${1:-/Volumes/MediaEditing/03_ingest_ready}"
OUTPUT_DIR="${2:-/Volumes/HomeMovies}"
ARCHIVE_DIR="${3:-/Volumes/MediaEditing/04_archived_originals}"

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffmpeg and ffprobe are required. Install with: brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: Input directory not found: $INPUT_DIR" >&2
  echo "Make sure your Windows 11 SMB shares (MediaEditing & HomeMovies) are mounted." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$ARCHIVE_DIR"

shopt -s nullglob nocaseglob
files=("$INPUT_DIR"/*.{mp4,mov,mkv,m4v})

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No video files found in $INPUT_DIR"
  exit 0
fi

echo "Found ${#files[@]} file(s) to process (lossless=$LOSSLESS)..."

for src in "${files[@]}"; do
  filename="$(basename "$src")"
  stem="${filename%.*}"

  # Extract original recording date from container metadata (falls back to file mtime)
  raw_date="$(ffprobe -v error -show_entries format_tags=creation_time \
    -of default=noprint_wrappers=1:nokey=1 "$src" | head -n 1 || true)"

  if [[ "$raw_date" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
    year="${BASH_REMATCH[1]}"
    ymd="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  else
    year="$(date -r "$src" "+%Y")"
    ymd="$(date -r "$src" "+%Y-%m-%d")"
  fi

  # Avoid duplicating date prefix if the filename already starts with YYYY-MM-DD
  if [[ "$stem" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    clean_name="$stem"
  else
    clean_name="${ymd} - ${stem}"
  fi

  dest_year_dir="${OUTPUT_DIR}/${year}"
  mkdir -p "$dest_year_dir"
  dest="${dest_year_dir}/${clean_name}.mp4"
  tmp_dest="${dest}.tmp.mp4"

  echo "----------------------------------------------------------------------"
  echo "Processing: $filename"
  echo "Target:     $dest"

  if [[ "$LOSSLESS" == true ]]; then
    ffmpeg -hide_banner -loglevel warning -stats \
      -i "$src" \
      -map 0:v:0 -map 0:a? \
      -c copy \
      -map_metadata 0 \
      -metadata title="$clean_name" \
      -movflags +faststart \
      -y "$tmp_dest"
  else
    # Apple Silicon VideoToolbox HEVC with hvc1 tag for native Apple TV / QuickTime compatibility
    ffmpeg -hide_banner -loglevel warning -stats \
      -i "$src" \
      -map 0:v:0 -map 0:a? \
      -c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
      -c:a aac -b:a 192k -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
      -map_metadata 0 \
      -metadata title="$clean_name" \
      -movflags +faststart \
      -y "$tmp_dest"
  fi

  mv -f "$tmp_dest" "$dest"
  mv -n "$src" "$ARCHIVE_DIR/$filename"
  echo "Done! Archived original to: $ARCHIVE_DIR/$filename"
done

echo "======================================================================"
echo "All files ingested into $OUTPUT_DIR. Plex will auto-scan them shortly."
