#!/bin/bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
# Functional PR test for action_recognition (depends on body_pose).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

MODULE=action_recognition
NODE=action_recognition_node

echo "=== Action Recognition Functional Test ==="

NODE_PID=""
cleanup_test_processes() {
  stop_node_gracefully "${NODE_PID}"
  NODE_PID=""
}
trap cleanup_test_processes EXIT INT TERM

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_setup.sh"

ABS_VALID="${SCRIPT_DIR}/test_config_valid.yaml"
TEST_INVALID="${SCRIPT_DIR}/test_config_invalid.yaml"
PKG_CONFIG="$(pkg_share_config action_recognition config/stgcn.yaml)"

echo "Test 1: missing model in config"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${ABS_VALID} \
    -p lazy_load:=false" \
  "VisionService::Create failed|Failed to load|runtime_error|Exception"

echo "Test 2: invalid config"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${TEST_INVALID} \
    -p lazy_load:=false" \
  "YAML|parse|Failed|VisionService::Create failed|runtime_error|Exception"

echo "Test 3: lazy_load node starts and advertises actions topic"
ros2 run "${MODULE}" "${NODE}" --ros-args \
  -p "config_path:=${PKG_CONFIG}" \
  -p lazy_load:=true &
NODE_PID=$!
sleep 3

assert_node_starts "${NODE}"
assert_topic_exists "/perception/actions"

stop_node_gracefully "${NODE_PID}"
NODE_PID=""

echo "=== Action recognition functional tests passed ==="
