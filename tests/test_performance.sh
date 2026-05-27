#!/bin/bash
set -eo pipefail
export PERCEPTION_TOPIC=/perception/actions
exec "$(cd "$(dirname "$0")/../.." && pwd)/tests/action_performance.sh"
