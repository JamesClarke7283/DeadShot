// Browser-side multiplayer client.
//
// Thin wrapper over a WebSocket to the relay server. Tracks lobby state
// (self id, host, roster, settings), exposes typed senders, and fans incoming
// server messages out to callbacks the Lobby UI + Match register. Relay model:
// this client owns its own player; if it is the host it also owns the bots.

import {
  type BotStateMsg,
  type ClientMsg,
  decodeServer,
  DEFAULT_SETTINGS,
  encode,
  type LobbyPlayer,
  type LobbySettings,
  type PlayerStateMsg,
} from "./protocol.ts";

export interface NetCallbacks {
  onWelcome?(id: number): void;
  onLobby?(players: LobbyPlayer[], hostId: number, settings: LobbySettings): void;
  onStart?(settings: LobbySettings, seed: number, players: LobbyPlayer[]): void;
  onState?(from: number, s: PlayerStateMsg): void;
  onBots?(from: number, b: BotStateMsg[]): void;
  onHit?(from: number, target: number, dmg: number, headshot: boolean, weaponId?: string): void;
  onDeath?(
    from: number,
    victim: number,
    killer: number | undefined,
    weaponId: string | undefined,
    headshot: boolean,
  ): void;
  onEvent?(from: number, kind: string, data: unknown): void;
  onPeerLeft?(id: number): void;
  onClose?(): void;
  onError?(): void;
}

export class NetClient {
  selfId = -1;
  hostId = -1;
  players: LobbyPlayer[] = [];
  settings: LobbySettings = { ...DEFAULT_SETTINGS };

  private ws: WebSocket | null = null;
  private cb: NetCallbacks = {};

  constructor(readonly url: string) {}

  /** Merge in callback handlers (Lobby + Match both register their own). */
  on(cb: NetCallbacks): void {
    this.cb = { ...this.cb, ...cb };
  }

  /** Drop all registered handlers (e.g. when a Match is disposed). */
  clearHandlers(): void {
    this.cb = {};
  }

  get connected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
  get isHost(): boolean {
    return this.selfId >= 0 && this.selfId === this.hostId;
  }

  /** Open the socket and join `room` as `name`. Resolves once the socket opens. */
  connect(room: string, name: string): Promise<void> {
    return new Promise((resolvePromise, reject) => {
      let ws: WebSocket;
      try {
        ws = new WebSocket(this.url);
      } catch (e) {
        reject(e);
        return;
      }
      this.ws = ws;
      ws.onopen = () => {
        this.send({ t: "join", room, name });
        resolvePromise();
      };
      ws.onerror = () => {
        this.cb.onError?.();
        reject(new Error(`could not connect to ${this.url}`));
      };
      ws.onclose = () => this.cb.onClose?.();
      ws.onmessage = (ev: MessageEvent) =>
        this.dispatch(typeof ev.data === "string" ? ev.data : "");
    });
  }

  private dispatch(raw: string): void {
    const m = decodeServer(raw);
    if (!m) return;
    switch (m.t) {
      case "welcome":
        this.selfId = m.id;
        this.cb.onWelcome?.(m.id);
        break;
      case "lobby":
        this.players = m.players;
        this.hostId = m.hostId;
        this.settings = m.settings;
        this.cb.onLobby?.(m.players, m.hostId, m.settings);
        break;
      case "start":
        this.settings = m.settings;
        this.players = m.players;
        this.cb.onStart?.(m.settings, m.seed, m.players);
        break;
      case "state":
        this.cb.onState?.(m.from, m.s);
        break;
      case "bots":
        this.cb.onBots?.(m.from, m.b);
        break;
      case "hit":
        this.cb.onHit?.(m.from, m.target, m.dmg, m.headshot, m.weaponId);
        break;
      case "death":
        this.cb.onDeath?.(m.from, m.victim, m.killer, m.weaponId, m.headshot);
        break;
      case "event":
        this.cb.onEvent?.(m.from, m.kind, m.data);
        break;
      case "peerLeft":
        this.cb.onPeerLeft?.(m.id);
        break;
    }
  }

  // ---- Senders ----
  setReady(ready: boolean): void {
    this.send({ t: "ready", ready });
  }
  setSettings(settings: LobbySettings): void {
    this.send({ t: "settings", settings });
  }
  start(): void {
    this.send({ t: "start" });
  }
  sendState(s: PlayerStateMsg): void {
    this.send({ t: "state", s });
  }
  sendBots(b: BotStateMsg[]): void {
    this.send({ t: "bots", b });
  }
  sendHit(target: number, dmg: number, headshot: boolean, weaponId?: string): void {
    this.send({ t: "hit", target, dmg, headshot, weaponId });
  }
  sendDeath(
    victim: number,
    killer: number | undefined,
    weaponId: string | undefined,
    headshot: boolean,
  ): void {
    this.send({ t: "death", victim, killer, weaponId, headshot });
  }
  sendEvent(kind: string, data?: unknown): void {
    this.send({ t: "event", kind, data });
  }

  private send(msg: ClientMsg): void {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(encode(msg));
  }

  disconnect(): void {
    try {
      this.ws?.close();
    } catch {
      // already closed
    }
    this.ws = null;
  }
}
