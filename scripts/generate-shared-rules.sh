#!/usr/bin/env bash
#
# Generates the shared-rules routing table in a consumer AGENTS.md from the
# AgentRules/ tree. The table is placed between explicit marker comments so
# repo-specific prose is never touched.
#
# Usage: scripts/generate-shared-rules.sh [consumer-directory]
#
# When called with no argument, operates in the current directory.
# The script expects AgentRules/ to exist relative to the target directory
# (or relative to CWD when no argument is given).
#
# The table lists every .md file under AgentRules/ (except README.md) with
# its frontmatter `title:` field as the Area column. Files are sorted by
# directory then filename for a deterministic order.
#
# Marker comments:
#   <!-- shared-rules-table:begin -->
#   <!-- shared-rules-table:end -->
#
# If AGENTS.md exists without markers, the table block is appended.
# If AGENTS.md does not exist, a minimal file is created.

set -uo pipefail

CONSUMER_DIR="${1:-.}"
AGENTS_MD="$CONSUMER_DIR/AGENTS.md"
RULES_DIR="$CONSUMER_DIR/AgentRules"
BEGIN_MARKER="<!-- shared-rules-table:begin -->"
END_MARKER="<!-- shared-rules-table:end -->"

if [ ! -d "$RULES_DIR" ]; then
  echo "FATAL: $RULES_DIR not found." >&2
  exit 1
fi

# Build the shared-rules table from frontmatter title fields.
TABLE="$(
  find "$RULES_DIR" -type f -name '*.md' ! -name 'README.md' -print |
    sort -t/ -k2,2 -k3,3 |
    while IFS= read -r file; do
      rel="${file#${RULES_DIR}/}"
      title="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/, ""); print; exit}' "$file")"
      if [ -z "$title" ]; then
        title="$(basename "$file" .md | tr '-' ' ')"
      fi
      printf '| %s | [`AgentRules/%s`](AgentRules/%s) |\n' "$title" "$rel" "$rel"
    done
)"

if [ -z "$TABLE" ]; then
  echo "FATAL: no rule files found under $RULES_DIR." >&2
  exit 1
fi

BLOCK="$(printf '%s\n| Area | Rules |\n| --- | --- |\n%s\n%s' \
  "$BEGIN_MARKER" "$TABLE" "$END_MARKER")"

# Case 1: AGENTS.md does not exist — create a minimal one.
if [ ! -f "$AGENTS_MD" ]; then
  printf '## Shared rules\n\n%s\n' "$BLOCK" > "$AGENTS_MD"
  echo "Created $AGENTS_MD with shared-rules table."
  exit 0
fi

# Case 2: AGENTS.md exists — update or append the table block.
if grep -qF "$BEGIN_MARKER" "$AGENTS_MD"; then
  # Markers present — replace the delimited block.
  awk -v block="$BLOCK" -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { print block; skip=1; next }
    $0 == end   { skip=0; next }
    !skip       { print }
  ' "$AGENTS_MD" > "${AGENTS_MD}.tmp"
  mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
  echo "Updated shared-rules table in $AGENTS_MD."
else
  # No markers — append the block.
  printf '\n%s\n' "$BLOCK" >> "$AGENTS_MD"
  echo "Appended shared-rules table to $AGENTS_MD."
fi
