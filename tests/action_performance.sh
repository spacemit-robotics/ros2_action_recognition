#!/bin/bash
# Scheduled performance test for action_recognition.

set -eo pipefail

INIT_THRESHOLD_MS="${PERCEPTION_INIT_THRESHOLD_MS:-5000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

MODULE=action_recognition
NODE=action_recognition_node
ACTIONS_TOPIC="${PERCEPTION_TOPIC:-/perception/actions}"

prepare_workspace() {
  if [ -d "install/action_recognition" ] && [ -d "install/body_pose" ] \
    && [ "${PERCEPTION_FORCE_BUILD:-0}" != "1" ]; then
    echo "=== Reusing install (PERCEPTION_FORCE_BUILD=1 to rebuild) ==="
    source_ros
    return 0
  fi
  bash "${SCRIPT_DIR}/common_build.sh" "body_pose action_recognition"
  source_ros
}

echo "=== Action Recognition Performance Test ==="
echo "threshold: init<=${INIT_THRESHOLD_MS}ms"

prepare_workspace

PKG_CONFIG="$(pkg_share_config action_recognition config/stgcn.yaml)"
if [ ! -f "${PKG_CONFIG}" ]; then
  echo "SKIP: config not found: ${PKG_CONFIG}"
  exit 0
fi

MODEL_PATH="$(grep '^model_path:' "${PKG_CONFIG}" | head -1 | sed 's/^model_path:[[:space:]]*//')"
MODEL_PATH="${MODEL_PATH/#\~/$HOME}"
if [ ! -f "${MODEL_PATH}" ]; then
  echo "SKIP: model not found at ${MODEL_PATH}"
  exit 0
fi

echo "model=${MODEL_PATH}"
cleanup_background_nodes "${NODE}"

start=$(date +%s%N)
ros2 run "${MODULE}" "${NODE}" --ros-args \
  -p "config_path:=${PKG_CONFIG}" \
  -p lazy_load:=false 2>/dev/null &
node_pid=$!

ok=0
for _ in $(seq 1 40); do
  if ros2 node list 2>/dev/null | grep -q "${NODE}"; then
    if ros2 topic list 2>/dev/null | grep -q "${ACTIONS_TOPIC}"; then
      ok=1
      end=$(date +%s%N)
      break
    fi
  fi
  sleep 0.5
done

stop_node_gracefully "${node_pid}"
cleanup_background_nodes "${NODE}"

if [ "${ok}" -ne 1 ]; then
  echo "FAIL: node/topic not ready within 20s" >&2
  exit 1
fi

elapsed=$(( (end - start) / 1000000 ))
echo "init_ms: ${elapsed}"
if [ "${elapsed}" -gt "${INIT_THRESHOLD_MS}" ]; then
  echo "FAIL: ${elapsed}ms exceeds ${INIT_THRESHOLD_MS}ms" >&2
  exit 1
fi

echo "PASS: init within ${INIT_THRESHOLD_MS}ms"
echo "=== Action recognition performance tests passed ==="
