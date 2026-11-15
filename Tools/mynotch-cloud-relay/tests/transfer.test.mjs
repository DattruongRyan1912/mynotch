import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execSync } from "node:child_process";
import { WebSocket } from "ws";
import { server, channels } from "../local-server.js";

// Helper to start the production server on an ephemeral port
async function setupServer() {
  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;
  return {
    port,
    close: () => new Promise((resolve) => {
      for (const ch of channels.values()) {
        for (const s of ch.sessions) {
          try { s.terminate(); } catch (_) {}
        }
      }
      if (typeof server.closeAllConnections === "function") {
        server.closeAllConnections();
      }
      server.close(resolve);
    })
  };
}

test("T18a: Relay health check endpoint returns 200 OK", async () => {
  const { port, close } = await setupServer();
  try {
    const res = await fetch(`http://localhost:${port}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, "ok");
    assert.equal(body.service, "mynotch-local-relay");
  } finally {
    await close();
  }
});

test("T18b: Relay rejects malformed and unauthorized channel connections", async () => {
  const { port, close } = await setupServer();
  try {
    // 1. Missing or short channelId (< 8 chars) -> 400
    const wsBad = new WebSocket(`ws://localhost:${port}/ws?channel=short&auth=valid-token-1234`);
    const statusBad = await new Promise((resolve) => {
      wsBad.on("unexpected-response", (req, res) => resolve(res.statusCode));
      wsBad.on("error", () => {});
    });
    assert.equal(statusBad, 400);

    // 2. Connect client 1 with auth-token-A
    const channelId = "auth-test-channel-12345";
    const tokenA = "auth-token-A-12345";
    const ws1 = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${tokenA}`);
    await new Promise((resolve, reject) => {
      ws1.on("open", resolve);
      ws1.on("error", reject);
    });

    // 3. Connect client 2 to same channel with wrong auth-token-B -> rejected 401
    const wsWrong = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=wrong-token-B-12345`);
    const statusWrong = await new Promise((resolve) => {
      wsWrong.on("unexpected-response", (req, res) => resolve(res.statusCode));
      wsWrong.on("error", () => {});
    });
    assert.equal(statusWrong, 401);

    ws1.close();
  } finally {
    await close();
  }
});

test("T18c: v1 clip messages cache lastSnapshot and replay to new peers", async () => {
  const { port, close } = await setupServer();
  try {
    const channelId = "v1-replay-channel-12345";
    const auth = "test-auth-12345";

    const wsA = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    await new Promise((r) => wsA.on("open", r));

    // Send v1 clip from A
    const v1Msg = JSON.stringify({ type: "clip", v: 1, ciphertext: "cipher1", nonce: "nonce1", tag: "tag1" });
    wsA.send(v1Msg);

    // Give server a tick to process
    await new Promise((r) => setTimeout(r, 50));

    // Client B connects afterwards: must immediately receive cached snapshot
    const wsB = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    const receivedB = await new Promise((resolve) => {
      wsB.on("message", (data) => resolve(data.toString()));
    });

    assert.equal(receivedB, v1Msg);

    wsA.close();
    wsB.close();
  } finally {
    await close();
  }
});

test("T18d: v2 clip messages forward directly and are NEVER cached in lastSnapshot", async () => {
  const { port, close } = await setupServer();
  try {
    const channelId = "v2-nocache-channel-12345";
    const auth = "test-auth-12345";

    const wsA = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    const wsB = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    await Promise.all([
      new Promise((r) => wsA.on("open", r)),
      new Promise((r) => wsB.on("open", r))
    ]);

    // Send v2 clip from A -> B must receive it
    const v2Msg = JSON.stringify({
      type: "clip_v2",
      v: 2,
      id: "uuid-123",
      senderId: "mac",
      timestamp: Date.now(),
      nonce: "MTIzNDU2Nzg5MDEy",
      tag: "MDEyMzQ1Njc4OTAxMjM0NQ==",
      ciphertext: "YWJj"
    });
    const bPromise = new Promise((resolve) => {
      wsB.on("message", (data) => resolve(data.toString()));
    });
    wsA.send(v2Msg);
    const receivedByB = await bPromise;
    assert.equal(receivedByB, v2Msg);

    // Verify channel.lastSnapshot is still null (v2 is ephemeral)
    const channelObj = channels.get(channelId);
    assert.equal(channelObj.lastSnapshot, null);

    // Client C connects after transfer: must NOT receive any v2 clip
    let receivedByC = null;
    const wsC = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    wsC.on("message", (data) => { receivedByC = data.toString(); });
    await new Promise((r) => wsC.on("open", r));
    await new Promise((r) => setTimeout(r, 100));

    assert.equal(receivedByC, null, "v2 clip must not be replayed to newly connected peers");

    wsA.close();
    wsB.close();
    wsC.close();
  } finally {
    await close();
  }
});

test("T19: Wire payload limit (messages > 2 MiB closed with code 1009)", async () => {
  const { port, close } = await setupServer();
  try {
    const channelId = "ceiling-channel-12345";
    const auth = "test-auth-12345";

    const ws = new WebSocket(`ws://localhost:${port}/ws?channel=${channelId}&auth=${auth}`);
    await new Promise((r) => ws.on("open", r));

    // Send oversized message (2.1 MiB)
    const oversized = Buffer.alloc(2.1 * 1024 * 1024, "A");
    const closePromise = new Promise((resolve) => {
      ws.on("close", (code, reason) => resolve({ code, reason: reason.toString() }));
    });
    ws.send(oversized);

    const { code, reason } = await closePromise;
    assert.equal(code, 1009);
    assert.ok(reason.includes("Payload too large"));
  } finally {
    await close();
  }
});

