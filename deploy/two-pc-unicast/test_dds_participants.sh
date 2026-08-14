#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${DEPLOY_DIR}/lib.sh"

load_unicast_config
render_unicast_profile

if docker ps --format '{{.Names}}' | grep -q '^anvil-loader-ros2-1$'; then
  echo "ERROR: refuse middleware stress test while the real ROS stack is running" >&2
  exit 1
fi

# Domain 230 is separate from the robot domain. The container has no hardware
# devices or robot config mounted; it validates 24 independent DDS processes.
docker run --rm \
  --name anvil-dds-participant-stress \
  --network host \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 512 \
  -e ROS_DOMAIN_ID=230 \
  -e ROS_AUTOMATIC_DISCOVERY_RANGE=SYSTEM_DEFAULT \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///opt/test/cyclonedds.xml \
  -e ROS_LOG_DIR=/tmp/ros-logs \
  -v "${ANVIL_DDS_PROFILE_PATH}:/opt/test/cyclonedds.xml:ro" \
  -v "${DEPLOY_DIR}/dds_participant_stress.py:/opt/test/dds_participant_stress.py:ro" \
  --entrypoint bash \
  "${ANVIL_ROS_IMAGE}" -lc \
  'source /opt/ros/jazzy/setup.bash && python3 /opt/test/dds_participant_stress.py --count 24 --duration 15'
