export interface Env {
  SYNC_CHANNEL: DurableObjectNamespace;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response(
        JSON.stringify({
          status: "ok",
          service: "mynotch-cloud-relay",
          version: "1.0.0",
          protocol: "e2ee-websocket",
          time: new Date().toISOString()
        }),
        {
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        }
      );
    }

    // WebSocket sync endpoint: /ws?channel=<id>&auth=<token>
    if (url.pathname === "/ws") {
      const upgradeHeader = request.headers.get("Upgrade");
      if (!upgradeHeader || upgradeHeader.toLowerCase() !== "websocket") {
        return new Response("Expected WebSocket Upgrade header", { status: 426 });
      }

      const channelId = url.searchParams.get("channel");
      const auth = url.searchParams.get("auth");

      if (!channelId || !auth || channelId.length < 8 || auth.length < 8) {
        return new Response("Missing or invalid channel/auth parameter", { status: 400 });
      }

      // Route to Durable Object unique to this channel
      const id = env.SYNC_CHANNEL.idFromName(channelId);
      const stub = env.SYNC_CHANNEL.get(id);

      return stub.fetch(request);
    }

    return new Response("Not Found", { status: 404 });
  }
};

export class SyncChannel implements DurableObject {
  state: DurableObjectState;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const auth = url.searchParams.get("auth") || "";
    const sender = url.searchParams.get("sender") || "unknown";

    // Validate channel auth using persistent storage
    let channelAuth = await this.state.storage.get<string>("channelAuth");
    if (!channelAuth) {
      await this.state.storage.put("channelAuth", auth);
    } else if (channelAuth !== auth) {
      console.warn(`[Relay] Unauthorized token for sender: ${sender}`);
      return new Response("Unauthorized channel token", { status: 401 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Accept WebSocket connection and attach sender metadata
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ senderId: sender, connectedAt: Date.now() });

    console.log(`[Relay] Client connected: sender=${sender}, totalSockets=${this.state.getWebSockets().length}`);

    // Send latest encrypted snapshot to newly connected client if available
    const lastSnapshot = await this.state.storage.get<string>("lastSnapshot");
    if (lastSnapshot) {
      try {
        server.send(lastSnapshot);
        console.log(`[Relay] Sent cached snapshot to new client: sender=${sender}`);
      } catch (err) {
        console.error("Failed to send initial snapshot", err);
      }
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      // Enforce max payload limit of 2MB
      const byteLength = typeof message === "string" ? new TextEncoder().encode(message).length : message.byteLength;
      if (byteLength > 2 * 1024 * 1024) {
        ws.send(JSON.stringify({ error: "Payload too large (> 2MB)", code: 413 }));
        return;
      }

      const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
      const parsed = JSON.parse(raw);

      // Heartbeat ping
      if (parsed.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", timestamp: Date.now() }));
        return;
      }

      // Manual snapshot pull request
      if (parsed.type === "pull") {
        const lastSnapshot = await this.state.storage.get<string>("lastSnapshot");
        if (lastSnapshot) {
          ws.send(lastSnapshot);
        }
        return;
      }

      // Validate envelope structure
      if (parsed.type === "clip" && parsed.ciphertext && parsed.nonce && parsed.tag) {
        await this.state.storage.put("lastSnapshot", raw);

        const allSockets = this.state.getWebSockets();
        let relayedCount = 0;
        for (const session of allSockets) {
          if (session !== ws) {
            try {
              session.send(raw);
              relayedCount++;
            } catch (err) {
              console.error("[Relay] Failed to relay message to peer", err);
            }
          }
        }
        console.log(`[Relay] Broadcasted clip to ${relayedCount} peers (total active: ${allSockets.length})`);
      }
    } catch (err) {
      console.error("[Relay] Error handling webSocketMessage", err);
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): Promise<void> {
    const attachment = ws.deserializeAttachment() as { senderId?: string } | null;
    console.log(`[Relay] Client disconnected: sender=${attachment?.senderId ?? "unknown"}, remaining=${this.state.getWebSockets().length - 1}`);
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    console.error("[Relay] WebSocket error:", error);
  }
}
