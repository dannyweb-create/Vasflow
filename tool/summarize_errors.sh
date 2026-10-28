#!/usr/bin/env bash
# Copies the first problems from each log onto the run's Summary page on GitHub,
# so you can read them without digging through long logs.
OUT="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

section() {  # $1 = title, $2 = log file, $3 = search pattern
  {
    echo "### $1"
    echo '```'
    if [ -f "$2" ]; then
      grep -m 12 -E "$3" "$2" || echo "(nothing found)"
    else
      echo "(this step did not run)"
    fi
    echo '```'
  } >> "$OUT"
}

echo "## First problems found" >> "$OUT"
section "Build errors" build.log "Error:|FAILURE|went wrong"
section "Analyzer errors" analyze.log " error • "
section "Test failures" test.log "Error:|Some tests failed|EXCEPTION"
