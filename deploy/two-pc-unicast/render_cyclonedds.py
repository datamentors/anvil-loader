#!/usr/bin/env python3
"""Render a validated robot-side CycloneDDS profile for two-PC unicast."""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

_INTERFACE_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]+$")
_SIZE_PATTERN = re.compile(r"^[1-9][0-9]*(?:B|kB|MB)$")


def _validated_ipv4(value: str, label: str) -> str:
    try:
        address = ipaddress.ip_address(value)
    except ValueError as exc:
        raise ValueError(f"{label} must be a valid IPv4 address: {value!r}") from exc
    if address.version != 4 or address.is_unspecified or address.is_multicast:
        raise ValueError(f"{label} must be a unicast IPv4 address: {value!r}")
    return str(address)


def _validated_size(value: str, label: str) -> str:
    if not _SIZE_PATTERN.fullmatch(value):
        raise ValueError(f"{label} must use CycloneDDS size syntax such as 1400B")
    return value


def build_profile(
    *,
    interface: str,
    robot_ip: str,
    gpu_ip: str,
    max_auto_participant_index: int,
    max_message_size: str,
    fragment_size: str,
    whc_high: str,
) -> ET.ElementTree:
    if not _INTERFACE_PATTERN.fullmatch(interface):
        raise ValueError(f"invalid network interface name: {interface!r}")
    robot_ip = _validated_ipv4(robot_ip, "robot IP")
    gpu_ip = _validated_ipv4(gpu_ip, "GPU IP")
    if robot_ip == gpu_ip:
        raise ValueError("robot IP and GPU IP must be different")
    if not 24 <= max_auto_participant_index <= 120:
        raise ValueError("max auto participant index must be between 24 and 120")

    max_message_size = _validated_size(max_message_size, "max message size")
    fragment_size = _validated_size(fragment_size, "fragment size")
    whc_high = _validated_size(whc_high, "WHC high watermark")

    namespace = "https://cdds.io/config"
    ET.register_namespace("", namespace)
    root = ET.Element(f"{{{namespace}}}CycloneDDS")
    domain = ET.SubElement(root, f"{{{namespace}}}Domain", {"id": "any"})
    general = ET.SubElement(domain, f"{{{namespace}}}General")
    interfaces = ET.SubElement(general, f"{{{namespace}}}Interfaces")
    ET.SubElement(interfaces, f"{{{namespace}}}NetworkInterface", {"name": interface})
    ET.SubElement(general, f"{{{namespace}}}AllowMulticast").text = "false"
    ET.SubElement(general, f"{{{namespace}}}MaxMessageSize").text = max_message_size
    ET.SubElement(general, f"{{{namespace}}}FragmentSize").text = fragment_size

    discovery = ET.SubElement(domain, f"{{{namespace}}}Discovery")
    peers = ET.SubElement(discovery, f"{{{namespace}}}Peers")
    ET.SubElement(peers, f"{{{namespace}}}Peer", {"address": robot_ip})
    ET.SubElement(peers, f"{{{namespace}}}Peer", {"address": gpu_ip})
    ET.SubElement(discovery, f"{{{namespace}}}ParticipantIndex").text = "auto"
    ET.SubElement(discovery, f"{{{namespace}}}MaxAutoParticipantIndex").text = str(
        max_auto_participant_index
    )

    internal = ET.SubElement(domain, f"{{{namespace}}}Internal")
    ET.SubElement(
        internal,
        f"{{{namespace}}}SocketReceiveBufferSize",
        {"min": "128MB"},
    )
    watermarks = ET.SubElement(internal, f"{{{namespace}}}Watermarks")
    ET.SubElement(watermarks, f"{{{namespace}}}WhcHigh").text = whc_high
    ET.indent(root, space="  ")
    return ET.ElementTree(root)


def write_profile(tree: ET.ElementTree, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output.parent,
        prefix=f".{output.name}.",
        text=True,
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            tree.write(stream, encoding="utf-8", xml_declaration=True)
            stream.write(b"\n")
        # The profile contains no credentials. It must remain readable by a
        # capability-dropped validation container and is mounted read-only in
        # the hardware stack.
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, output)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--robot-ip", required=True)
    parser.add_argument("--gpu-ip", required=True)
    parser.add_argument("--max-auto-participant-index", required=True, type=int)
    parser.add_argument("--max-message-size", required=True)
    parser.add_argument("--fragment-size", required=True)
    parser.add_argument("--whc-high", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    try:
        tree = build_profile(
            interface=args.interface,
            robot_ip=args.robot_ip,
            gpu_ip=args.gpu_ip,
            max_auto_participant_index=args.max_auto_participant_index,
            max_message_size=args.max_message_size,
            fragment_size=args.fragment_size,
            whc_high=args.whc_high,
        )
        write_profile(tree, args.output)
    except ValueError as exc:
        parser.error(str(exc))
    print(f"Rendered {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
