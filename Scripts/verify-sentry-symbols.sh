#!/usr/bin/env bash
# verify-sentry-symbols.sh — Verify every shipped Mach-O binary has a matching dSYM.
#
# This is a release gate for Sentry symbolication. It checks UUIDs, not just
# filenames, so stale or mismatched dSYMs are caught before a build ships.
#
# Usage examples:
#   ./Scripts/verify-sentry-symbols.sh \
#     --binary-root /path/to/OpenEmu.app \
#     --dsym-root /path/to/OpenEmu.xcarchive/dSYMs
#
#   ./Scripts/verify-sentry-symbols.sh --upload --wait-for 120 \
#     --binary-root /path/to/OpenEmu.app \
#     --dsym-root /path/to/OpenEmu.xcarchive/dSYMs
#
#   ./Scripts/verify-sentry-symbols.sh --upload \
#     --binary-root ~/Library/Developer/Xcode/DerivedData/.../Release/Dolphin.oecoreplugin \
#     --dsym-root ~/Library/Developer/Xcode/DerivedData/.../Release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ORG="openemu-silicon"
PROJECT="openemu-silicon"
UPLOAD=0
CHECK=0
INCLUDE_SOURCES=0
WAIT_FOR=""
BINARY_ROOTS=()
DSYM_ROOTS=()
GENERATED_DSYM_ROOT=""
ALLOW_MISSING_PATTERNS=("/Frameworks/libswift_.*\\.dylib$")
FALLBACK_DSYM_PATTERNS=(
  "/Frameworks/Sentry\\.framework/"
  "/Frameworks/UniversalDetector\\.framework/"
  "/Frameworks/XADMaster\\.framework/"
)

usage() {
  cat <<'EOF'
Usage: verify-sentry-symbols.sh [options]

Options:
  --binary-root <path>   App/plugin/framework/bundle root containing shipped binaries. Repeatable.
  --dsym-root <path>     Directory containing .dSYM bundles. Repeatable.
  --upload               Upload verified matching dSYMs to Sentry.
  --check                Run sentry-cli debug-files check without uploading.
  --include-sources      Include source context in Sentry upload.
  --wait-for <seconds>   Wait for Sentry processing after upload, e.g. 120.
  --org <slug>           Sentry org. Default: openemu-silicon.
  --project <slug>       Sentry project. Default: openemu-silicon.
  --generated-dsym-root <path>
                          Where fallback dSYMs are written. Default: temp dir.
  --allow-missing <regex> Allow a missing dSYM for matching binary paths. Repeatable.
                          Default allows Apple's bundled libswift_*.dylib runtime libraries.
  --fallback-dsym <regex> Allow dsymutil fallback dSYM generation for matching paths.
                          Defaults only cover known prebuilt third-party frameworks.
  -h, --help             Show this help.

If no roots are provided, the script uses the newest OpenEmu-Silicon archive
and its dSYMs directory.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --binary-root) BINARY_ROOTS+=("$2"); shift 2 ;;
    --dsym-root) DSYM_ROOTS+=("$2"); shift 2 ;;
    --upload) UPLOAD=1; CHECK=1; shift ;;
    --check) CHECK=1; shift ;;
    --include-sources) INCLUDE_SOURCES=1; shift ;;
    --wait-for) WAIT_FOR="$2"; shift 2 ;;
    --org) ORG="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --generated-dsym-root) GENERATED_DSYM_ROOT="$2"; shift 2 ;;
    --allow-missing) ALLOW_MISSING_PATTERNS+=("$2"); shift 2 ;;
    --fallback-dsym) FALLBACK_DSYM_PATTERNS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

die()  { echo ""; echo "ERROR: $*" >&2; exit 1; }
ok()   { echo "PASS  $*"; }
step() { echo ""; echo "──── $*"; }

