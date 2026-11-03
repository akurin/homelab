#!/usr/bin/env python3

"""Authenticated UDP echo server and client for connectivity tests."""

import argparse
import datetime
import os
import secrets
import socket
import struct


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--port", type=int, default=40000, help="UDP port")
    parser.add_argument(
        "--token",
        required=True,
        help="Shared token used to ignore unrelated internet traffic",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve = subparsers.add_parser("serve", help="Listen and echo authenticated packets")
    add_common_arguments(serve)
    serve.add_argument("--bind", default="0.0.0.0", help="IPv4 address to bind")
    serve.add_argument(
        "--once",
        action="store_true",
        help="Exit after echoing the first authenticated packet",
    )

    send = subparsers.add_parser("send", help="Send one packet and wait for its echo")
    add_common_arguments(send)
    send.add_argument("--host", required=True, help="IPv4 address or hostname to test")
    send.add_argument("--timeout", type=float, default=5, help="Reply timeout in seconds")
    send.add_argument(
        "--socks5",
        metavar="HOST:PORT",
        help="Use SOCKS5 UDP with credentials from OXY_USER and OXY_PASS",
    )

    return parser.parse_args()


def validate_port(port: int) -> None:
    if not 1 <= port <= 65535:
        raise SystemExit("--port must be between 1 and 65535")


def serve(args: argparse.Namespace) -> None:
    prefix = args.token.encode() + b":"
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.bind, args.port))
    print(f"Listening on udp://{args.bind}:{args.port}", flush=True)

    while True:
        payload, peer = sock.recvfrom(65535)
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()

        if not payload.startswith(prefix):
            print(
                f"{timestamp} ignored {len(payload)} bytes from {peer[0]}:{peer[1]}",
                flush=True,
            )
            continue

        sock.sendto(payload, peer)
        print(
            f"{timestamp} echoed {len(payload)} bytes to {peer[0]}:{peer[1]}",
            flush=True,
        )
        if args.once:
            return


def receive_exact(sock: socket.socket, length: int) -> bytes:
    result = bytearray()
    while len(result) < length:
        chunk = sock.recv(length - len(result))
        if not chunk:
            raise SystemExit("SOCKS5 server closed the control connection")
        result.extend(chunk)
    return bytes(result)


def receive_socks_address(sock: socket.socket) -> tuple[str, int]:
    address_type = receive_exact(sock, 1)[0]
    if address_type == 1:
        host = socket.inet_ntoa(receive_exact(sock, 4))
    elif address_type == 3:
        host = receive_exact(sock, receive_exact(sock, 1)[0]).decode()
    elif address_type == 4:
        host = socket.inet_ntop(socket.AF_INET6, receive_exact(sock, 16))
    else:
        raise SystemExit(f"SOCKS5 server returned unknown address type {address_type}")
    port = struct.unpack("!H", receive_exact(sock, 2))[0]
    return host, port


def unwrap_socks_udp(packet: bytes) -> tuple[bytes, str, int]:
    if len(packet) < 4 or packet[:2] != b"\x00\x00":
        raise SystemExit("Received an invalid SOCKS5 UDP packet")
    if packet[2] != 0:
        raise SystemExit("Fragmented SOCKS5 UDP responses are not supported")

    address_type = packet[3]
    offset = 4
    if address_type == 1:
        address_length = 4
        host = socket.inet_ntoa(packet[offset : offset + address_length])
    elif address_type == 3:
        address_length = packet[offset]
        offset += 1
        host = packet[offset : offset + address_length].decode()
    elif address_type == 4:
        address_length = 16
        host = socket.inet_ntop(socket.AF_INET6, packet[offset : offset + address_length])
    else:
        raise SystemExit(f"Received unknown SOCKS5 UDP address type {address_type}")

    offset += address_length
    if len(packet) < offset + 2:
        raise SystemExit("Received a truncated SOCKS5 UDP packet")
    port = struct.unpack("!H", packet[offset : offset + 2])[0]
    return packet[offset + 2 :], host, port


