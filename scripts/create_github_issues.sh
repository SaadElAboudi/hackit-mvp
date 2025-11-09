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

create_issue() {
  local title="$1"; shift
  local labels_csv="$1"; shift
  local milestone="$1"; shift
  local body_file="$1"; shift

  local args=(issue create --repo "$REPO" --title "$title" --body-file "$body_file")
  if [ -n "$labels_csv" ]; then
    args+=(--label "$labels_csv")
  fi
  if [ -n "$milestone" ]; then
    args+=(--milestone "$milestone")
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

  # Labels: extract after 'Labels:' line and normalize commas
  labels=$(echo "$block" | awk '/^Labels:/{sub(/^Labels:\s*/,""); print}' | tr -d '\r' | tr -d '"')
  labels=$(echo "$labels" | sed -E 's/,\s*/,/g')

  # Milestone: from labels like milestone:1 if present
  milestone=$(echo "$labels" | tr ',' '\n' | awk -F: '/^milestone:/{print $2; exit}')

  # Body: include Description, Acceptance Criteria, Dependencies
  body_file="$tmpdir/issue.md"
  {
    echo "### $title"
    echo
    echo "$block" | sed -n "$((line_no+1)),${end_line}p" | sed '1,/^Labels:/d'
  } > "$body_file"

  echo "Creating: $title"
  create_issue "$title" "$labels" "$milestone" "$body_file"
done

echo "All issues processed."