test("T19b: Cloudflare Worker runtime parity (src/index.ts under Wrangler)", async () => {
  const { unstable_dev } = await import("wrangler");
  const worker = await unstable_dev("src/index.ts", {
    experimental: { disableExperimentalWarning: true },
    logLevel: "error"
  });

  try {
    // 1. Health endpoint on Worker runtime returns 200 OK
    const healthResp = await worker.fetch("/health");
    assert.equal(healthResp.status, 200);
    const healthJson = await healthResp.json();
    assert.equal(healthJson.status, "ok");
    assert.equal(healthJson.service, "mynotch-cloud-relay");
    assert.equal(healthJson.protocol, "e2ee-websocket");

    // 2. Reject missing WebSocket Upgrade header on /ws with 426
    const noUpgradeResp = await worker.fetch("/ws?channel=testchannel123&auth=testauth123");
    assert.equal(noUpgradeResp.status, 426);
    const noUpgradeText = await noUpgradeResp.text();
    assert.ok(noUpgradeText.includes("Expected WebSocket Upgrade header"));

    // 3. Fallback 404 for unknown paths
    const notFoundResp = await worker.fetch("/unknown-route");
    assert.equal(notFoundResp.status, 404);

    // 4. Real WebSocket bi-directional forwarding on Worker runtime
    const port = worker.port;
    const channel = "worker_parity_channel_" + Date.now();
    const auth = "secret_auth_token_12345";
    const wsUrlMac = `ws://127.0.0.1:${port}/ws?channel=${channel}&auth=${auth}&sender=macbook`;
    const wsUrlAndroid = `ws://127.0.0.1:${port}/ws?channel=${channel}&auth=${auth}&sender=android`;

    const wsMac = new WebSocket(wsUrlMac);
    const wsAndroid = new WebSocket(wsUrlAndroid);

    await Promise.all([
      new Promise((res, rej) => { wsMac.onopen = res; wsMac.onerror = rej; }),
      new Promise((res, rej) => { wsAndroid.onopen = res; wsAndroid.onerror = rej; })
    ]);

    // Test V2 Envelope Forwarding and Echo Suppression
    let macReceivedEcho = false;
    wsMac.onmessage = () => { macReceivedEcho = true; };

    const v2Envelope = {
      type: "clip_v2",
      senderId: "macbook",
      timestamp: Date.now(),
      ciphertext: "c4ca4238a0b923820dcc509a6f75849b",
      nonce: "c81e728d9d4c2f636f067f89cc14862c",
      tag: "eccbc87e4b5ce2fe28308fd9f2a7baf3"
    };

    const androidMsgPromise = new Promise((resolve) => {
      wsAndroid.onmessage = (evt) => {
        resolve(JSON.parse(evt.data));
      };
    });

    wsMac.send(JSON.stringify(v2Envelope));
    const receivedByAndroid = await androidMsgPromise;
    assert.equal(receivedByAndroid.type, "clip_v2");
    assert.equal(receivedByAndroid.senderId, "macbook");
    assert.equal(receivedByAndroid.ciphertext, v2Envelope.ciphertext);

    // Small delay to ensure no echo delivered to mac
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(macReceivedEcho, false, "Mac must not receive echo of its own V2 envelope");

    // 5. Test V2 does NOT cache snapshot for newly connecting peers
    const wsLate = new WebSocket(`ws://127.0.0.1:${port}/ws?channel=${channel}&auth=${auth}&sender=late_peer`);
    let lateReceivedMessage = false;
    wsLate.onmessage = () => { lateReceivedMessage = true; };
    await new Promise((res, rej) => { wsLate.onopen = res; wsLate.onerror = rej; });
    await new Promise((r) => setTimeout(r, 60));
    assert.equal(lateReceivedMessage, false, "Late connecting peer must NOT receive snapshot for v2 clips");
    wsLate.close();

    // 6. Test 2 MiB payload ceiling enforcement on Worker runtime
    const hugePayload = JSON.stringify({
      type: "clip_v2",
      senderId: "macbook",
      ciphertext: "x".repeat(2 * 1024 * 1024 + 100),
      nonce: "nonce",
      tag: "tag"
    });

    const closePromise = new Promise((resolve, reject) => {
      wsMac.onclose = (evt) => resolve(evt.code);
      wsMac.onerror = (err) => reject(new Error("Unexpected error event on WebSocket: " + err));
    });
    wsMac.send(hugePayload);
    const closeCode = await closePromise;
    assert.equal(closeCode, 1009, `Server must close socket with code 1009 for payloads > 2MB, got ${closeCode}`);

    wsAndroid.close();
  } finally {
    await worker.stop();
  }
});

test("T19c: Bi-directional V2 multi-format chunked flow control and ACK verification", async () => {
  const { port, close } = await setupServer();
  try {
    const channel = "bidirectional-e2e-" + Date.now();
    const auth = "auth-token-e2e-12345";
    const key = crypto.randomBytes(32);

    const wsMac = new WebSocket(`ws://localhost:${port}/ws?channel=${channel}&auth=${auth}&sender=macbook`);
    const wsAndroid = new WebSocket(`ws://localhost:${port}/ws?channel=${channel}&auth=${auth}&sender=android`);

    await Promise.all([
      new Promise((r) => wsMac.on("open", r)),
      new Promise((r) => wsAndroid.on("open", r))
    ]);

    function encryptV2(payloadObj, senderId) {
      const now = Date.now();
      const id = crypto.randomUUID();
      const aad = `mynotch\nclip_v2\n2\n${id}\n${senderId}\n${now}`;
      const nonce = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
      cipher.setAAD(Buffer.from(aad, "utf-8"));
      const ciphertext = Buffer.concat([cipher.update(Buffer.from(JSON.stringify(payloadObj), "utf-8")), cipher.final()]);
      const tag = cipher.getAuthTag();
      return JSON.stringify({
        type: "clip_v2",
        v: 2,
        id,
        senderId,
        timestamp: now,
        nonce: nonce.toString("base64"),
        tag: tag.toString("base64"),
        ciphertext: ciphertext.toString("base64")
      });
    }

    function decryptV2(envelopeStr) {
      const env = JSON.parse(envelopeStr);
      const aad = `mynotch\nclip_v2\n2\n${env.id}\n${env.senderId}\n${env.timestamp}`;
      const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(env.nonce, "base64"));
      decipher.setAAD(Buffer.from(aad, "utf-8"));
      decipher.setAuthTag(Buffer.from(env.tag, "base64"));
      const decrypted = Buffer.concat([decipher.update(Buffer.from(env.ciphertext, "base64")), decipher.final()]);
      return JSON.parse(decrypted.toString("utf-8"));
    }

    // Step 1: Mac sends chunk 0 of 2 to Android
    const transferId = "xfer-e2e-999";
    const fileBytes = Buffer.from("Hello CloudSync V2 End-To-End Verification Stream!");
    const fileHash = crypto.createHash("sha256").update(fileBytes).digest("hex");
    const half = Math.floor(fileBytes.length / 2);
    const chunk0 = fileBytes.subarray(0, half);
    const chunk1 = fileBytes.subarray(half);

    let androidReceivedChunks = [];
    let completeAckReceivedByMac = null;
    let chunkAckReceivedByMac = null;

    wsAndroid.on("message", (data) => {
      const msg = decryptV2(data.toString());
      if (msg.kind === "file_chunk") {
        androidReceivedChunks.push(msg);
        // Reply with chunk_ack
        const ack = encryptV2({
          kind: "chunk_ack",
          transfer_id: msg.transfer_id,
          sequence: msg.sequence,
          status: "ok"
        }, "android");
        wsAndroid.send(ack);

        // If all chunks received, assemble and send complete_ack
        if (msg.sequence === msg.total_chunks - 1) {
          const assembled = Buffer.concat(androidReceivedChunks.map((c) => Buffer.from(c.content_base64, "base64")));
          const assembledHash = crypto.createHash("sha256").update(assembled).digest("hex");
          assert.equal(assembledHash, fileHash);
          const comp = encryptV2({
            kind: "complete_ack",
            transfer_id: msg.transfer_id,
            file_hash: assembledHash,
            status: "success",
            timestamp: Date.now()
          }, "android");
          wsAndroid.send(comp);
        }
      }
    });

    wsMac.on("message", (data) => {
      const msg = decryptV2(data.toString());
      if (msg.kind === "chunk_ack") {
        chunkAckReceivedByMac = msg;
      } else if (msg.kind === "complete_ack") {
        completeAckReceivedByMac = msg;
      }
    });

    // Send chunk 0
    wsMac.send(encryptV2({
      kind: "file_chunk",
      transfer_id: transferId,
      sequence: 0,
      total_chunks: 2,
      file_hash: fileHash,
      content_base64: chunk0.toString("base64")
    }, "macbook"));

    // Wait for chunk_ack(0) before sending chunk 1 (Window = 1 Flow Control)
    for (let i = 0; i < 30 && !chunkAckReceivedByMac; i++) {
      await new Promise((r) => setTimeout(r, 20));
    }
    assert.ok(chunkAckReceivedByMac, "Mac must receive chunk_ack for chunk 0");
    assert.equal(chunkAckReceivedByMac.sequence, 0);

    // Now send chunk 1
    wsMac.send(encryptV2({
      kind: "file_chunk",
      transfer_id: transferId,
      sequence: 1,
      total_chunks: 2,
      file_hash: fileHash,
      content_base64: chunk1.toString("base64")
    }, "macbook"));

    // Wait for complete_ack
    for (let i = 0; i < 30 && !completeAckReceivedByMac; i++) {
      await new Promise((r) => setTimeout(r, 20));
    }
    assert.ok(completeAckReceivedByMac, "Mac must receive complete_ack");
    assert.equal(completeAckReceivedByMac.status, "success");
    assert.equal(completeAckReceivedByMac.file_hash, fileHash);

    wsMac.close();
    wsAndroid.close();
  } finally {
    await close();
  }
});

