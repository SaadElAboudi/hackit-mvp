#!/usr/bin/env bash
set -euo pipefail

# Batch creates GitHub issues from docs/issues_plan.md sections.
# Requirements:
#  - GitHub CLI installed: https://cli.github.com/
#  - Authenticated: gh auth login
#  - Repo context set (run from repo root)
#
# Usage:
#   scripts/create_github_issues.sh
#
# The script parses headings like "#### 1. Summaries with Citations & Timestamps"
# and the subsequent blocks (Labels:, Description:, Acceptance Criteria:, Dependencies:)
# to generate issues with labels and body.

PLAN_FILE="docs/issues_plan.md"
shopt -s extglob || true
DRY_RUN=${DRY_RUN:-0}
VERBOSE=${VERBOSE:-0}

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) not found. Install from https://cli.github.com and run 'gh auth login'" >&2
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

# Extract repository in owner/name form
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO" ]; then
  echo "Unable to get current repo via gh; falling back to git remote origin"
  REPO=$(git remote get-url origin | sed -E 's#(git@|https://)github.com[:/](.*)\.git#\2#')
fi
echo "Target repo: $REPO"

ensure_label() {
  local name="$1"
  # Skip pseudo-labels like milestone:1
  if [[ "$name" =~ ^milestone: ]]; then
    return 0
  fi
  # Try to create the label; ignore error if it already exists
  gh label create "$name" --color F2F2F2 --description "auto-created" --repo "$REPO" >/dev/null 2>&1 || true
}

trim() {
  echo "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' 
}

ensure_labels() {
  local labels_csv="$1"
  IFS=',' read -r -a arr <<<"$labels_csv"
  for raw in "${arr[@]}"; do
    local lbl; lbl=$(trim "$raw")
    if [ -n "$lbl" ]; then
      ensure_label "$lbl"
    fi
  done
}

# Clean labels: trim, drop milestone:*, and echo normalized CSV
normalize_labels_and_milestone() {
  local labels_csv="$1"
  local -a out=()
  local milestone=""
  IFS=',' read -r -a arr <<<"$labels_csv"
  for raw in "${arr[@]}"; do
      local lbl; lbl=$(trim "$raw")
    [ -z "$lbl" ] && continue
    if [[ "$lbl" =~ ^milestone: ]]; then
      milestone="${lbl#milestone:}"
      continue
    fi
    out+=("$lbl")
  done
  local joined="$(printf ",%s" "${out[@]}")"; joined="${joined:1}"
  echo "$joined|$milestone"
}

ensure_milestone() {
  local num="$1"
  local title=""
  case "$num" in
    1) title="1 (Foundation)" ;;
    2) title="2 (Interaction)" ;;
    3) title="3 (Search Intelligence)" ;;
    *) title="$num" ;;
  esac
  # Attempt create (ignore if exists)
  gh api -X POST "repos/$REPO/milestones" -f title="$title" >/dev/null 2>&1 || true
  # Resolve milestone number for consistency (optional)
  local mid
  mid=$(gh api "repos/$REPO/milestones?state=all" -q ".[] | select(.title == \"$title\") | .number" 2>/dev/null || true)
  if [ -n "$mid" ]; then
    echo "$mid" # return number so gh can unambiguously match
  else
    echo "$title" # fallback to title
  fi
}

create_issue() {
  local title="$1"; shift
  local labels_csv="$1"; shift
  local milestone_ref="$1"; shift
  local body_file="$1"; shift

  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY_RUN] Would create issue: '$title'";
    echo "  Labels: $labels_csv";
    echo "  Milestone: $milestone_ref";
    [ "$VERBOSE" = "1" ] && echo "  Body Preview:" && sed -n '1,15p' "$body_file" && echo "  (truncated)";
    return 0
  fi

  local args=(issue create --repo "$REPO" --title "$title" --body-file "$body_file")
  if [ -n "$labels_csv" ]; then
    args+=(--label "$labels_csv")
  fi
  if [ -n "$milestone_ref" ]; then
    args+=(--milestone "$milestone_ref")
  fi
  if [ "$VERBOSE" = "1" ]; then
    echo "Executing: gh ${args[*]}"
  fi
  if ! gh "${args[@]}"; then
    echo "ERROR creating issue: $title" >&2
    return 1
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Parse issues from the Detailed Issue Specs sections
total=0
created=0
failed=0

while IFS= read -r hdr; do
  line_no=$(echo "$hdr" | cut -d: -f1)
  heading=$(echo "$hdr" | cut -d: -f2-)

  # Determine block end: next heading or end of file
  end_line=$(awk -v start=$((line_no+1)) 'NR>start && /^#### [0-9]+\./{print NR; exit}' "$PLAN_FILE")
  if [ -z "$end_line" ]; then end_line=$(wc -l < "$PLAN_FILE"); fi

  # Use end_line - 1 to exclude the next heading line from the block
  last_line=$((end_line-1))
  if [ "$last_line" -lt "$line_no" ]; then last_line="$line_no"; fi
  block=$(sed -n "$line_no,${last_line}p" "$PLAN_FILE")

  # Title: strip leading hashes and numeric id
  title=$(echo "$heading" | sed -E 's/^#### [0-9]+\.\s*//' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

  # Labels: extract after 'Labels:' line and normalize commas; trim outer spaces
  labels=$(echo "$block" | awk '/^Labels:/{sub(/^Labels:\s*/,""); print}' | tr -d '\r' | tr -d '"')
  labels=$(echo "$labels" | sed -E 's/,\s*/,/g; s/^\s+|\s+$//g')

  # Milestone: from labels like milestone:1 if present
  parsed=$(normalize_labels_and_milestone "$labels")
  labels_no_ms="${parsed%%|*}"
  milestone="${parsed##*|}"

  # Ensure labels and milestone exist
  if [ -n "$labels_no_ms" ]; then
    ensure_labels "$labels_no_ms"
  fi
  milestone_title=""
  if [ -n "$milestone" ]; then
    milestone_title=$(ensure_milestone "$milestone")
  fi

  # Body: include Description, Acceptance Criteria, Dependencies
  body_file="$tmpdir/issue_$line_no.md"
  {
    echo "### $title"
    echo
    # Remove first heading line and Labels: line; keep rest (Description, Acceptance, Dependencies, Notes...)
    echo "$block" | sed '1d' | sed '/^Labels:/d'
  } > "$body_file"

  if [ "$VERBOSE" = "1" ]; then
    echo "Parsed issue title='$title' labels='$labels_no_ms' milestone='$milestone_title' (src line $line_no)"
  fi

  echo "Creating: $title"
  if create_issue "$title" "$labels_no_ms" "$milestone_title" "$body_file"; then
    created=$((created+1))
  else
    failed=$((failed+1))
  fi
  total=$((total+1))
done < <(awk '/^#### [0-9]+\./{print NR":"$0}' "$PLAN_FILE")

echo "Processed $total issues: $created created, $failed failed."
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run complete. Re-run without DRY_RUN=1 to create issues."
fi
