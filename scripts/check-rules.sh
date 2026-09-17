#!/usr/bin/env bash
#
# Validates AgentRules/ before it is synced into consumer repositories.
#
# The rules are read as LLM context, so the checks enforce the properties that
# make them cheap to load: every file is reachable, discoverable, small, and
# free of copy-pasted prose. Run locally before committing; CI runs the same
# script.
#
# Usage: scripts/check-rules.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

RULES_DIR="AgentRules"
README="$RULES_DIR/README.md"

# Budgets are a ratchet, not a target: raise them only with a reason.
MAX_FILE_BYTES=2400
MAX_TOTAL_BYTES=16000
MIN_DUPLICATE_LINE=60

errors=0
fail() {
  printf '  - %s\n' "$1" >&2
  errors=$((errors + 1))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ ! -f "$README" ]; then
  echo "FATAL: $README not found; run this script from the repository." >&2
  exit 1
fi

mapfile -t rule_files < <(find "$RULES_DIR" -type f -name '*.md' ! -name 'README.md' | sort)

if [ "${#rule_files[@]}" -eq 0 ]; then
  echo "FATAL: no rule files found under $RULES_DIR." >&2
  exit 1
fi

# --- frontmatter ------------------------------------------------------------

# Every rule file must declare the work it governs (load-when) and the scope it
# applies to (applies-to). Without load-when an agent cannot route around it and
# must read every file to be safe.
for file in "${rule_files[@]}"; do
  first_line="$(head -n 1 "$file")"
  if [ "$first_line" != "---" ]; then
    fail "$file: missing YAML frontmatter (must start with '---')."
    continue
  fi

  fm="$(awk 'NR == 1 { next } /^---[[:space:]]*$/ { exit } { print }' "$file")"
  if [ -z "$fm" ]; then
    fail "$file: frontmatter is not closed by a second '---' line."
    continue
  fi

  for key in load-when applies-to title; do
    if ! grep -qE "^${key}:[[:space:]]*[^[:space:]]" <<<"$fm"; then
      fail "$file: frontmatter is missing a non-empty '${key}:' field."
    fi
  done
done

# --- shared scope -----------------------------------------------------------

# These files are shared by every consumer, so they must not name one of them:
# anything repository-specific belongs in that repository's own AGENTS.md.
# The consumer list is read from the sync matrix so it cannot drift.
mapfile -t consumers < <(
  grep -oE '^[[:space:]]*-[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+[[:space:]]*$' \
    .github/workflows/sync.yml | sed -E 's|.*/||; s/[[:space:]]*$//' | sort -u
)

if [ "${#consumers[@]}" -eq 0 ]; then
  fail "no consumer repositories found in .github/workflows/sync.yml."
else
  for file in "${rule_files[@]}"; do
    for consumer in "${consumers[@]}"; do
      if grep -qiF "$consumer" "$file"; then
        fail "$file: names the consumer repository '$consumer'; shared rules must be repository-agnostic."
      fi
    done
  done
fi

# --- size -------------------------------------------------------------------

total_bytes=0
for file in "${rule_files[@]}" "$README"; do
  bytes="$(wc -c <"$file" | tr -d ' ')"
  total_bytes=$((total_bytes + bytes))
  if [ "$bytes" -gt "$MAX_FILE_BYTES" ]; then
    fail "$file: ${bytes} bytes exceeds the per-file budget of ${MAX_FILE_BYTES}."
  fi
done

if [ "$total_bytes" -gt "$MAX_TOTAL_BYTES" ]; then
  fail "${RULES_DIR}/ totals ${total_bytes} bytes, over the budget of ${MAX_TOTAL_BYTES}."
fi

# --- links ------------------------------------------------------------------

# A rule that points at a file must point at a file that is actually synced.
for file in "${rule_files[@]}" "$README"; do
  dir="$(dirname "$file")"
  while IFS= read -r target; do
    case "$target" in
      http://* | https://* | mailto:* | '#'*) continue ;;
    esac
    path="${target%%#*}"
    [ -n "$path" ] || continue
    if [ ! -e "$dir/$path" ]; then
      fail "$file: link target '$target' does not exist."
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//')
done

