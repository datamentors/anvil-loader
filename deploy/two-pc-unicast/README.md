# Two-PC unicast DDS profile

This profile connects one robot Devbox to one inference workstation through
CycloneDDS static peers. It disables multicast discovery, keeps the complete
default loader stack, disables teleoperation, and selects the real-hardware
inference controller profile.

The profile also sets a finite CycloneDDS auto-participant ceiling above the
0.10.5 default. The default ceiling is insufficient for the loader's
multi-process ROS graph.

## Configure

Copy the local profile and review it for the workcell:

```bash
cd deploy/two-pc-unicast
cp unicast.env.example unicast.env
$EDITOR unicast.env
```

The example documents the required keys with explicit placeholders.
`unicast.env` is ignored by Git because interface names and addresses are
robot-local configuration. Confirm DHCP reservations or static assignments
before relying on the peer addresses.

The matching inference workstation must use the same ROS domain, multicast
setting and participant ceiling, with its own interface and the robot address
as its remote peer.

## Validate without starting hardware

Run the preflight while the loader `ros2` service is stopped:

```bash
./preflight.sh
```

It renders `runtime/cyclonedds_two_pc_robot.xml`, verifies the selected NIC and
peer route, resolves the complete Compose stack, preserves a local
`docker-compose.override.yml` when present, and checks that no teleoperation
profile or process is active. It does not start a container or access CAN.

## Start real hardware

Starting `ros2` connects to both CAN arms and performs automatic homing. Use a
local operator, a tested E-stop and a clear workspace. Then run:

```bash
export REAL_ROBOT_START_CONFIRM=HOME_REAL_ROBOT_WITH_UNICAST_DDS
./start.sh
```

The script asks for a second interactive confirmation. It starts the same
default services as `docker compose up`, excludes optional profiles such as
Pico4, and overrides `ros2.restart` to `no` so Docker or host restarts cannot
auto-home the arms unattended.

Before enabling inference commands, verify homing and controller state, all
three cameras and `/joint_states`, zero existing publishers on both live
controller command topics, and the inference-side freshness/safety gates.

To stop the hardware-facing ROS service while leaving telemetry services alone:

```bash
./stop.sh
```

For unexpected motion, use the physical E-stop first.

## Return to Pico4 teleoperation and data capture

The unicast inference profile deliberately excludes Pico4 services. Before
returning the workcell to teleoperation, stop the inference deployment on the
inference workstation and confirm that it no longer publishes arm commands.

Switch the Devbox back to the standard Pico4 profile with an operator beside
the robot, a tested E-stop and a clear workspace. Starting the `ros2` service
connects to the real arms and may perform automatic homing.

```bash
cd /home/anvil/anvil-loader/deploy/two-pc-unicast
./stop.sh

cd /home/anvil/anvil-loader
docker compose --profile pico4 up --detach
docker compose --profile pico4 ps
```

Verify that `ros2`, `pico4-teleop`, `xr-pc-service` and `session-bridge` are
running before starting a recording session. The workcell UI remains available
at `http://localhost:3000` from the Devbox.

Do not use `start.sh` from this directory for data capture: it starts the
inference controller profile and intentionally leaves Pico4 teleoperation
disabled.

## Network boundary

Multicast-off static peers prevent accidental discovery across a large LAN, but
they are not authentication or an inbound firewall. A third host configured to
send unicast DDS discovery to this ROS domain could still join the graph. Use a
VLAN, firewall policy or DDS Security when an adversarial isolation boundary is
required.
