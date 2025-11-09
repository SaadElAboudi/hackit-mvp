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

ensure_labels() {
  local labels_csv="$1"
  IFS=',' read -r -a arr <<<"$labels_csv"
  for raw in "${arr[@]}"; do
    # trim whitespace
    local lbl="${raw##*( )}"
    lbl="${lbl%%*( )}"
    if [ -n "$lbl" ]; then
      ensure_label "$lbl"
    fi
  done
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
  # Create milestone if missing (ignore if exists)
  gh api -X POST "repos/$REPO/milestones" -f title="$title" >/dev/null 2>&1 || true
  echo "$title"
}

create_issue() {
  local title="$1"; shift
  local labels_csv="$1"; shift
  local milestone_title="$1"; shift
  local body_file="$1"; shift

  local args=(issue create --repo "$REPO" --title "$title" --body-file "$body_file")
  if [ -n "$labels_csv" ]; then
    args+=(--label "$labels_csv")
  fi
  if [ -n "$milestone_title" ]; then
    args+=(--milestone "$milestone_title")
  fi
  gh "${args[@]}"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Parse issues from the Detailed Issue Specs sections
awk '/^#### [0-9]+\./{print NR":"$0}' "$PLAN_FILE" | while IFS= read -r hdr; do
  line_no=$(echo "$hdr" | cut -d: -f1)
  heading=$(echo "$hdr" | cut -d: -f2-)

  # Determine block end: next heading or end of file
  end_line=$(awk -v start=$((line_no+1)) 'NR>start && /^#### [0-9]+\./{print NR; exit}' "$PLAN_FILE")
  if [ -z "$end_line" ]; then end_line=$(wc -l < "$PLAN_FILE"); fi

  block=$(sed -n "$line_no,${end_line}p" "$PLAN_FILE")

  # Title: strip leading hashes and numeric id
  title=$(echo "$heading" | sed -E 's/^#### [0-9]+\.\s*//')

  # Labels: extract after 'Labels:' line and normalize commas; trim outer spaces
  labels=$(echo "$block" | awk '/^Labels:/{sub(/^Labels:\s*/,""); print}' | tr -d '\r' | tr -d '"')
  labels=$(echo "$labels" | sed -E 's/,\s*/,/g; s/^\s+|\s+$//g')

  # Milestone: from labels like milestone:1 if present
  milestone=$(echo "$labels" | tr ',' '\n' | awk -F: '/^milestone:/{print $2; exit}')
  # Remove milestone:* pseudo-labels from labels before creation
  labels_no_ms=$(echo "$labels" | tr ',' '\n' | grep -v '^milestone:' || true)
  labels_no_ms=$(echo "$labels_no_ms" | paste -sd, -)

  # Ensure labels and milestone exist
  if [ -n "$labels_no_ms" ]; then
    ensure_labels "$labels_no_ms"
  fi
  milestone_title=""
  if [ -n "$milestone" ]; then
    milestone_title=$(ensure_milestone "$milestone")
  fi

  # Body: include Description, Acceptance Criteria, Dependencies
  body_file="$tmpdir/issue.md"
  {
    echo "### $title"
    echo
    echo "$block" | sed -n "$((line_no+1)),${end_line}p" | sed '1,/^Labels:/d'
  } > "$body_file"

  echo "Creating: $title"
  create_issue "$title" "$labels_no_ms" "$milestone_title" "$body_file"
done

echo "All issues processed."