# --- routing table coverage -------------------------------------------------

if ! grep -q '<!-- routing-table:begin -->' "$README" ||
  ! grep -q '<!-- routing-table:end -->' "$README"; then
  fail "$README: routing-table markers are missing."
else
  sed -n '/<!-- routing-table:begin -->/,/<!-- routing-table:end -->/p' "$README" |
    grep -oE '\]\([^)]+\)' |
    sed -E 's/^\]\(//; s/\)$//' >"$work/listed"

  printf '%s\n' "${rule_files[@]}" | sed "s|^${RULES_DIR}/||" | sort >"$work/actual"
  sort -u "$work/listed" >"$work/listed.sorted"

  while IFS= read -r missing; do
    [ -n "$missing" ] && fail "$README: routing table does not list $missing (unreachable for an agent)."
  done < <(comm -23 "$work/actual" "$work/listed.sorted")
  while IFS= read -r extra; do
    [ -n "$extra" ] && fail "$README: routing table lists $extra, which is not a rule file."
  done < <(comm -13 "$work/actual" "$work/listed.sorted")
  while IFS= read -r dup; do
    [ -n "$dup" ] && fail "$README: routing table lists $dup more than once."
  done < <(uniq -d "$work/listed")
fi

# --- duplicated prose -------------------------------------------------------

# The same paragraph in two files costs the context window twice. Merging the
# files or leaving one link is cheaper than both copies.
awk -v min="$MIN_DUPLICATE_LINE" '
  {
    line = $0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (length(line) < min) next
    if (line ~ /^[#|>]/ || line ~ /^---/) next
    if ((line, FILENAME) in seen) next
    seen[line, FILENAME] = 1
    where[line] = where[line] " " FILENAME
    files[line]++
  }
  END {
    for (line in files)
      if (files[line] > 1)
        printf "%s\n", substr(line, 1, 70) "  [in:" where[line] "]"
  }
' "${rule_files[@]}" "$README" | sort >"$work/duplicates"

while IFS= read -r dup; do
  [ -n "$dup" ] && fail "duplicated prose across files: $dup"
done <"$work/duplicates"

# --- shared-rules table generation -----------------------------------------

# The sync workflow regenerates each consumer AGENTS.md shared-rules table from
# the AgentRules tree using generate-shared-rules.sh. Verify the script exists,
# is executable, and produces a valid table for the current tree.
if [ ! -x scripts/generate-shared-rules.sh ]; then
  fail "scripts/generate-shared-rules.sh is missing or not executable (sync workflow depends on it)."
else
  gen_work="$work/shared-rules-gen"
  mkdir -p "$gen_work"
  cp -r AgentRules "$gen_work/"
  gen_output="$(bash scripts/generate-shared-rules.sh "$gen_work" 2>&1)"
  gen_rc=$?
  if [ "$gen_rc" -ne 0 ]; then
    fail "scripts/generate-shared-rules.sh failed (exit $gen_rc): $gen_output"
  elif [ ! -f "$gen_work/AGENTS.md" ]; then
    fail "scripts/generate-shared-rules.sh did not produce AGENTS.md."
  else
    # Every AgentRules path in the generated table must resolve to a real file.
    while IFS= read -r gen_path; do
      if [ ! -f "$gen_work/$gen_path" ]; then
        fail "generated shared-rules table references '$gen_path' which does not exist."
      fi
    done < <(grep -oE 'AgentRules/[^ `)]+\.md' "$gen_work/AGENTS.md" | sort -u)
  fi
fi

# --- report -----------------------------------------------------------------

if [ "$errors" -gt 0 ]; then
  printf 'check-rules: %d problem(s) found.\n' "$errors" >&2
  exit 1
fi

printf 'check-rules: OK — %d rule files, %d bytes total.\n' "${#rule_files[@]}" "$total_bytes"
