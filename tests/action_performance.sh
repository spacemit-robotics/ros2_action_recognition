#!/bin/bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
# Scheduled performance test for action_recognition.

set -eo pipefail

if [ -n "${PERF_INIT_THRESHOLD_S:-}" ]; then
  INIT_THRESHOLD_MS=$(( PERF_INIT_THRESHOLD_S * 1000 ))
else
  INIT_THRESHOLD_MS="${PERCEPTION_INIT_THRESHOLD_MS:-5000}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

stop_process_group() {
  local pid="${1:-}"
  [ -n "${pid}" ] || return 0

  kill -INT "-${pid}" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 0.5
  done
  kill -TERM "-${pid}" 2>/dev/null || true
  sleep 0.5
  kill -KILL "-${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}

MODULE=action_recognition
NODE=action_recognition_node
ACTIONS_TOPIC="${PERCEPTION_TOPIC:-/perception/actions}"
METRICS_FILE="${SROBOTIS_TEST_ARTIFACT_DIR:-${TMPDIR:-/tmp}}/perception_perf_action_recognition.txt"
INIT_MS=""
RESULT_STATUS="unknown"
RESULT_REASON=""

write_metrics() {
  mkdir -p "$(dirname "${METRICS_FILE}")"
  {
    echo "module=${MODULE}"
    echo "init_ms=${INIT_MS}"
    echo "init_threshold_ms=${INIT_THRESHOLD_MS}"
    echo "status=${RESULT_STATUS}"
    echo "reason=${RESULT_REASON}"
    echo "model=${MODEL_PATH:-}"
  } >"${METRICS_FILE}"
  echo "Metrics written to ${METRICS_FILE}"
}

echo "=== Action Recognition Performance Test ==="
echo "threshold: init<=${INIT_THRESHOLD_MS}ms"

NODE_PID=""

cleanup_perf_nodes() {
  if [ -n "${NODE_PID}" ]; then
    stop_process_group "${NODE_PID}" || true
  fi
}
trap cleanup_perf_nodes EXIT INT TERM

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_setup.sh"

PKG_CONFIG="$(pkg_share_config action_recognition config/stgcn.yaml)"
if [ ! -f "${PKG_CONFIG}" ]; then
  echo "SKIP: config not found: ${PKG_CONFIG}"
  RESULT_STATUS="skipped"
  RESULT_REASON="config_not_found"
  write_metrics
  exit 0
fi

MODEL_PATH="$(grep '^model_path:' "${PKG_CONFIG}" | head -1 | sed 's/^model_path:[[:space:]]*//')"
MODEL_PATH="${MODEL_PATH//\"/}"
MODEL_PATH="${MODEL_PATH//\'/}"
MODEL_PATH="${MODEL_PATH/#\~/$HOME}"
if [ ! -f "${MODEL_PATH}" ]; then
  echo "SKIP: model not found at ${MODEL_PATH}"
  RESULT_STATUS="skipped"
  RESULT_REASON="model_not_found"
  write_metrics
  exit 0
fi

echo "model=${MODEL_PATH}"

start=$(date +%s%N)
setsid ros2 run "${MODULE}" "${NODE}" --ros-args \
  -p "config_path:=${PKG_CONFIG}" \
  -p lazy_load:=false 2>/dev/null &
node_pid=$!
NODE_PID="${node_pid}"

ok=0
for _ in $(seq 1 40); do
  if ros2 node list 2>/dev/null | grep -q "${NODE}"; then
    if ros2 topic list 2>/dev/null | grep -Fxq "${ACTIONS_TOPIC}"; then
      ok=1
      end=$(date +%s%N)
      break
    fi
  fi
  sleep 0.5
done

stop_process_group "${node_pid}"
NODE_PID=""

if [ "${ok}" -ne 1 ]; then
  echo "FAIL: node/topic not ready within 20s" >&2
  RESULT_STATUS="failed"
  RESULT_REASON="node_or_topic_not_ready"
  write_metrics
  exit 1
fi

elapsed=$(( (end - start) / 1000000 ))
echo "init_ms: ${elapsed}"
INIT_MS="${elapsed}"
if [ "${elapsed}" -gt "${INIT_THRESHOLD_MS}" ]; then
  echo "FAIL: ${elapsed}ms exceeds ${INIT_THRESHOLD_MS}ms" >&2
  RESULT_STATUS="failed"
  RESULT_REASON="init_threshold_exceeded"
  write_metrics
  exit 1
fi

echo "PASS: init within ${INIT_THRESHOLD_MS}ms"
RESULT_STATUS="passed"
RESULT_REASON="ok"
write_metrics
echo "=== Action recognition performance tests passed ==="
