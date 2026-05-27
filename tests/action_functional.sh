#!/bin/bash
# Functional PR test for action_recognition (depends on body_pose).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

MODULE=action_recognition
NODE=action_recognition_node

echo "=== Action Recognition Functional Test ==="

bash "${SCRIPT_DIR}/common_build.sh" "body_pose action_recognition"
source_ros

ABS_VALID="$(cd action_recognition/tests && pwd)/test_config_valid.yaml"
TEST_INVALID="$(cd action_recognition/tests && pwd)/test_config_invalid.yaml"
PKG_CONFIG="$(pkg_share_config action_recognition config/stgcn.yaml)"

echo "Test 1: missing model in config"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${ABS_VALID} \
    -p lazy_load:=false" \
  "VisionService::Create failed|Failed to load|runtime_error|Exception"

echo "Test 2: invalid yaml config"
assert_node_fails_with_error \
  "ros2 run ${MODULE} ${NODE} --ros-args \
    -p config_path:=${TEST_INVALID} \
    -p lazy_load:=false" \
  "YAML|parse|Failed|VisionService::Create failed|runtime_error|Exception"

echo "Test 3: lazy_load node starts and advertises actions topic"
cleanup_background_nodes "${NODE}"
ros2 run "${MODULE}" "${NODE}" --ros-args \
  -p "config_path:=${PKG_CONFIG}" \
  -p lazy_load:=true &
NODE_PID=$!
sleep 3

assert_node_starts "${NODE}"
assert_topic_exists "/perception/actions"

kill "${NODE_PID}" 2>/dev/null || true
wait "${NODE_PID}" 2>/dev/null || true
cleanup_background_nodes "${NODE}"

echo "=== Action recognition functional tests passed ==="
