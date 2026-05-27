#!/bin/bash
# Shared assertion helpers for perception tests.

set -eo pipefail

source_ros() {
  local ros_setup="/opt/ros/humble/setup.bash"
  if [ -f "${ros_setup}" ]; then
    set +u
    # shellcheck disable=SC1090
    source "${ros_setup}"
    set -e
  fi
  if [ -f "install/local_setup.bash" ]; then
    set +u
    # shellcheck disable=SC1091
    source install/local_setup.bash
    set -e
  elif [ -f "install/setup.bash" ]; then
    set +u
    # shellcheck disable=SC1091
    source install/setup.bash
    set -e
  fi
}

cleanup_background_nodes() {
  local pattern="${1:-}"
  if [ -n "${pattern}" ]; then
    pkill -f "${pattern}" 2>/dev/null || true
  fi
  sleep 1
}

# Node must exit non-zero and log must match expected_pattern.
assert_node_fails_with_error() {
  local node_cmd="$1"
  local expected_pattern="$2"
  local timeout_sec="${3:-15}"
  local log_file="${TMPDIR:-/tmp}/perception_node_output.log"

  set +e
  # shellcheck disable=SC2086
  timeout "${timeout_sec}s" bash -c "${node_cmd}" 2>&1 | tee "${log_file}"
  local exit_code=$?
  set -e

  if [ "${exit_code}" -eq 0 ]; then
    echo "FAIL: command succeeded but failure was expected" >&2
    cat "${log_file}" >&2
    return 1
  fi

  if grep -Eiq "${expected_pattern}" "${log_file}"; then
    echo "PASS: failed with expected error (${expected_pattern})"
    return 0
  fi

  echo "FAIL: exit=${exit_code} but log missing pattern: ${expected_pattern}" >&2
  cat "${log_file}" >&2
  return 1
}

assert_node_starts() {
  local node_pattern="$1"
  local timeout_sec="${2:-10}"

  for _ in $(seq 1 "${timeout_sec}"); do
    if ros2 node list 2>/dev/null | grep -q "${node_pattern}"; then
      echo "PASS: node matching '${node_pattern}' is running"
      return 0
    fi
    sleep 1
  done

  echo "FAIL: node '${node_pattern}' not found within ${timeout_sec}s" >&2
  ros2 node list 2>/dev/null || true
  return 1
}

assert_topic_exists() {
  local topic_name="$1"
  local timeout_sec="${2:-10}"

  for _ in $(seq 1 "${timeout_sec}"); do
    if ros2 topic list 2>/dev/null | grep -q "${topic_name}"; then
      echo "PASS: topic '${topic_name}' exists"
      return 0
    fi
    sleep 1
  done

  echo "FAIL: topic '${topic_name}' not found within ${timeout_sec}s" >&2
  ros2 topic list 2>/dev/null || true
  return 1
}

pkg_share_config() {
  local pkg="$1"
  local rel="$2"
  local prefix
  prefix="$(ros2 pkg prefix "${pkg}")"
  echo "${prefix}/share/${pkg}/${rel}"
}

source_workspace_install() {
  local setup_script="install/local_setup.bash"
  if [ ! -f "${setup_script}" ]; then
    setup_script="install/setup.bash"
  fi
  if [ ! -f "${setup_script}" ]; then
    echo "ERROR: install/local_setup.bash not found (run colcon build first)" >&2
    exit 1
  fi
  set +u
  # shellcheck disable=SC1090
  source "${setup_script}"
  set -e
}

stop_node_gracefully() {
  local pid="${1:-}"
  [ -n "${pid}" ] || return 0
  kill -INT "${pid}" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do
    kill -0 "${pid}" 2>/dev/null || return 0
    sleep 0.5
  done
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}
