#!/bin/bash
set -eo pipefail
export PERCEPTION_MODULE=action_recognition
export PERCEPTION_NODE=action_recognition_node
export PERCEPTION_PACKAGES="body_pose action_recognition"
export PERCEPTION_TOPIC=/perception/actions
export PERCEPTION_CONFIG_REL=config/stgcn.yaml
export PERF_INIT_THRESHOLD_S=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/action_performance.sh"
