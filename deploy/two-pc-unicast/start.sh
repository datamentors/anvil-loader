#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${DEPLOY_DIR}/lib.sh"

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "ERROR: real-robot startup requires an interactive terminal" >&2
  exit 1
fi
if [[ "${REAL_ROBOT_START_CONFIRM:-}" != "HOME_REAL_ROBOT_WITH_UNICAST_DDS" ]]; then
  echo "ERROR: export REAL_ROBOT_START_CONFIRM=HOME_REAL_ROBOT_WITH_UNICAST_DDS" >&2
  exit 1
fi

"${DEPLOY_DIR}/preflight.sh"
load_unicast_config
render_unicast_profile
build_compose_command

echo "WARNING: this starts the loader stack on REAL HARDWARE."
echo "The ros2 service connects to both CAN arms and performs automatic homing."
echo "Confirm: operator beside robot, E-stop tested, workspace clear, no teleoperation."
read -r -p "Type exactly 'HOME ROBOT WITH UNICAST': " phrase
if [[ "${phrase}" != "HOME ROBOT WITH UNICAST" ]]; then
  echo "Cancelled."
  exit 1
fi

"${COMPOSE[@]}" up --detach

echo "Default loader stack started without optional teleoperation profiles."
echo "Verify homing, controller state and sensor topics before starting inference."
