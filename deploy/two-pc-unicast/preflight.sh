#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${DEPLOY_DIR}/lib.sh"

for command in docker ip ping python3; do
  command -v "${command}" >/dev/null || {
    echo "ERROR: required command not found: ${command}" >&2
    exit 1
  }
done

load_unicast_config

if ! [[ "${ANVIL_ROS_DOMAIN_ID}" =~ ^[0-9]+$ ]] \
  || ((ANVIL_ROS_DOMAIN_ID < 0 || ANVIL_ROS_DOMAIN_ID > 232)); then
  echo "ERROR: ANVIL_ROS_DOMAIN_ID must be between 0 and 232" >&2
  exit 1
fi
if ! [[ "${ANVIL_ROBOT_PREFIX_LENGTH}" =~ ^[0-9]+$ ]] \
  || ((ANVIL_ROBOT_PREFIX_LENGTH < 1 || ANVIL_ROBOT_PREFIX_LENGTH > 32)); then
  echo "ERROR: ANVIL_ROBOT_PREFIX_LENGTH must be between 1 and 32" >&2
  exit 1
fi

render_unicast_profile
build_compose_command

if ! ip -4 -o addr show dev "${ANVIL_ROBOT_INTERFACE}" \
  | awk '{print $4}' \
  | grep -Fxq "${ANVIL_ROBOT_IP}/${ANVIL_ROBOT_PREFIX_LENGTH}"; then
  echo "ERROR: ${ANVIL_ROBOT_INTERFACE} does not own " \
    "${ANVIL_ROBOT_IP}/${ANVIL_ROBOT_PREFIX_LENGTH}" >&2
  exit 1
fi
if ! ping -I "${ANVIL_ROBOT_INTERFACE}" -c 2 -W 1 "${ANVIL_GPU_IP}" >/dev/null; then
  echo "ERROR: GPU peer ${ANVIL_GPU_IP} is not reachable through " \
    "${ANVIL_ROBOT_INTERFACE}" >&2
  exit 1
fi

resolved="$(mktemp)"
services="$(mktemp)"
trap 'rm -f "${resolved}" "${services}"' EXIT
"${COMPOSE[@]}" config --format json >"${resolved}"
"${COMPOSE[@]}" config --services >"${services}"

python3 - "${resolved}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    payload = json.load(stream)
service = payload["services"]["ros2"]
expected = {
    "ROS_DOMAIN_ID": os.environ["ANVIL_ROS_DOMAIN_ID"],
    "ENABLE_CYCLONEDDS": "false",
    "RMW_IMPLEMENTATION": "rmw_cyclonedds_cpp",
    "CYCLONEDDS_URI": "file:///tmp/cyclonedds_two_pc_robot.xml",
    "CYCLONEDDS_IFACE": os.environ["ANVIL_ROBOT_INTERFACE"],
    "CYCLONEDDS_PEER_IP": os.environ["ANVIL_GPU_IP"],
    "CYCLONEDDS_ALLOW_MULTICAST": "false",
    "ROS_AUTOMATIC_DISCOVERY_RANGE": "SYSTEM_DEFAULT",
    "CYCLONEDDS_MAX_MESSAGE_SIZE": os.environ["ANVIL_DDS_MAX_MESSAGE_SIZE"],
    "CYCLONEDDS_FRAGMENT_SIZE": os.environ["ANVIL_DDS_FRAGMENT_SIZE"],
    "CYCLONEDDS_WHC_HIGH": os.environ["ANVIL_DDS_WHC_HIGH"],
    "ARMS_CONTROL_CONFIG_FILE": os.environ["ANVIL_ARMS_CONTROL_CONFIG_FILE"],
    "ENABLE_VR_TELEOP": "false",
}
actual = service.get("environment", {})
errors = [
    f"{key}: {actual.get(key)!r} != {value!r}"
    for key, value in expected.items()
    if str(actual.get(key)).lower() != value.lower()
]
if errors:
    raise SystemExit("ERROR: effective ros2 environment mismatch:\n  " + "\n  ".join(errors))
if service.get("network_mode") != "host":
    raise SystemExit("ERROR: ros2 service must use host networking")
if service.get("restart") not in (None, "no"):
    raise SystemExit(f"ERROR: ros2 restart policy is not fail-closed: {service.get('restart')!r}")
if not service.get("privileged"):
    raise SystemExit("ERROR: base ros2 hardware privileges were lost during Compose merge")

mounts = service.get("volumes", [])
targets = {mount.get("target"): mount for mount in mounts}
for required_target in ("/config", "/dev/bus/usb", "/tmp/cyclonedds_two_pc_robot.xml"):
    if required_target not in targets:
        raise SystemExit(f"ERROR: required ros2 mount missing after Compose merge: {required_target}")
dds_mount = targets["/tmp/cyclonedds_two_pc_robot.xml"]
if not dds_mount.get("read_only"):
    raise SystemExit("ERROR: CycloneDDS profile is not mounted read-only")
print("[preflight] Effective DDS, controller and hardware Compose contract: PASS")
PY

if grep -Eiq 'pico4|quest|teleop|xr-pc|session-bridge' "${services}"; then
  echo "ERROR: an optional teleoperation service is active in the resolved stack" >&2
  cat "${services}" >&2
  exit 1
fi

if "${COMPOSE[@]}" ps --status running --quiet ros2 | grep -q .; then
  echo "ERROR: ros2 is already running; recreate it to apply the reviewed profile" >&2
  exit 1
fi
if docker ps --format '{{.Names}} {{.Image}} {{.Command}}' \
  | grep -Eiq 'pico4|quest.*teleop|teleop.*quest|xr-pc-service|session-bridge'; then
  echo "ERROR: a Pico4, Quest or teleoperation container is running" >&2
  exit 1
fi
if pgrep -af 'pico4_teleop_controller\.py|quest_teleop' >/dev/null; then
  echo "ERROR: a Pico4 or Quest teleoperation process is running" >&2
  pgrep -af 'pico4_teleop_controller\.py|quest_teleop' >&2 || true
  exit 1
fi

echo "[preflight] Robot address and GPU peer reachability: PASS"
echo "[preflight] Static peers rendered; multicast disabled; participant ceiling reviewed"
echo "[preflight] No teleoperation process or profile detected"
echo "[preflight] ros2 is stopped; no hardware process was started"
echo "[preflight] PASS"
