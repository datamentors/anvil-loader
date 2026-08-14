#!/usr/bin/env python3
"""Create many independent DDS processes without loading robot hardware."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time


def child(index: int, duration: float) -> int:
    import rclpy
    from rclpy.node import Node
    from std_msgs.msg import String

    rclpy.init()
    node = Node(f"dds_unicast_stress_{index:02d}")
    received = False

    if index == 0:
        publisher = node.create_publisher(String, "/dds_unicast_stress", 10)
        node.create_timer(0.1, lambda: publisher.publish(String(data="ping")))
    elif index == 1:

        def receive(_message: String) -> None:
            nonlocal received
            received = True

        node.create_subscription(String, "/dds_unicast_stress", receive, 10)

    print(f"READY {index}", flush=True)
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)

    if index == 1:
        print(f"RECEIVED {int(received)}", flush=True)
    node.destroy_node()
    rclpy.shutdown()
    return 0 if index != 1 or received else 1


def parent(count: int, duration: float) -> int:
    processes = [
        subprocess.Popen(
            [
                sys.executable,
                __file__,
                "--child",
                str(index),
                "--duration",
                str(duration),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        for index in range(count)
    ]
    ready: set[int] = set()
    received = False
    failed: list[tuple[int, int, str]] = []
    for index, process in enumerate(processes):
        output, _ = process.communicate(timeout=duration + 20)
        for line in output.splitlines():
            if line.startswith("READY "):
                ready.add(int(line.split()[1]))
            elif line == "RECEIVED 1":
                received = True
        if process.returncode != 0:
            failed.append((index, process.returncode, output))

    if failed or len(ready) != count or not received:
        print(
            f"DDS_PARTICIPANT_STRESS_FAIL ready={len(ready)}/{count} "
            f"localhost_delivery={received} failures={len(failed)}",
            file=sys.stderr,
        )
        for index, returncode, output in failed:
            print(f"--- child {index} rc={returncode} ---\n{output}", file=sys.stderr)
        return 1

    print(
        f"DDS_PARTICIPANT_STRESS_PASS participants={count} "
        "localhost_delivery=1 multicast_config=false"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=24)
    parser.add_argument("--duration", type=float, default=8.0)
    parser.add_argument("--child", type=int)
    args = parser.parse_args()
    if args.child is not None:
        return child(args.child, args.duration)
    if not 2 <= args.count <= 31:
        parser.error("--count must be between 2 and 31")
    return parent(args.count, args.duration)


if __name__ == "__main__":
    raise SystemExit(main())
