// Event rate limits (spec 7.2): a leading send when idle, then at most one per interval, and the trailing value is
// always sent, so the native side's last `edited` revision is never stale.
export type Clock = { now(): number; setTimeout(f: () => void, ms: number): unknown; clearTimeout(t: unknown): void };
export const realClock: Clock = {
  now: () => performance.now(),
  setTimeout: (f, ms) => setTimeout(f, ms),
  clearTimeout: (t) => clearTimeout(t as ReturnType<typeof setTimeout>),
};

export class Throttle<T> {
  private last = -Infinity;
  private timer: unknown = null;
  private latest: (() => T) | null = null;
  private readonly interval: number;
  private readonly send: (v: T) => void;
  private readonly clock: Clock;

  constructor(perSecond: number, send: (v: T) => void, clock: Clock = realClock) {
    this.interval = 1000 / perSecond;
    this.send = send;
    this.clock = clock;
  }

  /** `value` is computed only when it is sent, so a burst of pushes costs one computation. */
  push(value: () => T): void {
    this.latest = value;
    if (this.timer !== null) return;
    const wait = this.last + this.interval - this.clock.now();
    if (wait <= 0) this.flush();
    else this.timer = this.clock.setTimeout(() => { this.timer = null; this.flush(); }, wait);
  }

  private flush(): void {
    const v = this.latest;
    this.latest = null;
    if (!v) return;
    this.last = this.clock.now();
    this.send(v());
  }

  cancel(): void {
    if (this.timer !== null) this.clock.clearTimeout(this.timer);
    this.timer = null;
    this.latest = null;
  }
}