matches_any_pattern() {
  local path="$1"
  shift
  local pattern
  for pattern in "$@"; do
    if [[ "$path" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

is_allowed_missing() {
  matches_any_pattern "$1" "${ALLOW_MISSING_PATTERNS[@]}"
}

can_generate_fallback_dsym() {
  matches_any_pattern "$1" "${FALLBACK_DSYM_PATTERNS[@]}"
}

if [ ${#BINARY_ROOTS[@]} -eq 0 ] && [ ${#DSYM_ROOTS[@]} -eq 0 ]; then
  ARCHIVE=$(find "$HOME/Library/Developer/Xcode/Archives" \
    -name "OpenEmu-Silicon-*.xcarchive" -type d 2>/dev/null \
    | sort | tail -1)
  [ -n "$ARCHIVE" ] || die "No OpenEmu-Silicon archive found. Pass --binary-root and --dsym-root explicitly."
  BINARY_ROOTS+=("$ARCHIVE/Products/Applications/OpenEmu.app")
  DSYM_ROOTS+=("$ARCHIVE/dSYMs")
fi

for root in "${BINARY_ROOTS[@]}"; do
  [ -e "$root" ] || die "Binary root not found: $root"
done
for root in "${DSYM_ROOTS[@]}"; do
  [ -e "$root" ] || die "dSYM root not found: $root"
done

if [ "$CHECK" -eq 1 ] && ! command -v sentry-cli >/dev/null 2>&1; then
  die "sentry-cli check/upload requested but sentry-cli is not installed."
fi
if [ "$UPLOAD" -eq 1 ] && ! sentry-cli info >/dev/null 2>&1; then
  die "sentry-cli is not authenticated. Run: sentry-cli login or set SENTRY_AUTH_TOKEN."
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
BINARIES="$TMPDIR/binaries.txt"
BINARY_UUIDS="$TMPDIR/binary-uuids.tsv"
DSYM_UUIDS="$TMPDIR/dsym-uuids.tsv"
MATCHED_DSYMS="$TMPDIR/matched-dsyms.txt"
if [ -n "$GENERATED_DSYM_ROOT" ]; then
  GENERATED_DSYM_DIR="$GENERATED_DSYM_ROOT"
else
  GENERATED_DSYM_DIR="$TMPDIR/generated-dSYMs"
fi
mkdir -p "$GENERATED_DSYM_DIR"
: > "$BINARIES"
: > "$BINARY_UUIDS"
: > "$DSYM_UUIDS"
: > "$MATCHED_DSYMS"

is_macho() {
  file -b "$1" 2>/dev/null | grep -q "Mach-O"
}

uuid_lines() {
  dwarfdump --uuid "$1" 2>/dev/null || true
}

index_dsym() {
  local dsym="$1"
  local line uuid arch
  while IFS= read -r line; do
    uuid=$(echo "$line" | awk '{print $2}')
    arch=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')
    [ -n "$uuid" ] || continue
    printf '%s\t%s\t%s\n' "$uuid" "$arch" "$dsym" >> "$DSYM_UUIDS"
  done < <(uuid_lines "$dsym")
}

find_dsym_match() {
  local uuid="$1"
  awk -F '\t' -v uuid="$uuid" '$1 == uuid { print $3; exit }' "$DSYM_UUIDS"
}

generate_fallback_dsym() {
  local bin="$1"
  local uuid="$2"
  local base safe out
  base=$(basename "$bin")
  safe=$(printf '%s-%s' "$base" "$uuid" | tr -c '[:alnum:]._-\n' '_')
  out="$GENERATED_DSYM_DIR/${safe}.dSYM"
  echo "Generating fallback dSYM with dsymutil: $out" >&2
  if dsymutil "$bin" -o "$out" >&2 && [ -d "$out" ]; then
    index_dsym "$out"
    find_dsym_match "$uuid"
  fi
}

step "Finding shipped Mach-O binaries"
for root in "${BINARY_ROOTS[@]}"; do
  while IFS= read -r -d '' file_path; do
    case "$file_path" in
      *.dSYM/*) continue ;;
    esac
    if is_macho "$file_path"; then
      printf '%s\n' "$file_path" >> "$BINARIES"
    fi
  done < <(find "$root" -type f -print0)
done

BINARY_COUNT=$(wc -l < "$BINARIES" | tr -d ' ')
[ "$BINARY_COUNT" -gt 0 ] || die "No Mach-O binaries found under binary roots."
ok "Found $BINARY_COUNT Mach-O binary file(s)"

step "Indexing binary UUIDs"
while IFS= read -r bin; do
  while IFS= read -r line; do
    uuid=$(echo "$line" | awk '{print $2}')
    arch=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')
    [ -n "$uuid" ] || continue
    printf '%s\t%s\t%s\n' "$uuid" "$arch" "$bin" >> "$BINARY_UUIDS"
  done < <(uuid_lines "$bin")
done < "$BINARIES"

UUID_COUNT=$(wc -l < "$BINARY_UUIDS" | tr -d ' ')
[ "$UUID_COUNT" -gt 0 ] || die "No UUIDs found in Mach-O binaries."
ok "Found $UUID_COUNT binary UUID(s)"

step "Indexing dSYM UUIDs"
for root in "${DSYM_ROOTS[@]}"; do
  while IFS= read -r -d '' dsym; do
    index_dsym "$dsym"
  done < <(find "$root" -name "*.dSYM" -type d -print0)
done

DSYM_UUID_COUNT=$(wc -l < "$DSYM_UUIDS" | tr -d ' ')
[ "$DSYM_UUID_COUNT" -gt 0 ] || die "No dSYM UUIDs found under dSYM roots."
ok "Found $DSYM_UUID_COUNT dSYM UUID(s)"

step "Matching binaries to dSYMs"
missing=0
while IFS=$'\t' read -r uuid arch bin; do
  match=$(find_dsym_match "$uuid")
  if [ -z "$match" ]; then
    if is_allowed_missing "$bin"; then
      echo "ALLOWED missing dSYM for Apple Swift runtime: $uuid ($arch) $bin"
    elif can_generate_fallback_dsym "$bin"; then
      match=$(generate_fallback_dsym "$bin" "$uuid" || true)
      if [ -n "$match" ]; then
        echo "GENERATED fallback dSYM for prebuilt third-party binary: $uuid ($arch)"
        echo "    binary: $bin"
        echo "    dSYM:   $match"
        printf '%s\n' "$match" >> "$MATCHED_DSYMS"
      else
        echo "MISSING dSYM: $uuid ($arch) $bin"
        missing=$((missing + 1))
      fi
    else
      echo "MISSING dSYM: $uuid ($arch) $bin"
      missing=$((missing + 1))
    fi
  else
    echo "OK: $uuid ($arch)"
    echo "    binary: $bin"
    echo "    dSYM:   $match"
    printf '%s\n' "$match" >> "$MATCHED_DSYMS"
  fi
done < "$BINARY_UUIDS"

if [ "$missing" -ne 0 ]; then
  die "$missing binary UUID(s) have no matching dSYM. Do not release/upload this build."
fi
ok "All shipped binary UUIDs have matching dSYMs"

sort -u "$MATCHED_DSYMS" -o "$MATCHED_DSYMS"

if [ "$CHECK" -eq 1 ]; then
  step "Checking matched dSYMs with sentry-cli"
  while IFS= read -r dsym; do
    while IFS= read -r -d '' dwarf_file; do
      sentry-cli debug-files check "$dwarf_file" >/dev/null
    done < <(find "$dsym/Contents/Resources/DWARF" -type f -print0)
    ok "sentry-cli check: $dsym"
  done < "$MATCHED_DSYMS"
fi

if [ "$UPLOAD" -eq 1 ]; then
  step "Uploading matched dSYMs to Sentry"
  upload_args=(debug-files upload --org "$ORG" --project "$PROJECT")
  if [ "$INCLUDE_SOURCES" -eq 1 ]; then
    upload_args+=(--include-sources)
  fi
  if [ -n "$WAIT_FOR" ]; then
    upload_args+=(--wait-for "$WAIT_FOR")
  fi
  while IFS= read -r dsym; do
    upload_args+=("$dsym")
  done < "$MATCHED_DSYMS"
  sentry-cli "${upload_args[@]}"
  ok "Uploaded $(wc -l < "$MATCHED_DSYMS" | tr -d ' ') dSYM bundle(s) to $ORG/$PROJECT"
fi
