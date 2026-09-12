#!/usr/bin/env bash
# Wrapper shortcut for run.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/run.sh" "$@"
