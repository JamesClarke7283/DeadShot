// Monotonic clock with delta clamping.
//
// Wraps performance.now() and clamps per-frame delta so a tab-switch / GC pause
// cannot inject a huge dt that tunnels the player through walls or NaNs the sim.

export class Clock {
  private last: number;
  /** Seconds since start(), advanced by getDelta(). */
  elapsed = 0;
  /** Max delta returned in seconds (frames longer than this are clamped). */
  maxDelta: number;

  constructor(maxDelta = 0.1) {
    this.maxDelta = maxDelta;
    this.last = performance.now() / 1000;
  }

  /** Reset the clock baseline (e.g. after a long pause / match load). */
  reset(): void {
    this.last = performance.now() / 1000;
  }

  /** Seconds since the previous call, clamped to [0, maxDelta]. */
  getDelta(): number {
    const now = performance.now() / 1000;
    let dt = now - this.last;
    this.last = now;
    if (dt < 0) dt = 0;
    if (dt > this.maxDelta) dt = this.maxDelta;
    this.elapsed += dt;
    return dt;
  }
}
