#!/usr/bin/env bash

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER_DIR="${ANVIL_LOADER_DIR:-$(cd "${DEPLOY_DIR}/../.." && pwd)}"
UNICAST_ENV="${ANVIL_UNICAST_ENV:-${DEPLOY_DIR}/unicast.env}"
RUNTIME_DIR="${ANVIL_UNICAST_RUNTIME_DIR:-${DEPLOY_DIR}/runtime}"
BASE_COMPOSE="${LOADER_DIR}/docker-compose.yml"
LOCAL_COMPOSE_OVERRIDE="${LOADER_DIR}/docker-compose.override.yml"
UNICAST_COMPOSE_OVERRIDE="${DEPLOY_DIR}/docker-compose.unicast.yml"

load_unicast_config() {
  [[ -f "${UNICAST_ENV}" ]] || {
    echo "ERROR: missing ${UNICAST_ENV}; copy unicast.env.example and review it" >&2
    return 1
  }

  set -a
  # shellcheck disable=SC1090
  source "${UNICAST_ENV}"
  set +a

  local required=(
    ANVIL_ROBOT_INTERFACE
    ANVIL_ROBOT_IP
    ANVIL_ROBOT_PREFIX_LENGTH
    ANVIL_GPU_IP
    ANVIL_ROS_DOMAIN_ID
    ANVIL_DDS_MAX_AUTO_PARTICIPANT_INDEX
  )
  local variable
  for variable in "${required[@]}"; do
    [[ -n "${!variable:-}" ]] || {
      echo "ERROR: ${variable} is required in ${UNICAST_ENV}" >&2
      return 1
    }
  done

  export ANVIL_DDS_MAX_MESSAGE_SIZE="${ANVIL_DDS_MAX_MESSAGE_SIZE:-1400B}"
  export ANVIL_DDS_FRAGMENT_SIZE="${ANVIL_DDS_FRAGMENT_SIZE:-1344B}"
  export ANVIL_DDS_WHC_HIGH="${ANVIL_DDS_WHC_HIGH:-8MB}"
  export ANVIL_ARMS_CONTROL_CONFIG_FILE="${ANVIL_ARMS_CONTROL_CONFIG_FILE:-openarm_inference.yaml}"
  export ANVIL_DDS_PROFILE_PATH="${RUNTIME_DIR}/cyclonedds_two_pc_robot.xml"
  export COMPOSE_PROFILES=""
}

render_unicast_profile() {
  python3 "${DEPLOY_DIR}/render_cyclonedds.py" \
    --interface "${ANVIL_ROBOT_INTERFACE}" \
    --robot-ip "${ANVIL_ROBOT_IP}" \
    --gpu-ip "${ANVIL_GPU_IP}" \
    --max-auto-participant-index "${ANVIL_DDS_MAX_AUTO_PARTICIPANT_INDEX}" \
    --max-message-size "${ANVIL_DDS_MAX_MESSAGE_SIZE}" \
    --fragment-size "${ANVIL_DDS_FRAGMENT_SIZE}" \
    --whc-high "${ANVIL_DDS_WHC_HIGH}" \
    --output "${ANVIL_DDS_PROFILE_PATH}"
}

build_compose_command() {
  [[ -f "${BASE_COMPOSE}" ]] || {
    echo "ERROR: loader compose not found: ${BASE_COMPOSE}" >&2
    return 1
  }
  COMPOSE=(
    docker compose
    --project-name anvil-loader
    --project-directory "${LOADER_DIR}"
    -f "${BASE_COMPOSE}"
  )
  # Preserve the team's implicit local override before applying the unicast
  # safety override last.
  if [[ -f "${LOCAL_COMPOSE_OVERRIDE}" ]]; then
    COMPOSE+=(-f "${LOCAL_COMPOSE_OVERRIDE}")
  fi
  COMPOSE+=(-f "${UNICAST_COMPOSE_OVERRIDE}")
}
