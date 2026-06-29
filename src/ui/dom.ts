// Tiny DOM helper for building UI screens with inline styles (keeps each screen
// self-contained — no shared CSS class coupling). All UI lives under #ui-root.

export interface ElOptions {
  class?: string;
  id?: string;
  text?: string;
  html?: string;
  style?: Partial<CSSStyleDeclaration>;
  parent?: HTMLElement;
  onClick?: (e: MouseEvent) => void;
  attrs?: Record<string, string>;
  children?: HTMLElement[];
}

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  opts: ElOptions = {},
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (opts.class) node.className = opts.class;
  if (opts.id) node.id = opts.id;
  if (opts.text !== undefined) node.textContent = opts.text;
  if (opts.html !== undefined) node.innerHTML = opts.html;
  if (opts.style) Object.assign(node.style, opts.style);
  if (opts.attrs) { for (const [k, v] of Object.entries(opts.attrs)) node.setAttribute(k, v); }
  if (opts.onClick) node.addEventListener("click", opts.onClick as EventListener);
  if (opts.children) { for (const c of opts.children) node.appendChild(c); }
  if (opts.parent) opts.parent.appendChild(node);
  return node;
}

export function clearChildren(node: HTMLElement): void {
  while (node.firstChild) node.removeChild(node.firstChild);
}

/** A styled cartoon button. */
export function button(
  label: string,
  onClick: () => void,
  style: Partial<CSSStyleDeclaration> = {},
): HTMLButtonElement {
  const b = el("button", {
    text: label,
    onClick,
    style: {
      pointerEvents: "auto",
      cursor: "pointer",
      font: "600 16px/1 'Segoe UI', system-ui, sans-serif",
      letterSpacing: "0.04em",
      color: "#0a0c10",
      background: "linear-gradient(180deg,#cdeb6e,#9fd13e)",
      border: "2px solid #0a0c10",
      borderRadius: "8px",
      padding: "12px 22px",
      boxShadow: "3px 3px 0 #0a0c10",
      ...style,
    },
  });
  b.addEventListener("mouseenter", () => (b.style.filter = "brightness(1.08)"));
  b.addEventListener("mouseleave", () => (b.style.filter = "none"));
  return b;
}

/** Hex number -> CSS color string. */
export function hexColor(hex: number): string {
  return "#" + hex.toString(16).padStart(6, "0");
}
