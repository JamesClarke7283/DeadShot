// In-game developer console (toggled with the left-tilde / backquote key).
//
// Captures a command line while open and forwards it to a handler that the Game
// wires to match/debug actions (spawn bots, switch maps, grant streaks, god
// mode, end match, ...). Decoupled from those actions via the `run` callback.

import { el } from "./dom.ts";

export class DevConsole {
  private panel: HTMLDivElement;
  private input: HTMLInputElement;
  private log: HTMLDivElement;
  open = false;

  constructor(root: HTMLElement, private run: (cmd: string) => string | void) {
    this.panel = el("div", {
      parent: root,
      style: {
        position: "fixed",
        left: "0",
        top: "0",
        right: "0",
        maxHeight: "40vh",
        display: "none",
        flexDirection: "column",
        background: "rgba(6,8,11,0.92)",
        borderBottom: "2px solid #b6ff5e",
        font: "13px/1.4 'Consolas', monospace",
        color: "#cfe",
        zIndex: "200",
        pointerEvents: "auto",
      },
    });
    this.log = el("div", {
      parent: this.panel,
      style: { overflowY: "auto", padding: "8px 10px", flex: "1", whiteSpace: "pre-wrap" },
    });
    this.input = el("input", {
      parent: this.panel,
      attrs: { type: "text", placeholder: "command… (try: help)" },
      style: {
        border: "none",
        borderTop: "1px solid #2a3a20",
        background: "#0a0c10",
        color: "#b6ff5e",
        font: "13px/1.4 'Consolas', monospace",
        padding: "8px 10px",
        outline: "none",
      },
    }) as HTMLInputElement;

    globalThis.addEventListener("keydown", this.onKey, true);
    this.input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") this.submit();
      if (e.key === "Escape") this.toggle();
    });

    this.println("DeadShot dev console. Type 'help'.");
  }

  private onKey = (e: KeyboardEvent): void => {
    if (e.code === "Backquote") {
      e.preventDefault();
      this.toggle();
    }
  };

  toggle(): void {
    this.open = !this.open;
    this.panel.style.display = this.open ? "flex" : "none";
    if (this.open) {
      this.input.focus();
    } else {
      this.input.blur();
    }
  }

  private submit(): void {
    const cmd = this.input.value.trim();
    if (!cmd) return;
    this.println("> " + cmd);
    this.input.value = "";
    try {
      const out = this.run(cmd);
      if (out) this.println(out);
    } catch (err) {
      this.println("error: " + (err instanceof Error ? err.message : String(err)));
    }
  }

  println(line: string): void {
    const row = el("div", { text: line });
    this.log.appendChild(row);
    this.log.scrollTop = this.log.scrollHeight;
  }

  dispose(): void {
    globalThis.removeEventListener("keydown", this.onKey, true);
    this.panel.remove();
  }
}