def send_direct(args: argparse.Namespace, payload: bytes) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(args.timeout)

    try:
        sock.sendto(payload, (args.host, args.port))
        response, peer = sock.recvfrom(65535)
    except socket.timeout as error:
        raise SystemExit(f"Timed out after {args.timeout:g}s waiting for UDP echo") from error

    if response != payload:
        raise SystemExit(
            f"Received an unexpected {len(response)}-byte response from {peer[0]}:{peer[1]}"
        )

    print(f"UDP echo succeeded via {peer[0]}:{peer[1]} ({len(response)} bytes)")


def send_socks5(args: argparse.Namespace, payload: bytes) -> None:
    try:
        proxy_host, proxy_port_text = args.socks5.rsplit(":", 1)
        proxy_port = int(proxy_port_text)
    except ValueError as error:
        raise SystemExit("--socks5 must use the form HOST:PORT") from error
    validate_port(proxy_port)

    username = os.environ.get("OXY_USER")
    password = os.environ.get("OXY_PASS")
    if username is None or password is None:
        raise SystemExit("Set OXY_USER and OXY_PASS before using --socks5")
    username_bytes = username.encode()
    password_bytes = password.encode()
    if not 1 <= len(username_bytes) <= 255 or not 1 <= len(password_bytes) <= 255:
        raise SystemExit("SOCKS5 username and password must each be 1-255 bytes")

    try:
        control = socket.create_connection((proxy_host, proxy_port), args.timeout)
        control.settimeout(args.timeout)
        control.sendall(b"\x05\x01\x02")
        if receive_exact(control, 2) != b"\x05\x02":
            raise SystemExit("SOCKS5 server did not accept username/password authentication")

        control.sendall(
            b"\x01"
            + bytes([len(username_bytes)])
            + username_bytes
            + bytes([len(password_bytes)])
            + password_bytes
        )
        if receive_exact(control, 2) != b"\x01\x00":
            raise SystemExit("SOCKS5 authentication failed")

        control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
        version, reply, reserved = receive_exact(control, 3)
        if version != 5 or reserved != 0:
            raise SystemExit("SOCKS5 server returned an invalid UDP ASSOCIATE response")
        if reply != 0:
            raise SystemExit(f"SOCKS5 UDP ASSOCIATE rejected with code {reply}")
        relay_host, relay_port = receive_socks_address(control)
        if relay_host == "0.0.0.0":
            relay_host = control.getpeername()[0]

        target_ip = socket.gethostbyname(args.host)
        request = (
            b"\x00\x00\x00\x01"
            + socket.inet_aton(target_ip)
            + struct.pack("!H", args.port)
            + payload
        )
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.settimeout(args.timeout)
        print(
            f"SOCKS5 UDP relay {relay_host}:{relay_port}; "
            f"target {target_ip}:{args.port}"
        )
        udp.sendto(request, (relay_host, relay_port))
        packet, peer = udp.recvfrom(65535)
        response, response_host, response_port = unwrap_socks_udp(packet)
    except socket.timeout as error:
        raise SystemExit(
            f"Timed out after {args.timeout:g}s waiting for SOCKS5 UDP echo"
        ) from error

    if response != payload:
        raise SystemExit(
            f"Received an unexpected {len(response)}-byte UDP response "
            f"from {response_host}:{response_port}"
        )
    print(
        f"SOCKS5 UDP echo succeeded from {response_host}:{response_port} "
        f"via relay {peer[0]}:{peer[1]} ({len(response)} bytes)"
    )


def send(args: argparse.Namespace) -> None:
    payload = f"{args.token}:{secrets.token_hex(16)}".encode()
    if args.socks5:
        send_socks5(args, payload)
    else:
        send_direct(args, payload)


def main() -> None:
    args = parse_args()
    validate_port(args.port)

    if args.command == "serve":
        serve(args)
    else:
        send(args)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
