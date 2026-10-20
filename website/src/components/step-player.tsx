"use client";

import { useEffect, useRef, useState, type RefObject } from "react";

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
const mix = (a: number, b: number, t: number) => a + (b - a) * t;
const quart = (t: number) => 1 - (1 - t) ** 4;
const swing = (t: number) => (t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2);
const easeOut = (u: number) => 1 - Math.pow(1 - u, 3);

function useTween(to: number, ms: number, instant = false, ease = quart) {
	const [at, setAt] = useState(to);
	const cur = useRef(to);
	const raf = useRef(0);

	useEffect(() => {
		if (instant) {
			cur.current = to;
			setAt(to);
			return;
		}
		const from = cur.current;
		if (from === to) return;
		const t0 = performance.now();
		const step = (now: number) => {
			const t = Math.min(1, (now - t0) / ms);
			cur.current = from + (to - from) * ease(t);
			setAt(cur.current);
			raf.current = t < 1 ? requestAnimationFrame(step) : 0;
		};
		raf.current = requestAnimationFrame(step);
		return () => {
			cancelAnimationFrame(raf.current);
			raf.current = 0;
		};
	}, [to, ms, instant, ease]);

	return at;
}

const PAUSE_L = [6, 4, 10, 4, 10, 20, 6, 20] as const;
const PLAY_L = [6.5, 4, 13.25, 8, 13.25, 16, 6.5, 20] as const;
const PAUSE_R = [14, 4, 18, 4, 18, 20, 14, 20] as const;
const PLAY_R = [13.25, 8, 20, 12, 20, 12, 13.25, 16] as const;

const quad = (a: readonly number[], b: readonly number[], t: number) => {
	let d = "";
	for (let i = 0; i < 8; i += 2) d += `${i ? "L" : "M"}${mix(a[i], b[i], t).toFixed(2)} ${mix(a[i + 1], b[i + 1], t).toFixed(2)}`;
	return `${d}Z`;
};

function Mark({ playing, size, still }: { playing: boolean; size: number; still: boolean }) {
	const t = useTween(playing ? 0 : 1, 300, still, swing);
	const goo = Math.sin(clamp(t, 0, 1) * Math.PI);
	const pull = 1.6 * goo;
	const tip = (playing ? -9 : 9) * goo;

	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 24 24"
			aria-hidden
			fill="currentColor"
			stroke="currentColor"
			strokeWidth={2}
			strokeLinejoin="round"
			strokeLinecap="round"
			style={{ transformOrigin: "50% 50%", transform: `rotate(${tip}deg) scale(${1 - 0.13 * goo}, ${1 + 0.11 * goo})` }}
		>
			<path d={quad(PAUSE_L, PLAY_L, t)} transform={`translate(${pull} 0)`} />
			<path d={quad(PAUSE_R, PLAY_R, t)} transform={`translate(${-pull} 0)`} />
		</svg>
	);
}

const DOT = 8;
const BAR = 36;
const GAP = 8;
const PAD = 14;
const H = DOT + PAD * 2;
const MOVE = 520;
const LEAD = 60;
const RISE = 300;
const WAKE = { amp: 0.34, reach: 8, self: 0.3, stagger: 55 };
const SETTLE = { k: 0.16, d: 1 - 2 * Math.sqrt(0.16) };

const layout = (n: number, at: number) => {
	const out: [number, number][] = [];
	let x = 0;
	for (let i = 0; i < n; i++) {
		const w = i === at ? BAR : DOT;
		out.push([x, x + w]);
		x += w + GAP;
	}
	return out;
};

type Tween = { from: number; to: number; t0: number };
type Edge = { x: number; v: number; tw?: Tween };
type Dot = { l: Edge; r: Edge; ink: number };

type Props = {
	labels: string[];
	at: number;
	playing: boolean;
	progress: RefObject<number>;
	onPick: (i: number) => void;
	onPeek?: (i: number) => void;
	onToggle: () => void;
};

