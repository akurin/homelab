#!/usr/bin/env python3

"""Reproduce SOCKS5 UDP behavior using a public STUN server."""

import argparse
import getpass
import os
import secrets
import socket
import struct
import sys
from typing import Tuple


STUN_BINDING_REQUEST = 0x0001
STUN_BINDING_SUCCESS = 0x0101
STUN_MAGIC_COOKIE = 0x2112A442


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-host", default="isp.oxylabs.io")
    parser.add_argument("--proxy-port", type=int, default=8001)
    parser.add_argument("--username", default=os.environ.get("OXY_USER"))
    parser.add_argument("--stun-host", default="stun.nextcloud.com")
    parser.add_argument("--stun-port", type=int, default=443)
    parser.add_argument("--timeout", type=float, default=10)
    return parser.parse_args()


def receive_exact(sock: socket.socket, length: int) -> bytes:
    result = bytearray()
    while len(result) < length:
        chunk = sock.recv(length - len(result))
        if not chunk:
            raise RuntimeError("SOCKS5 server closed the control connection")
        result.extend(chunk)
    return bytes(result)


def receive_socks_address(sock: socket.socket) -> Tuple[str, int]:
    address_type = receive_exact(sock, 1)[0]
    if address_type == 1:
        host = socket.inet_ntoa(receive_exact(sock, 4))
    elif address_type == 3:
        host = receive_exact(sock, receive_exact(sock, 1)[0]).decode()
    elif address_type == 4:
        host = socket.inet_ntop(socket.AF_INET6, receive_exact(sock, 16))
    else:
        raise RuntimeError(f"Unknown SOCKS5 address type {address_type}")
    port = struct.unpack("!H", receive_exact(sock, 2))[0]
    return host, port


def unwrap_socks_udp(packet: bytes) -> bytes:
    if len(packet) < 4 or packet[:2] != b"\x00\x00":
        raise RuntimeError("Invalid SOCKS5 UDP response")
    if packet[2] != 0:
        raise RuntimeError("Fragmented SOCKS5 UDP responses are not supported")

    address_type = packet[3]
    offset = 4
    if address_type == 1:
        address_length = 4
    elif address_type == 3:
        if len(packet) <= offset:
            raise RuntimeError("Truncated SOCKS5 UDP response")
        address_length = packet[offset]
        offset += 1
    elif address_type == 4:
        address_length = 16
    else:
        raise RuntimeError(f"Unknown SOCKS5 UDP address type {address_type}")

    offset += address_length + 2
    if len(packet) < offset:
        raise RuntimeError("Truncated SOCKS5 UDP response")
    return packet[offset:]


def make_stun_request() -> Tuple[bytes, bytes]:
    transaction_id = secrets.token_bytes(12)
    request = struct.pack(
        "!HHI12s",
        STUN_BINDING_REQUEST,
        0,
        STUN_MAGIC_COOKIE,
        transaction_id,
    )
    return request, transaction_id


def validate_stun_response(response: bytes, transaction_id: bytes) -> None:
    if len(response) < 20:
        raise RuntimeError("Truncated STUN response")
    message_type, message_length, cookie, response_id = struct.unpack(
        "!HHI12s", response[:20]
    )
    if message_type != STUN_BINDING_SUCCESS:
        raise RuntimeError(f"Unexpected STUN response type 0x{message_type:04x}")
    if cookie != STUN_MAGIC_COOKIE or response_id != transaction_id:
        raise RuntimeError("STUN transaction ID or magic cookie does not match")
    if len(response) < 20 + message_length:
        raise RuntimeError("Incomplete STUN response")


def test_direct(
    target: Tuple[str, int], request: bytes, transaction_id: bytes, timeout: float
) -> None:
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.settimeout(timeout)
    udp.sendto(request, target)
    response, peer = udp.recvfrom(65535)
    validate_stun_response(response, transaction_id)
    print(f"Direct UDP: success ({peer[0]}:{peer[1]})")


def authenticate_socks5(
    control: socket.socket, username: str, password: str
) -> None:
    username_bytes = username.encode()
    password_bytes = password.encode()
    if not 1 <= len(username_bytes) <= 255 or not 1 <= len(password_bytes) <= 255:
        raise RuntimeError("SOCKS5 username and password must each be 1-255 bytes")

    control.sendall(b"\x05\x01\x02")
    if receive_exact(control, 2) != b"\x05\x02":
        raise RuntimeError("SOCKS5 server did not select username/password authentication")
    control.sendall(
        b"\x01"
        + bytes([len(username_bytes)])
        + username_bytes
        + bytes([len(password_bytes)])
        + password_bytes
    )
    if receive_exact(control, 2) != b"\x01\x00":
        raise RuntimeError("SOCKS5 authentication failed")


def test_socks5(
    args: argparse.Namespace,
    proxy_port: int,
    password: str,
    target: Tuple[str, int],
    request: bytes,
    transaction_id: bytes,
) -> None:
    proxy_ip = socket.gethostbyname(args.proxy_host)
    control = socket.create_connection((proxy_ip, proxy_port), timeout=args.timeout)
    control.settimeout(args.timeout)
    authenticate_socks5(control, args.username, password)
    print("SOCKS5 authentication: success")

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind((control.getsockname()[0], 0))
    udp.settimeout(args.timeout)
    client_host, client_port = udp.getsockname()
    control.sendall(
        b"\x05\x03\x00\x01"
        + socket.inet_aton(client_host)
        + struct.pack("!H", client_port)
    )
    version, reply, reserved = receive_exact(control, 3)
    if version != 5 or reserved != 0:
        raise RuntimeError("Invalid SOCKS5 UDP ASSOCIATE response")
    if reply != 0:
        raise RuntimeError(f"SOCKS5 UDP ASSOCIATE rejected with code {reply}")
    relay_host, relay_port = receive_socks_address(control)
    if relay_host == "0.0.0.0":
        relay_host = control.getpeername()[0]
    print(f"SOCKS5 UDP ASSOCIATE: success ({relay_host}:{relay_port})")

    packet = (
        b"\x00\x00\x00\x01"
        + socket.inet_aton(target[0])
        + struct.pack("!H", target[1])
        + request
    )
    udp.sendto(packet, (relay_host, relay_port))
    response_packet, peer = udp.recvfrom(65535)
    response = unwrap_socks_udp(response_packet)
    validate_stun_response(response, transaction_id)
    print(f"SOCKS5 UDP data: success (relay {peer[0]}:{peer[1]})")


def main() -> int:
    args = parse_args()
    if not args.username:
        args.username = input("Oxylabs username: ")
    password = os.environ.get("OXY_PASS") or getpass.getpass("Oxylabs password: ")

    target_ip = socket.gethostbyname(args.stun_host)
    target = (target_ip, args.stun_port)
    print(f"STUN target: {args.stun_host} ({target_ip}:{args.stun_port})")

    direct_request, direct_id = make_stun_request()
    try:
        test_direct(target, direct_request, direct_id, args.timeout)
    except (OSError, RuntimeError) as error:
        print(f"Direct UDP: FAILED: {error}", file=sys.stderr)
        return 1

    print(f"\nProxy: {args.proxy_host}:{args.proxy_port}")
    socks_request, socks_id = make_stun_request()
    try:
        test_socks5(
            args,
            args.proxy_port,
            password,
            target,
            socks_request,
            socks_id,
        )
    except socket.timeout:
        print(
            f"SOCKS5 UDP data: FAILED: timed out after {args.timeout:g}s",
            file=sys.stderr,
        )
        return 2
    except (OSError, RuntimeError) as error:
        print(f"SOCKS5 UDP data: FAILED: {error}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
