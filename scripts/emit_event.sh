#!/usr/bin/env bash
# Emit a simple event/metric to tmp/events.log. Non-invasive: only writes to workspace tmp.
set -euo pipefail
LOGDIR=/workspaces/AiCloudxAgent/tmp
mkdir -p "$LOGDIR"
EVENT_FILE="$LOGDIR/events.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat <<JSON >> "$EVENT_FILE"
{"ts":"$TIMESTAMP","source":"auto-merge-workflow","event":"workflow-updated","detail":"auto-merge workflow label updated to auto-merge"}
JSON
echo "Event emitted to $EVENT_FILE"
