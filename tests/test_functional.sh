#!/bin/bash
set -eo pipefail
exec "$(cd "$(dirname "$0")/../.." && pwd)/tests/action_functional.sh"
