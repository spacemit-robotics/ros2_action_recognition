#!/bin/bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
# Invalid-input PR test for action_recognition.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

MODULE=action_recognition
NODE=action_recognition_node

echo "=== Action Recognition Invalid Input Test ==="

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_setup.sh"

TEST_INVALID="${SCRIPT_DIR}/test_config_invalid.yaml"
MISSING_CONFIG="/tmp/perception_missing_config_action_recognition.yaml"

echo "Test 1: invalid config"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${TEST_INVALID} \
    -p lazy_load:=false" \
  "YAML|parse|Failed|VisionService::Create failed|runtime_error|Exception"

echo "Test 2: missing config file"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${MISSING_CONFIG} \
    -p lazy_load:=false" \
  "VisionService::Create failed|Failed|No such file|runtime_error|Exception"

echo "Test 3: invalid sequence_length"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p sequence_length:=0 \
    -p lazy_load:=true" \
  "sequence_length|invalid|out of range|runtime_error|Exception"

echo "Test 4: invalid score_threshold"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/perception_threshold_action_recognition.XXXXXX.log")"
set +e
timeout 10s ros2 run "${MODULE}" "${NODE}" --ros-args \
  -p score_threshold:=-1.0 \
  -p lazy_load:=true 2>&1 | tee "$LOG_FILE"
TH_RC=$?
set -e
if [ "$TH_RC" -eq 124 ]; then
  echo "FAIL: node hung (timeout) for invalid score_threshold" >&2
  exit 1
elif grep -Eiq 'score_threshold.*(invalid|out of range|must be between)|threshold.*(invalid|out of range)' "$LOG_FILE"; then
  echo "PASS: invalid score_threshold handled"
elif [ "$TH_RC" -ne 0 ]; then
  echo "PASS: node exited with error for invalid score_threshold"
else
  echo "FAIL: node accepted score_threshold=-1.0 without validation" >&2
  exit 1
fi

echo "=== Action recognition invalid input tests passed ==="
