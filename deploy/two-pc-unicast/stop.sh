#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${DEPLOY_DIR}/lib.sh"

load_unicast_config
render_unicast_profile
build_compose_command
"${COMPOSE[@]}" stop ros2
