/**
 * Minimal typed subset of the OpenClaw Gateway WebSocket protocol (v4) that
 * Wingman shells need. Mirrors `packages/gateway-protocol` in OpenClaw —
 * frame envelopes, connect handshake, and agent run params/events.
 *
 * Every platform shell (macOS Swift, Windows, mobile) implements this same
 * wire contract; this file is the canonical reference plus the implementation
 * used by TypeScript shells.
 */

export const WINGMAN_PROTOCOL_VERSION = 4;

export type RequestFrame = {
  type: "req";
  id: string;
  method: string;
  params?: unknown;
};

export type ResponseFrame = {
  type: "res";
  id: string;
  ok: boolean;
  payload?: unknown;
  error?: { code: string; message: string; retryable?: boolean };
};

export type EventFrame = {
  type: "event";
  event: string;
  payload?: unknown;
  seq?: number;
};

export type GatewayFrame = RequestFrame | ResponseFrame | EventFrame;

/**
 * Client identity sent on connect.
 * Use `gateway-client` + `backend` with a shared loopback token so OpenClaw
 * preserves operator scopes without device pairing (ui mode clears them).
 */
export type ConnectClientInfo = {
  id: "gateway-client";
  displayName?: string;
  version: string;
  platform: string;
  deviceFamily?: string;
  mode: "backend";
  instanceId?: string;
};

/** Default operator scopes for Wingman shells (includes agent `operator.write`). */
export const WINGMAN_OPERATOR_SCOPES = [
  "operator.admin",
  "operator.read",
  "operator.write",
  "operator.approvals",
  "operator.pairing",
] as const;

export type ConnectParams = {
  minProtocol: number;
  maxProtocol: number;
  client: ConnectClientInfo;
  role?: "operator";
  scopes?: readonly string[];
  auth?: { token?: string; password?: string; deviceToken?: string };
  locale?: string;
  userAgent?: string;
};

export function buildConnectParams(options: {
  displayName: string;
  version: string;
  platform: string;
  instanceId: string;
  token?: string;
}): ConnectParams {
  return {
    minProtocol: WINGMAN_PROTOCOL_VERSION,
    maxProtocol: WINGMAN_PROTOCOL_VERSION,
    client: {
      id: "gateway-client",
      displayName: options.displayName,
      version: options.version,
      platform: options.platform,
      mode: "backend",
      instanceId: options.instanceId,
    },
    role: "operator",
    scopes: [...WINGMAN_OPERATOR_SCOPES],
    auth: options.token ? { token: options.token } : undefined,
  };
}

/** Base64 image attachment accepted by the gateway `agent` method. */
export type ImageAttachment = {
  type: "image";
  source: { type: "base64"; media_type: string; data: string };
};

/** Params for the `agent` RPC (subset of OpenClaw AgentParamsSchema). */
export type AgentParams = {
  message: string;
  sessionKey?: string;
  attachments?: ImageAttachment[];
  extraSystemPrompt?: string;
  deliver?: boolean;
  timeout?: number;
  idempotencyKey: string;
};

/** Streaming event payload for `agent` events. */
export type AgentEvent = {
  runId: string;
  seq: number;
  stream: string;
  ts: number;
  data: Record<string, unknown>;
};