// --- Helpers for T19d Live E2E ---
const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../..");
const EVIDENCE_DIR = path.join(REPO_ROOT, "docs", "evidence", "cloud-sync-v2");

function makeValidPdf() {
  return Buffer.from(
    "%PDF-1.4\n" +
    "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n" +
    "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n" +
    "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R >>\nendobj\n" +
    "4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 12 Tf 20 100 Td (MyNotch CloudSync V2) Tj ET\nendstream\nendobj\n" +
    "xref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000206 00000 n \n" +
    "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n300\n%%EOF\n"
  );
}

function makeValidPng() {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.from([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1f, 0x15, 0xc4, 0x89]);
  const idat = Buffer.from([0, 0, 0, 10, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4]);
  const iend = Buffer.from([0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);
  return Buffer.concat([sig, ihdr, idat, iend]);
}

function makeValidZip() {
  return Buffer.from([
    0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  ]);
}

function makeValidDocx() {
  const b64 = "UEsDBBQAAAAIACA8aV2i7cddawAAAHMAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbBWMwQ3CMAwAV4n8bx14IISa9scEZYAomLSC2FFsIdie8Dzd6ablU17uTU134QCH0YMjTnLfOQe4rdfhDMs8rd9K6nrKGmAzqxdETRuVqKNU4m4e0kq0ji1jjekZM+HR+xMmYSO2wf4PwPkHUEsDBBQAAAAIACA8aV025mK9lAAAAMIAAAARAAAAd29yZC9kb2N1bWVudC54bWxFjr0OwjAMhF8lyk5dOiBU9WdjgwnYSxLaSo0dOYHQtycpA8t3Ot355Kb/2EW8DfuZsJX7opTCoCI949jK2/W0O8q+a2KtSb2swSBSH30dWzmF4GoAryZjB1+QM5iyJ7EdQrI8QiTWjkkZ79OcXaAqywPYYUaZJx+k16wugzNCd14vFNQk7lUD2WfyRrfxdwP/f7ovUEsBAhQDFAAAAAgAIDxpXaLtx11rAAAAcwAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAgPGldNuZivZQAAADCAAAAEQAAAAAAAAAAAAAAgAGcAAAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAIAAgCAAAAAXwEAAAAA";
  return Buffer.from(b64, "base64");
}

function makeChunkedData(bytesCount = 1200000) {
  const buf = Buffer.alloc(bytesCount);
  for (let i = 0; i < bytesCount; i++) {
    buf[i] = (i % 251);
  }
  return buf;
}

test("T19d: Live End-to-End Bidirectional File Transfer & FileProvider Verification", async (t) => {
  // FAIL-CLOSED: No t.skip(). Must have a live Android device/emulator connected
  let devicesOut = "";
  try {
    devicesOut = execSync("adb devices", { encoding: "utf8" });
  } catch (e) {
    assert.fail(`ADB execution failed: ${e.message}`);
  }

  const deviceLines = devicesOut.split("\n").filter((l) => l.includes("\tdevice"));
  assert.ok(deviceLines.length > 0, "FAIL-CLOSED: At least one live Android device/emulator must be connected and authorized for T19d");
  const serial = deviceLines[0].split("\t")[0].trim();
  console.log(`[T19d E2E] Testing with live Android device: ${serial}`);

  const { port, close } = await setupServer();
  const channelId = "e2e_channel_99999";
  const authToken = "e2e_auth_99999";
  const aesKeyB64 = "y/E8w9oG+8GvC7mD+KxK9b1s8VqfO7N7k1x2y3z4w5E=";
  const aesKeyBytes = Buffer.from(aesKeyB64, "base64");

  function computeAad(id, senderId, timestamp) {
    return Buffer.from(`mynotch\nclip_v2\n2\n${id}\n${senderId}\n${timestamp}`, "utf8");
  }

  function encryptMsg(payloadObj, senderId = "macbook") {
    const now = Date.now();
    const id = crypto.randomUUID().toLowerCase();
    const nonce = crypto.randomBytes(12);
    const aad = computeAad(id, senderId, now);

    const cipher = crypto.createCipheriv("aes-256-gcm", aesKeyBytes, nonce);
    cipher.setAAD(aad);

    const plaintext = Buffer.from(JSON.stringify(payloadObj), "utf8");
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const tag = cipher.getAuthTag();

    return JSON.stringify({
      type: "clip_v2",
      v: 2,
      id,
      senderId,
      timestamp: now,
      nonce: nonce.toString("base64"),
      tag: tag.toString("base64"),
      ciphertext: ciphertext.toString("base64")
    });
  }

  function decryptMsg(envelopeStr) {
    const env = JSON.parse(envelopeStr);
    const aad = computeAad(env.id, env.senderId, env.timestamp);
    const nonce = Buffer.from(env.nonce, "base64");
    const tag = Buffer.from(env.tag, "base64");
    const ciphertext = Buffer.from(env.ciphertext, "base64");

    const decipher = crypto.createDecipheriv("aes-256-gcm", aesKeyBytes, nonce);
    decipher.setAAD(aad);
    decipher.setAuthTag(tag);

    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return JSON.parse(decrypted.toString("utf8"));
  }

  let macWs = null;
  try {
    // 2. Pair Android app with test credentials pointing to ws://10.0.2.2:<port>/ws
    console.log(`[T19d] Pairing Android app on ${serial}...`);
    execSync(`adb -s '${serial}' shell am force-stop io.lucasvu.mynotch.mynotch_android`);
    const pairUrl = `mynotch://pair?c=${channelId}&k=${authToken}&e=${encodeURIComponent(aesKeyB64)}&s=ws://10.0.2.2:${port}/ws`;
    execSync(`adb -s '${serial}' shell 'am start -a android.intent.action.VIEW -d "${pairUrl}" -n io.lucasvu.mynotch.mynotch_android/.MainActivity'`);
    await new Promise((r) => setTimeout(r, 2500));

    // 3. Connect Mac client
    const wsUrl = `ws://localhost:${port}/ws?channel=${channelId}&auth=${authToken}&sender=macbook`;
    macWs = new WebSocket(wsUrl);

    const macSessionId = crypto.randomUUID().toLowerCase();
    let androidSessionId = null;
    const incomingCompleteAcks = new Map();
    const incomingChunkAcks = new Set();
    const incomingErrors = new Map();
    const receivedAndroidFiles = [];

    macWs.on("message", (data) => {
      try {
        const payload = decryptMsg(data.toString());
        if (payload.kind === "hello") {
          androidSessionId = payload.session_id;
          macWs.send(encryptMsg({
            kind: "ready",
            session_id: macSessionId,
            peer_session_id: androidSessionId,
            senderId: "macbook",
            timestamp: Date.now()
          }, "macbook"));
        } else if (payload.kind === "ready") {
          androidSessionId = payload.session_id;
        } else if (payload.kind === "chunk_ack") {
          incomingChunkAcks.add(`${payload.transfer_id}_${payload.sequence}`);
        } else if (payload.kind === "complete_ack") {
          incomingCompleteAcks.set(payload.transfer_id, payload);
        } else if (payload.kind === "error") {
          incomingErrors.set(payload.transfer_id, payload);
        } else if (payload.kind === "file" || payload.kind === "file_chunk" || payload.kind === "image") {
          receivedAndroidFiles.push(payload);
          if (payload.kind === "file_chunk") {
            macWs.send(encryptMsg({
              kind: "chunk_ack",
              transfer_id: payload.transfer_id,
              sequence: payload.sequence,
              status: "ok"
            }, "macbook"));
          }
          if (payload.kind === "file" || payload.kind === "image" || payload.sequence === (payload.total_chunks - 1)) {
            macWs.send(encryptMsg({
              kind: "complete_ack",
              transfer_id: payload.transfer_id,
              sender_session_id: payload.sender_session_id,
              receiver_session_id: macSessionId,
              file_hash: payload.file_hash,
              status: "success",
              timestamp: Date.now()
            }, "macbook"));
          }
        }
      } catch (_) {}
    });

    await new Promise((resolve, reject) => {
      macWs.on("open", resolve);
      macWs.on("error", reject);
    });

    macWs.send(encryptMsg({
      kind: "hello",
      session_id: macSessionId,
      senderId: "macbook",
      timestamp: Date.now()
    }, "macbook"));

    for (let i = 0; i < 20; i++) {
      if (androidSessionId) break;
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.ok(androidSessionId, "Handshake failed: Android session ID not received");
    console.log(`[T19d] Handshake verified: Mac Session=${macSessionId}, Android Session=${androidSessionId}`);

    // 4. Direction 1: Mac -> Android (PDF, DOCX, ZIP, PNG, 1.2 MiB Chunked, and Exact 15 MiB Boundary)
    const samples = [
      { name: "e2e_document.pdf", mime: "application/pdf", data: makeValidPdf(), isImage: false, isChunked: false },
      { name: "e2e_proposal.docx", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", data: makeValidDocx(), isImage: false, isChunked: false },
      { name: "e2e_archive.zip", mime: "application/zip", data: makeValidZip(), isImage: false, isChunked: false },
      { name: "e2e_snapshot.png", mime: "image/png", data: makeValidPng(), isImage: true, isChunked: false },
      { name: "chunked_sample.bin", mime: "application/octet-stream", data: makeChunkedData(1200000), isImage: false, isChunked: true },
      { name: "boundary_15mib.bin", mime: "application/octet-stream", data: makeChunkedData(15728640), isImage: false, isChunked: true }
    ];

    const results = {};
    let savedPdfTransferId = null;
    let savedDocxTransferId = null;
    let savedZipTransferId = null;
    let savedPngName = null;
    let savedChunkedTransferId = null;
    let saved15MibTransferId = null;

    for (const sample of samples) {
      const transferId = crypto.randomUUID().toLowerCase();
      if (sample.name === "e2e_document.pdf") savedPdfTransferId = transferId;
      if (sample.name === "e2e_proposal.docx") savedDocxTransferId = transferId;
      if (sample.name === "e2e_archive.zip") savedZipTransferId = transferId;
      if (sample.name === "e2e_snapshot.png") savedPngName = sample.name;
      if (sample.name === "chunked_sample.bin") savedChunkedTransferId = transferId;
      if (sample.name === "boundary_15mib.bin") saved15MibTransferId = transferId;

      const fileHash = crypto.createHash("sha256").update(sample.data).digest("hex");
      console.log(`[T19d] Mac sending ${sample.name} (${sample.data.length} bytes, chunked=${sample.isChunked})...`);

      if (!sample.isChunked) {
        // Single inline envelope (<= 1 MiB)
        const payload = {
          kind: sample.isImage ? "image" : "file",
          transfer_id: transferId,
          sender_session_id: macSessionId,
          receiver_session_id: androidSessionId,
          file_name: sample.name,
          mime_type: sample.mime,
          file_size: sample.data.length,
          file_hash: fileHash,
          sequence: 0,
          total_chunks: 1,
          content_base64: sample.data.toString("base64"),
          sourceApp: "MacBookPro",
          timestamp: Date.now()
        };
        macWs.send(encryptMsg(payload, "macbook"));

        let ack = null;
        for (let i = 0; i < 40; i++) {
          ack = incomingCompleteAcks.get(transferId);
          if (ack) break;
          await new Promise((r) => setTimeout(r, 250));
        }
        assert.ok(ack, `Timeout waiting for complete_ack for ${sample.name}`);
        assert.equal(ack.status, "success");
        assert.equal(ack.file_hash, fileHash);
        assert.equal(ack.sender_session_id, macSessionId);
        console.log(`  ✔ Verified complete_ack for ${sample.name}`);
      } else {
        // Chunked transfer (> 1 MiB, 512 KiB chunks: 1.2 MiB = 3 chunks, 15 MiB = 30 chunks)
        const chunkSize = 524288;
        const totalChunks = Math.ceil(sample.data.length / chunkSize);
        const expectedChunks = sample.name === "boundary_15mib.bin" ? 30 : 3;
        assert.equal(totalChunks, expectedChunks, `Expected exactly ${expectedChunks} chunks for ${sample.data.length} bytes`);

        for (let seq = 0; seq < totalChunks; seq++) {
          const start = seq * chunkSize;
          const end = Math.min(start + chunkSize, sample.data.length);
          const chunkData = sample.data.subarray(start, end);

          const chunkPayload = {
            kind: "file_chunk",
            transfer_id: transferId,
            sender_session_id: macSessionId,
            receiver_session_id: androidSessionId,
            file_name: sample.name,
            mime_type: sample.mime,
            file_size: sample.data.length,
            file_hash: fileHash,
            sequence: seq,
            total_chunks: totalChunks,
            content_base64: chunkData.toString("base64"),
            sourceApp: "MacBookPro",
            timestamp: Date.now()
          };
          macWs.send(encryptMsg(chunkPayload, "macbook"));

          if (seq < totalChunks - 1) {
            // Flow Control: wait for chunk_ack for seq
            let acked = false;
            for (let i = 0; i < 40; i++) {
              if (incomingChunkAcks.has(`${transferId}_${seq}`)) {
                acked = true;
                break;
              }
              await new Promise((r) => setTimeout(r, 250));
            }
            assert.ok(acked, `Timeout waiting for chunk_ack(${seq}) for ${sample.name}`);
          }
        }

        // Wait for complete_ack for the assembled chunked file
        let ack = null;
        for (let i = 0; i < 40; i++) {
          ack = incomingCompleteAcks.get(transferId);
          if (ack) break;
          await new Promise((r) => setTimeout(r, 250));
        }
        assert.ok(ack, `Timeout waiting for complete_ack for chunked ${sample.name}`);
        assert.equal(ack.status, "success");
        assert.equal(ack.file_hash, fileHash);
        assert.equal(ack.sender_session_id, macSessionId);
        console.log(`  ✔ Verified complete_ack for chunked file ${sample.name} (${totalChunks} chunks reassembled)`);
      }

      // Verify backing storage on Android device via run-as sha256sum
      if (!sample.isImage) {
        const devReadCmd = `adb -s '${serial}' shell run-as io.lucasvu.mynotch.mynotch_android sha256sum 'files/sync_files/${transferId}/${sample.name}'`;
        const readOut = execSync(devReadCmd, { encoding: "utf8" }).trim();
        const readHash = readOut.split(/\s+/)[0];
        assert.equal(readHash, fileHash, `FileProvider backing store hash mismatch for ${sample.name}`);
        console.log(`  ✔ Android FileProvider backing file verified via run-as (SHA-256 match: ${readHash})`);

        // Test Anti-Replay: Send duplicate and verify file count remains exactly 1
        const dupPayload = {
          kind: sample.isChunked ? "file_chunk" : "file",
          transfer_id: transferId,
          sender_session_id: macSessionId,
          receiver_session_id: androidSessionId,
          file_name: sample.name,
          mime_type: sample.mime,
          file_size: sample.data.length,
          file_hash: fileHash,
          sequence: 0,
          total_chunks: sample.isChunked ? (sample.name === "boundary_15mib.bin" ? 30 : 3) : 1,
          content_base64: (sample.isChunked ? sample.data.subarray(0, 524288) : sample.data).toString("base64"),
          sourceApp: "MacBookPro",
          timestamp: Date.now()
        };
        macWs.send(encryptMsg(dupPayload, "macbook"));
        await new Promise((r) => setTimeout(r, 600));

        const countCheck = execSync(`adb -s '${serial}' shell run-as io.lucasvu.mynotch.mynotch_android "ls files/sync_files/${transferId} 2>/dev/null | wc -l"`, { encoding: "utf8" }).trim();
        assert.equal(countCheck, "1", `Anti-replay failed: expected 1 file, found ${countCheck}`);
        console.log(`  ✔ Anti-Replay Idempotency verified: duplicate ignored, exactly 1 file preserved`);
      } else {
        const devReadCmd = `adb -s '${serial}' shell run-as io.lucasvu.mynotch.mynotch_android sha256sum 'cache/sync_images/${sample.name}'`;
        const readOut = execSync(devReadCmd, { encoding: "utf8" }).trim();
        const readHash = readOut.split(/\s+/)[0];
        assert.equal(readHash, fileHash, `Image cache hash mismatch for ${sample.name}`);
        console.log(`  ✔ Android Image cache file verified via run-as (SHA-256 match: ${readHash})`);

        // Anti-Replay for Image: re-send duplicate image
        const dupImgPayload = {
          kind: "image",
          transfer_id: transferId,
          sender_session_id: macSessionId,
          receiver_session_id: androidSessionId,
          file_name: sample.name,
          mime_type: sample.mime,
          file_size: sample.data.length,
          file_hash: fileHash,
          sequence: 0,
          total_chunks: 1,
          content_base64: sample.data.toString("base64"),
          sourceApp: "MacBookPro",
          timestamp: Date.now()
        };
        macWs.send(encryptMsg(dupImgPayload, "macbook"));
        await new Promise((r) => setTimeout(r, 600));

        const imgCountCheck = execSync(`adb -s '${serial}' shell run-as io.lucasvu.mynotch.mynotch_android "ls cache/sync_images | grep '${sample.name}' | wc -l"`, { encoding: "utf8" }).trim();
        assert.equal(imgCountCheck, "1", `Anti-replay image failed: expected 1 file, found ${imgCountCheck}`);
        console.log(`  ✔ Anti-Replay Image verified: duplicate ignored, exactly 1 file in cache`);
      }

      results[sample.name] = {
        transfer_id: transferId,
        sha256: fileHash,
        bytes: sample.data.length,
        complete_ack_verified: true,
        file_provider_verified: true,
        anti_replay_verified: true
      };
    }

    // 4b. Negative Boundary Test 1: Max + 1 byte (15,728,641 bytes) MUST be rejected by Android
    console.log(`[T19d] Verifying negative max+1 (15,728,641 bytes) boundary rejection...`);
    const maxPlusOneTransferId = crypto.randomUUID().toLowerCase();
    const maxPlusOnePayload = {
      kind: "file_chunk",
      transfer_id: maxPlusOneTransferId,
      sender_session_id: macSessionId,
      receiver_session_id: androidSessionId,
      file_name: "negative_max_plus_one.bin",
      mime_type: "application/octet-stream",
      file_size: 15728641,
      file_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      sequence: 0,
      total_chunks: 31,
      content_base64: Buffer.alloc(1024).toString("base64"),
      sourceApp: "MacBookPro",
      timestamp: Date.now()
    };
    macWs.send(encryptMsg(maxPlusOnePayload, "macbook"));

    let maxPlusOneErr = null;
    for (let i = 0; i < 40; i++) {
      maxPlusOneErr = incomingErrors.get(maxPlusOneTransferId);
      if (maxPlusOneErr) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(maxPlusOneErr, "FAIL-CLOSED: Android MUST emit explicit error envelope when file_size exceeds 15 MiB limit");
    assert.ok(maxPlusOneErr.message.includes("15 MiB") || maxPlusOneErr.message.includes("exceeds maximum allowed limit"), `Expected size limit rejection message, got: ${maxPlusOneErr.message}`);
    assert.equal(incomingChunkAcks.has(`${maxPlusOneTransferId}_0`), false, "FAIL-CLOSED: Rejected chunk 0 must NOT receive chunk_ack");
    assert.equal(incomingCompleteAcks.has(maxPlusOneTransferId), false, "FAIL-CLOSED: Files exceeding 15 MiB limit (15,728,641 bytes) MUST NOT receive complete_ack");
    const maxPlusOneDirCheck = execSync(`adb -s '${serial}' shell 'run-as io.lucasvu.mynotch.mynotch_android sh -c "[ -d files/sync_files/${maxPlusOneTransferId} ] && echo EXISTS || echo NOT_EXISTS"'`, { encoding: "utf8" }).trim();
    assert.equal(maxPlusOneDirCheck, "NOT_EXISTS", "Backing storage must not create directory for rejected max+1 transfer");
    console.log(`  ✔ Verified negative max+1 (15,728,641 bytes) explicitly rejected with error: ${maxPlusOneErr.message}`);

    // 4c. Negative Boundary Test 2: Stream with mismatched declared size MUST be rejected
    console.log(`[T19d] Verifying stream size mismatch rejection...`);
    const mismatchStreamTransferId = crypto.randomUUID().toLowerCase();
    const declaredSize = 1048576; // 1 MiB declared
    const dummyHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    // Chunk 0: 600,000 bytes (within declared 1 MiB) -> accepted
    const mismatchChunk0 = {
      kind: "file_chunk",
      transfer_id: mismatchStreamTransferId,
      sender_session_id: macSessionId,
      receiver_session_id: androidSessionId,
      file_name: "mismatched_stream.bin",
      mime_type: "application/octet-stream",
      file_size: declaredSize,
      file_hash: dummyHash,
      sequence: 0,
      total_chunks: 2,
      content_base64: Buffer.alloc(600000, 0x41).toString("base64"),
      sourceApp: "MacBookPro",
      timestamp: Date.now()
    };
    macWs.send(encryptMsg(mismatchChunk0, "macbook"));

    let chunk0Acked = false;
    for (let i = 0; i < 40; i++) {
      if (incomingChunkAcks.has(`${mismatchStreamTransferId}_0`)) {
        chunk0Acked = true;
        break;
      }
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(chunk0Acked, "Chunk 0 (600,000 bytes <= 1,048,576 declared) must receive chunk_ack(0)");
    console.log(`  ✔ Chunk 0 accepted with chunk_ack(0) as expected`);

    // Chunk 1: 600,000 bytes -> cumulative 1,200,000 bytes > 1,048,576 declared -> rejected!
    const mismatchChunk1 = {
      kind: "file_chunk",
      transfer_id: mismatchStreamTransferId,
      sender_session_id: macSessionId,
      receiver_session_id: androidSessionId,
      file_name: "mismatched_stream.bin",
      mime_type: "application/octet-stream",
      file_size: declaredSize,
      file_hash: dummyHash,
      sequence: 1,
      total_chunks: 2,
      content_base64: Buffer.alloc(600000, 0x42).toString("base64"),
      sourceApp: "MacBookPro",
      timestamp: Date.now()
    };
    macWs.send(encryptMsg(mismatchChunk1, "macbook"));

    let mismatchErr = null;
    for (let i = 0; i < 40; i++) {
      mismatchErr = incomingErrors.get(mismatchStreamTransferId);
      if (mismatchErr) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(mismatchErr, "FAIL-CLOSED: Android MUST emit explicit error envelope when cumulative bytes exceed declared file_size");
    assert.ok(mismatchErr.message.includes("exceeds declared file size"), `Expected mismatch error message, got: ${mismatchErr.message}`);
    assert.equal(incomingChunkAcks.has(`${mismatchStreamTransferId}_1`), false, "FAIL-CLOSED: Oversized chunk 1 must NOT receive chunk_ack");
    assert.equal(incomingCompleteAcks.has(mismatchStreamTransferId), false, "FAIL-CLOSED: Cumulative chunk size exceeding declared file_size MUST NOT receive complete_ack");
    const mismatchFileCheck = execSync(`adb -s '${serial}' shell 'run-as io.lucasvu.mynotch.mynotch_android sh -c "[ -f files/sync_files/${mismatchStreamTransferId}/mismatched_stream.bin ] && echo EXISTS || echo NOT_EXISTS"'`, { encoding: "utf8" }).trim();
    assert.equal(mismatchFileCheck, "NOT_EXISTS", "Backing storage must not save completed file for mismatched stream");
    console.log(`  ✔ Verified stream size mismatch rejected with error: ${mismatchErr.message}`);

    // 5. Direction 2: Android -> Mac via FileProvider ContentResolver & ClipSendActivity (5 formats: PDF, DOCX, ZIP, PNG, Chunked Binary)
    console.log(`[T19d] Testing Direction 2: Android sending 5 formats (PDF, DOCX, ZIP, PNG, Chunked Binary) to Mac via ClipSendActivity...`);
    assert.ok(savedPdfTransferId, "Saved PDF transferId must exist");
    assert.ok(savedDocxTransferId, "Saved DOCX transferId must exist");
    assert.ok(savedZipTransferId, "Saved ZIP transferId must exist");
    assert.ok(savedPngName, "Saved PNG name must exist");
    assert.ok(savedChunkedTransferId, "Saved Chunked transferId must exist");

    // 5a. Verify FileProvider Security: Direct external caller (UID 2000 shell) MUST be denied with SecurityException
    console.log(`[T19d] Verifying FileProvider external security (UID 2000 external access rejection)...`);
    const pdfContentUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_files/${savedPdfTransferId}/e2e_document.pdf`;
    let directReadDenied = false;
    try {
      const directRead = execSync(`adb -s '${serial}' shell content read --uri "${pdfContentUri}" 2>&1`, { encoding: "utf8" });
      if (directRead.includes("SecurityException") || directRead.includes("Permission Denial")) {
        directReadDenied = true;
      }
    } catch (e) {
      const errOut = `${e.stdout || ""} ${e.stderr || ""} ${e.message || ""}`;
      if (errOut.includes("SecurityException") || errOut.includes("Permission Denial")) {
        directReadDenied = true;
      } else {
        throw new Error(`Unexpected ADB error during direct read check: ${errOut}`);
      }
    }
    assert.ok(directReadDenied, "FAIL-CLOSED: FileProvider MUST deny direct access to external callers without URI permission grant (SecurityException: Permission Denial)");
    console.log(`  ✔ Negative Case: FileProvider denies direct access to external callers without grant (SecurityException: Permission Denial)`);

    // 5a-bis. Positive Case: Grant URI permission to external UID 2000 (com.android.shell) -> MUST read successfully
    console.log(`[T19d] Verifying positive FileProvider access with explicit URI permission grant to external UID 2000...`);
    execSync(`adb -s '${serial}' shell 'am start -a io.lucasvu.mynotch.ACTION_GRANT_URI_PERMISSION --es target_package com.android.shell --es uri "${pdfContentUri}" -n io.lucasvu.mynotch.mynotch_android/.MainActivity'`);
    await new Promise((r) => setTimeout(r, 600));
    const grantedReadBytes = execSync(`adb -s '${serial}' shell content read --uri "${pdfContentUri}"`, { maxBuffer: 10 * 1024 * 1024 });
    const grantedHash = crypto.createHash("sha256").update(grantedReadBytes).digest("hex");
    assert.equal(grantedHash, crypto.createHash("sha256").update(makeValidPdf()).digest("hex"), "External caller with granted URI permission MUST read identical content bytes");
    console.log(`  ✔ Positive Case: External UID 2000 reads content successfully with URI permission grant (SHA-256 match!)`);

    // 5b. Verify Path Traversal containment: Grant URI permission to the traversal URI to distinguish path errors from permission errors,
    // then verify that FileProvider strictly detects and rejects the traversal with "Resolved path jumped beyond configured root"
    console.log(`[T19d] Verifying FileProvider path traversal containment with granted URI...`);
    const traversalUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_files/..%2F..%2Fshared_prefs/sync_prefs.xml`;
    execSync(`adb -s '${serial}' shell 'am start -a io.lucasvu.mynotch.ACTION_GRANT_URI_PERMISSION --es target_package com.android.shell --es uri "${traversalUri}" -n io.lucasvu.mynotch.mynotch_android/.MainActivity'`);
    await new Promise((r) => setTimeout(r, 600));

    let traversalDenied = false;
    try {
      const travOut = execSync(`adb -s '${serial}' shell content read --uri "${traversalUri}" 2>&1`, { encoding: "utf8" });
      if (travOut.includes("Resolved path jumped beyond configured root") || travOut.includes("Failed to find configured root") || travOut.includes("IllegalArgumentException")) {
        traversalDenied = true;
      }
    } catch (e) {
      const errOut = `${e.stdout || ""} ${e.stderr || ""} ${e.message || ""}`;
      if (errOut.includes("Resolved path jumped beyond configured root") || errOut.includes("Failed to find configured root") || errOut.includes("IllegalArgumentException")) {
        traversalDenied = true;
      } else {
        throw new Error(`Expected path traversal error ('Resolved path jumped beyond configured root'), but got: ${errOut}`);
      }
    }
    assert.ok(traversalDenied, "FAIL-CLOSED: FileProvider MUST reject path traversal attempts with 'Resolved path jumped beyond configured root'");
    console.log(`  ✔ Verified FileProvider path traversal containment protection: 'Resolved path jumped beyond configured root'`);

    // 5c. Revocation Case: Revoke permission and verify access is denied again with specifically Permission Denial
    execSync(`adb -s '${serial}' shell 'am start -a io.lucasvu.mynotch.ACTION_REVOKE_URI_PERMISSION --es uri "${pdfContentUri}" -n io.lucasvu.mynotch.mynotch_android/.MainActivity'`);
    await new Promise((r) => setTimeout(r, 600));
    let postRevokeDenied = false;
    try {
      const postRevokeRead = execSync(`adb -s '${serial}' shell content read --uri "${pdfContentUri}" 2>&1`, { encoding: "utf8" });
      if (postRevokeRead.includes("Permission Denial")) {
        postRevokeDenied = true;
      }
    } catch (e) {
      const errOut = `${e.stdout || ""} ${e.stderr || ""} ${e.message || ""}`;
      if (errOut.includes("Permission Denial")) {
        postRevokeDenied = true;
      } else {
        throw new Error(`Expected Permission Denial after revocation, but got: ${errOut}`);
      }
    }
    assert.ok(postRevokeDenied, "FAIL-CLOSED: Access must be denied after URI permission revocation with Permission Denial");
    console.log(`  ✔ Revocation Case: Direct access rejected again after permission revocation (Permission Denial)`);

    // 5c. Direction 2 Transmission: PDF
    console.log(`[T19d] Dispatching Intent.ACTION_SEND for PDF: ${pdfContentUri}`);
    receivedAndroidFiles.length = 0;
    const sendPdfCmd = `adb -s '${serial}' shell 'am start -a android.intent.action.SEND -t application/pdf --eu android.intent.extra.STREAM "${pdfContentUri}" -n io.lucasvu.mynotch.mynotch_android/.ClipSendActivity --grant-read-uri-permission'`;
    execSync(sendPdfCmd);

    let receivedPdf = null;
    for (let i = 0; i < 40; i++) {
      if (receivedAndroidFiles.length > 0) {
        receivedPdf = receivedAndroidFiles[0];
        break;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.ok(receivedPdf, "FAIL-CLOSED: Android->Mac PDF file transfer was not received over WebSocket");
    const recPdfData = Buffer.from(receivedPdf.content_base64, "base64");
    const recPdfHash = crypto.createHash("sha256").update(recPdfData).digest("hex");
    const testPdfHash = crypto.createHash("sha256").update(makeValidPdf()).digest("hex");
    assert.equal(recPdfHash, testPdfHash, `Android->Mac PDF hash mismatch: ${recPdfHash} != ${testPdfHash}`);
    assert.equal(receivedPdf.receiver_session_id, macSessionId, `Android must address envelope to negotiated peer macSessionId`);
    assert.equal(receivedPdf.sender_session_id, androidSessionId, "Android must include valid sender_session_id");
    console.log(`  ✔ Verified Android -> Mac PDF transfer: received ${recPdfData.length} bytes, SHA-256 and Session match!`);

    // 5d. Direction 2 Transmission: DOCX (Bidirectional DOCX Verification)
    const docxContentUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_files/${savedDocxTransferId}/e2e_proposal.docx`;
    console.log(`[T19d] Dispatching Intent.ACTION_SEND for DOCX: ${docxContentUri}`);
    receivedAndroidFiles.length = 0;
    const sendDocxCmd = `adb -s '${serial}' shell 'am start -a android.intent.action.SEND -t application/vnd.openxmlformats-officedocument.wordprocessingml.document --eu android.intent.extra.STREAM "${docxContentUri}" -n io.lucasvu.mynotch.mynotch_android/.ClipSendActivity --grant-read-uri-permission'`;
    execSync(sendDocxCmd);

    let receivedDocx = null;
    for (let i = 0; i < 40; i++) {
      if (receivedAndroidFiles.length > 0) {
        receivedDocx = receivedAndroidFiles[0];
        break;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.ok(receivedDocx, "FAIL-CLOSED: Android->Mac DOCX file transfer was not received over WebSocket");
    const recDocxData = Buffer.from(receivedDocx.content_base64, "base64");
    const recDocxHash = crypto.createHash("sha256").update(recDocxData).digest("hex");
    const testDocxHash = crypto.createHash("sha256").update(makeValidDocx()).digest("hex");
    assert.equal(recDocxHash, testDocxHash, `Android->Mac DOCX hash mismatch: ${recDocxHash} != ${testDocxHash}`);
    assert.equal(receivedDocx.receiver_session_id, macSessionId, `Android must address envelope to negotiated peer macSessionId`);
    assert.equal(receivedDocx.sender_session_id, androidSessionId, "Android must include valid sender_session_id");
    console.log(`  ✔ Verified Android -> Mac DOCX transfer: received ${recDocxData.length} bytes, SHA-256 and Session match!`);

    // 5e. Direction 2 Transmission: ZIP (Bidirectional ZIP Verification)
    const zipContentUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_files/${savedZipTransferId}/e2e_archive.zip`;
    console.log(`[T19d] Dispatching Intent.ACTION_SEND for ZIP: ${zipContentUri}`);
    receivedAndroidFiles.length = 0;
    const sendZipCmd = `adb -s '${serial}' shell 'am start -a android.intent.action.SEND -t application/zip --eu android.intent.extra.STREAM "${zipContentUri}" -n io.lucasvu.mynotch.mynotch_android/.ClipSendActivity --grant-read-uri-permission'`;
    execSync(sendZipCmd);

    let receivedZip = null;
    for (let i = 0; i < 40; i++) {
      if (receivedAndroidFiles.length > 0) {
        receivedZip = receivedAndroidFiles[0];
        break;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.ok(receivedZip, "FAIL-CLOSED: Android->Mac ZIP file transfer was not received over WebSocket");
    const recZipData = Buffer.from(receivedZip.content_base64, "base64");
    const recZipHash = crypto.createHash("sha256").update(recZipData).digest("hex");
    const testZipHash = crypto.createHash("sha256").update(makeValidZip()).digest("hex");
    assert.equal(recZipHash, testZipHash, `Android->Mac ZIP hash mismatch: ${recZipHash} != ${testZipHash}`);
    assert.equal(receivedZip.receiver_session_id, macSessionId, `Android must address envelope to negotiated peer macSessionId`);
    assert.equal(receivedZip.sender_session_id, androidSessionId, "Android must include valid sender_session_id");
    console.log(`  ✔ Verified Android -> Mac ZIP transfer: received ${recZipData.length} bytes, SHA-256 and Session match!`);

    // 5f. Direction 2 Transmission: PNG (Bidirectional PNG Verification)
    const pngContentUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_images/${savedPngName}`;
    console.log(`[T19d] Dispatching Intent.ACTION_SEND for PNG: ${pngContentUri}`);
    receivedAndroidFiles.length = 0;
    const sendPngCmd = `adb -s '${serial}' shell 'am start -a android.intent.action.SEND -t image/png --eu android.intent.extra.STREAM "${pngContentUri}" -n io.lucasvu.mynotch.mynotch_android/.ClipSendActivity --grant-read-uri-permission'`;
    execSync(sendPngCmd);

    let receivedPng = null;
    for (let i = 0; i < 40; i++) {
      if (receivedAndroidFiles.length > 0) {
        receivedPng = receivedAndroidFiles[0];
        break;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.ok(receivedPng, "FAIL-CLOSED: Android->Mac PNG image transfer was not received over WebSocket");
    const recPngData = Buffer.from(receivedPng.content_base64, "base64");
    const recPngHash = crypto.createHash("sha256").update(recPngData).digest("hex");
    const testPngHash = crypto.createHash("sha256").update(makeValidPng()).digest("hex");
    assert.equal(recPngHash, testPngHash, `Android->Mac PNG hash mismatch: ${recPngHash} != ${testPngHash}`);
    assert.equal(receivedPng.receiver_session_id, macSessionId, `Android must address envelope to negotiated peer macSessionId`);
    assert.equal(receivedPng.sender_session_id, androidSessionId, "Android must include valid sender_session_id");
    console.log(`  ✔ Verified Android -> Mac PNG transfer: received ${recPngData.length} bytes, SHA-256 and Session match!`);

    // 5g. Direction 2 Transmission: Chunked Binary (1.2 MiB Chunked Verification)
    const chunkedContentUri = `content://io.lucasvu.mynotch.mynotch_android.syncfiles/sync_files/${savedChunkedTransferId}/chunked_sample.bin`;
    console.log(`[T19d] Dispatching Intent.ACTION_SEND for Chunked Binary: ${chunkedContentUri}`);
    receivedAndroidFiles.length = 0;
    const sendChunkedCmd = `adb -s '${serial}' shell 'am start -a android.intent.action.SEND -t application/octet-stream --eu android.intent.extra.STREAM "${chunkedContentUri}" -n io.lucasvu.mynotch.mynotch_android/.ClipSendActivity --grant-read-uri-permission'`;
    execSync(sendChunkedCmd);

    // Wait for all 3 chunks to be received
    for (let i = 0; i < 40; i++) {
      if (receivedAndroidFiles.length >= 3) break;
      await new Promise((r) => setTimeout(r, 250));
    }
    assert.equal(receivedAndroidFiles.length, 3, `Expected 3 chunks for 1.2 MiB chunked binary transfer, got ${receivedAndroidFiles.length}`);
    const sortedChunks = [...receivedAndroidFiles].sort((a, b) => a.sequence - b.sequence);
    const recChunkedData = Buffer.concat(sortedChunks.map((c) => Buffer.from(c.content_base64, "base64")));
    const recChunkedHash = crypto.createHash("sha256").update(recChunkedData).digest("hex");
    const testChunkedHash = crypto.createHash("sha256").update(makeChunkedData(1200000)).digest("hex");
    assert.equal(recChunkedHash, testChunkedHash, `Android->Mac Chunked Binary hash mismatch: ${recChunkedHash} != ${testChunkedHash}`);
    console.log(`  ✔ Verified Android -> Mac Chunked Binary transfer: received ${recChunkedData.length} bytes across 3 chunks with flow control, SHA-256 match!`);

    results["android_to_mac_transfer"] = {
      pdf: { sha256: recPdfHash, file_provider_uri: pdfContentUri, status: "verified" },
      docx: { sha256: recDocxHash, file_provider_uri: docxContentUri, status: "verified" },
      zip: { sha256: recZipHash, file_provider_uri: zipContentUri, status: "verified" },
      png: { sha256: recPngHash, file_provider_uri: pngContentUri, status: "verified" },
      chunked_bin: { sha256: recChunkedHash, file_provider_uri: chunkedContentUri, chunks: 3, status: "verified" },
      security: {
        uid2000_direct_read_denied: true,
        uid2000_granted_read_verified: true,
        uid2000_post_revoke_denied: true,
        path_traversal_denied: true,
        path_traversal_containment_verified: true
      },
      boundary: {
        exact_positive_15mib_verified: true,
        negative_max_plus_one_rejected: true,
        stream_size_mismatch_rejected: true
      }
    };

    // 6. Write Evidence Log
    if (!fs.existsSync(EVIDENCE_DIR)) {
      fs.mkdirSync(EVIDENCE_DIR, { recursive: true });
    }
    const evidencePath = path.join(EVIDENCE_DIR, "e2e_device_evidence.json");
    fs.writeFileSync(evidencePath, JSON.stringify({
      device: { serial, model: execSync(`adb -s '${serial}' shell getprop ro.product.model`, { encoding: "utf8" }).trim() },
      sessions: { mac: macSessionId, android: androidSessionId },
      direction_mac_to_android: results,
      direction_android_to_mac: results["android_to_mac_transfer"],
      timestamp: new Date().toISOString()
    }, null, 2));
    console.log(`[T19d] All live device tests PASSED cleanly! Evidence written to ${evidencePath}`);

  } finally {
    if (macWs) {
      try { macWs.terminate(); } catch (_) {}
    }
    await close();
    console.log("[T19d] Local relay server and WebSocket connection cleanly closed.");
  }
});
