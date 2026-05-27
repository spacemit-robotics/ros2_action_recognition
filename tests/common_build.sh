#!/bin/bash
# Unified colcon build for perception PR tests.
# Usage: bash tests/common_build.sh "<package1> [package2 ...]"
# Must be run with cwd = middleware/ros2/perception.

set -eo pipefail

PACKAGES="${1:?package list required}"

if [ ! -d "face_detection" ]; then
  echo "ERROR: run from middleware/ros2/perception (missing workspace layout)" >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    echo "PATH=${PATH}" >&2
    exit 1
  fi
}

# Drop stale SDK-root install paths left in the environment (avoids colcon warnings).
sanitize_prefix_path_var() {
  local var_name="$1"
  local root="${SROBOTIS_ROOT:-${SPACEMIT_SDK_ROOT:-}}"
  local current="${!var_name:-}"
  local cleaned="" part

  [ -z "${current}" ] && return 0
  local old_ifs="${IFS}"
  IFS=':'
  for part in ${current}; do
    [ -z "${part}" ] && continue
    if [ -n "${root}" ] && [[ "${part}" == "${root}/install/"* ]] && [ ! -d "${part}" ]; then
      continue
    fi
    if [ -z "${cleaned}" ]; then
      cleaned="${part}"
    else
      cleaned="${cleaned}:${part}"
    fi
  done
  IFS="${old_ifs}"
  export "${var_name}=${cleaned}"
}

source_ros() {
  local ros_setup="/opt/ros/humble/setup.bash"
  if [ ! -f "${ros_setup}" ]; then
    echo "ERROR: ROS 2 Humble not found: ${ros_setup}" >&2
    exit 1
  fi
  set +u
  # shellcheck disable=SC1090
  source "${ros_setup}"
  set -e
}

source_sdk_env() {
  local root="${SROBOTIS_ROOT:-${SPACEMIT_SDK_ROOT:-}}"
  if [ -z "${root}" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
  fi
  export SROBOTIS_ROOT="${root}"
  if [ ! -f "${root}/build/envsetup.sh" ]; then
    echo "WARNING: envsetup.sh not found under ${root}; libvision.so may be missing" >&2
    return 0
  fi
  set +eu
  # shellcheck disable=SC1090
  source "${root}/build/envsetup.sh" || {
    echo "WARNING: envsetup.sh returned non-zero; continuing" >&2
  }
  set -e
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common_test_utils.sh"

echo "=== Building perception packages: ${PACKAGES} ==="

source_ros
source_sdk_env
sanitize_prefix_path_var AMENT_PREFIX_PATH
sanitize_prefix_path_var CMAKE_PREFIX_PATH

require_cmd colcon
require_cmd ros2

# PACKAGES may contain multiple package names separated by spaces.
# Convert to array so colcon receives each package as a separate argv.
read -r -a PACKAGES_ARR <<< "${PACKAGES}"
colcon build --packages-select "${PACKAGES_ARR[@]}" --cmake-args -DCMAKE_BUILD_TYPE=Release

source_workspace_install

echo "=== Build completed ==="