export default function StepPlayer({ labels, at, playing, progress, onPick, onPeek, onToggle }: Props) {
	const n = labels.length;
	const [still, setStill] = useState(false);
	const [, setTick] = useState(0);

	const dots = useRef<Dot[]>([]);
	const raf = useRef(0);
	const shown = useRef(at);
	const wave = useRef<{ t0: number; origin: number; from: number } | null>(null);
	const live = useRef({ at, playing, n, still });
	live.current = { at, playing, n, still };

	if (dots.current.length !== n) {
		dots.current = layout(n, at).map(([l, r], i) => ({ l: { x: l, v: 0 }, r: { x: r, v: 0 }, ink: i < at ? 1 : 0 }));
	}

	const run = () => {
		if (raf.current) return;
		let prev = 0;
		const tick = (t: number) => {
			const dt = prev ? clamp((t - prev) / 16.67, 0, 2.5) : 1;
			prev = t;
			const { at: cur, playing: on, n: count, still: calm } = live.current;
			const slots = layout(count, cur);
			let busy = on;

			dots.current.forEach((d, i) => {
				const [tl, tr] = slots[i] ?? [0, 0];
				for (const [e, target] of [
					[d.l, tl],
					[d.r, tr],
				] as const) {
					if (calm) {
						e.x = target;
						e.v = 0;
						e.tw = undefined;
						continue;
					}
					if (e.tw) {
						const u = clamp((t - e.tw.t0) / MOVE, 0, 1);
						e.x = mix(e.tw.from, e.tw.to, easeOut(u));
						if (u >= 1) e.tw = undefined;
						busy = true;
						continue;
					}
					e.v += (target - e.x) * SETTLE.k * dt;
					e.v *= Math.pow(SETTLE.d, dt);
					e.x += e.v * dt;
					if (Math.abs(target - e.x) < 0.02 && Math.abs(e.v) < 0.02) {
						e.x = target;
						e.v = 0;
					} else busy = true;
				}
				const want = i < cur ? 1 : i === cur ? clamp(progress.current ?? 0, 0, 1) : 0;
				const next = calm ? want : d.ink + (want - d.ink) * Math.min(1, 0.22 * dt);
				d.ink = Math.abs(want - next) < 0.002 ? want : next;
				if (d.ink !== want) busy = true;
			});

			if (wave.current && t - wave.current.t0 < LEAD + (WAKE.reach + 1) * WAKE.stagger + RISE) busy = true;
			else wave.current = null;

			setTick((k) => k + 1);
			raf.current = busy ? requestAnimationFrame(tick) : 0;
		};
		raf.current = requestAnimationFrame(tick);
	};

	useEffect(() => {
		setStill(matchMedia("(prefers-reduced-motion: reduce)").matches);
		return () => {
			cancelAnimationFrame(raf.current);
			raf.current = 0;
		};
	}, []);

	useEffect(() => {
		const from = shown.current;
		shown.current = at;
		if (from !== at && !live.current.still) {
			const will = layout(n, at);
			const now = performance.now();
			dots.current.forEach((d, i) => {
				d.l.tw = { from: d.l.x, to: will[i][0], t0: now };
				d.r.tw = { from: d.r.x, to: will[i][1], t0: now };
			});
			wave.current = { t0: now, origin: at, from };
		}
		run();
	});

	const now = typeof performance === "undefined" ? 0 : performance.now();
	const shape = (d: Dot, i: number) => {
		let sy = 1;
		const w = wave.current;
		if (w) {
			const span = Math.abs(w.origin - w.from);
			const skip = Math.max(0, span - WAKE.reach);
			const lo = Math.min(w.from, w.origin);
			const hi = Math.max(w.from, w.origin);
			let delay = -1;
			let share = 1;
			if (i === w.origin) {
				delay = Math.min(span, WAKE.reach) * WAKE.stagger;
				share = WAKE.self;
			} else if (i >= lo && i <= hi) {
				const k = Math.abs(i - w.from);
				if (span - k <= WAKE.reach) delay = (k - skip) * WAKE.stagger;
			}
			if (delay >= 0) {
				const u = (now - w.t0 - LEAD - delay) / RISE;
				if (u > 0 && u < 1) sy = 1 + Math.sin(Math.PI * u) * WAKE.amp * share;
			}
		}
		return `translateX(${d.l.x.toFixed(2)}px) scaleY(${sy.toFixed(3)})`;
	};

	const width = layout(n, 0).at(-1)![1];

	return (
		<div className="flex items-center gap-2" role="group" aria-label={`${labels[at]}, ${at + 1} of ${n}`}>
			<div className="bg-raised inset-ring inset-ring-line" style={{ padding: PAD, borderRadius: H / 2 }}>
				<div className="relative" style={{ width, height: DOT }}>
					{dots.current.map((d, i) => {
						const w = Math.max(0, d.r.x - d.l.x);
						return (
							<button
								key={i}
								type="button"
								aria-label={`Show ${labels[i]}`}
								aria-current={i === at ? "step" : undefined}
								onClick={() => i !== at && onPick(i)}
								onPointerEnter={() => onPeek?.(i)}
								className="absolute top-0 left-0 h-full cursor-pointer overflow-hidden rounded-full bg-line-strong transition-colors duration-200 ease-quart before:absolute before:-inset-2 hover:bg-faint"
								style={{ transform: shape(d, i), width: w }}
							>
								<i
									className="absolute inset-y-0 left-0 block rounded-full bg-fg"
									style={{
										width: d.ink > 0.001 ? Math.max(Math.min(DOT, w), w * d.ink) : 0,
										opacity: i === at ? Math.min(1, d.ink * 14) : 1,
									}}
								/>
							</button>
						);
					})}
				</div>
			</div>

			<button
				type="button"
				onClick={onToggle}
				aria-label={playing ? "Pause" : "Play"}
				className="grid cursor-pointer place-items-center bg-raised text-fg inset-ring inset-ring-line transition-[background-color,scale] duration-200 ease-quart hover:bg-surface active:scale-95"
				style={{ width: H, height: H, borderRadius: H / 2 }}
			>
				<Mark playing={playing} size={14} still={still} />
			</button>
		</div>
	);
}
