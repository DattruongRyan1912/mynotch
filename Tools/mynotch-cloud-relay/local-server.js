// Standalone Node.js WebSocket Relay Server for local testing (Port 8787)
const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8787;
const channels = new Map(); // channelId -> { auth: string, sessions: Set<WebSocket>, lastSnapshot: string | null }

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === "/" || url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", service: "mynotch-local-relay", port: PORT }));
    return;
  }
  res.writeHead(404);
  res.end("Not Found");
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  if (url.pathname === "/ws") {
    const channelId = url.searchParams.get("channel");
    const auth = url.searchParams.get("auth");

    if (!channelId || !auth || channelId.length < 8 || auth.length < 8) {
      socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      socket.destroy();
      return;
    }

    let channel = channels.get(channelId);
    if (!channel) {
      channel = { auth, sessions: new Set(), lastSnapshot: null };
      channels.set(channelId, channel);
    } else if (channel.auth !== auth) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }

    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request, channel);
    });
  } else {
    socket.destroy();
  }
});

wss.on("connection", (ws, request, channel) => {
  channel.sessions.add(ws);
  console.log(`[Relay] New peer connected. Total in channel: ${channel.sessions.size}`);

  if (channel.lastSnapshot) {
    try {
      ws.send(channel.lastSnapshot);
    } catch (e) {}
  }

  ws.on("message", (data) => {
    try {
      const raw = data.toString();
      const parsed = JSON.parse(raw);

      if (parsed.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", timestamp: Date.now() }));
        return;
      }

      if (parsed.type === "pull") {
        if (channel.lastSnapshot) ws.send(channel.lastSnapshot);
        return;
      }

      if (parsed.type === "clip") {
        channel.lastSnapshot = raw;
        for (const peer of channel.sessions) {
          if (peer !== ws && peer.readyState === 1) {
            peer.send(raw);
          }
        }
      }
    } catch (err) {
      console.error("[Relay] Error handling message", err);
    }
  });

  ws.on("close", () => {
    channel.sessions.delete(ws);
    console.log(`[Relay] Peer disconnected. Remaining: ${channel.sessions.size}`);
  });
});

server.listen(PORT, () => {
  console.log(`🚀 MyNotch WebSocket Relay listening on http://localhost:${PORT}`);
  console.log(`📡 WebSocket endpoint: ws://localhost:${PORT}/ws?channel=<id>&auth=<token>`);
});
