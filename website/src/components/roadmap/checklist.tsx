"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useReducedMotion } from "@/lib/use-reduced-motion";

const PEN = "cubic-bezier(0.65,0,0.35,1)";
const CHECK_MS = 200;
const STRIKE_DELAY_MS = 140;
const FADE_MS = 180;

type Line = { x0: number; x1: number; y: number };
type Stroke = { d: string; width: number };

function hash(text: string) {
	let h = 2166136261;
	for (let i = 0; i < text.length; i++) {
		h ^= text.charCodeAt(i);
		h = Math.imul(h, 16777619);
	}
	return h >>> 0;
}

function random(seed: number) {
	let a = seed;
	return () => {
		a = (a + 0x6d2b79f5) | 0;
		let t = Math.imul(a ^ (a >>> 15), 1 | a);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

const r = (n: number) => Math.round(n * 10) / 10;

function checkPath(seed: number): Stroke {
	const rand = random(seed);
	const between = (a: number, b: number) => a + rand() * (b - a);
	const sx = between(3.5, 7);
	const sy = between(10, 14);
	const vx = sx + between(3.5, 5.5);
	const vy = between(16.5, 19.5);
	const angle = (between(48, 68) * Math.PI) / 180;
	const length = between(15, 21);
	const ex = vx + Math.cos(angle) * length;
	const ey = vy - Math.sin(angle) * length;
	const dipBow = between(-1.2, 1.4);
	const flickBow = between(-2.2, 1.6);
	const nx = Math.sin(angle);
	const ny = Math.cos(angle);
	let d =
		`M${r(sx)} ${r(sy)}` +
		`C${r(sx + 1.3 + dipBow)} ${r(sy + 2 - dipBow * 0.5)} ${r(vx - 1.8)} ${r(vy - between(0.2, 1.4))} ${r(vx)} ${r(vy)}` +
		`C${r(vx + (ex - vx) * 0.3 + nx * flickBow)} ${r(vy + (ey - vy) * 0.3 + ny * flickBow)} ${r(vx + (ex - vx) * 0.7 + nx * flickBow)} ${r(vy + (ey - vy) * 0.7 + ny * flickBow)} ${r(ex)} ${r(ey)}`;
	if (rand() < 0.45) {
		d += `q${r(between(0.6, 1.6))} ${r(between(-0.6, 0.3))} ${r(between(1.2, 2.6))} ${r(between(0.4, 1.4))}`;
	}
	return { d, width: r(between(1.75, 2.3)) };
}

function strikePath(line: Line, seed: number): Stroke {
	const rand = random(seed);
	const between = (a: number, b: number) => a + rand() * (b - a);
	const x0 = line.x0 - between(1, 5);
	const x1 = line.x1 + between(1, 6);
	const w = x1 - x0;
	const { y } = line;
	const slope = between(-2, 0.6);
	const d =
		`M${r(x0)} ${r(y - slope / 2 + between(-0.6, 0.6))}` +
		`C${r(x0 + w * between(0.25, 0.4))} ${r(y + between(-1.8, 1.8))} ${r(x0 + w * between(0.6, 0.75))} ${r(y + between(-1.8, 1.8))} ${r(x1)} ${r(y + slope / 2 + between(-0.6, 0.6))}`;
	return { d, width: r(between(1.4, 1.9)) };
}

const strikeMs = (line: Line) => Math.round(Math.min(260, Math.max(120, (line.x1 - line.x0) * 0.9)));

function strokeStyle(checked: boolean, delay: number, duration: number, reduceMotion: boolean) {
	if (checked) {
		return {
			strokeDashoffset: 0,
			opacity: 1,
			transition: reduceMotion ? `opacity ${FADE_MS}ms ease-out` : `stroke-dashoffset ${duration}ms ${PEN} ${delay}ms`,
		};
	}
	return {
		strokeDashoffset: 1.04,
		opacity: 0,
		transition: `opacity ${FADE_MS}ms ease-out, stroke-dashoffset 0ms linear ${FADE_MS}ms`,
	};
}

function Item({ label, checked, reduceMotion }: { label: string; checked: boolean; reduceMotion: boolean }) {
	const seed = hash(label);
	const check = checkPath(seed);
	const wrapRef = useRef<HTMLSpanElement>(null);
	const textRef = useRef<HTMLSpanElement>(null);
	const [lines, setLines] = useState<Line[]>([]);

	useLayoutEffect(() => {
		const wrap = wrapRef.current;
		const text = textRef.current;
		if (!wrap || !text) return;
		let alive = true;

		const measure = () => {
			const origin = wrap.getBoundingClientRect();
			const k = wrap.offsetWidth ? origin.width / wrap.offsetWidth : 1;
			const s = Number.isFinite(k) && k > 0 ? k : 1;
			const range = document.createRange();
			range.selectNodeContents(text);
			const rows: { top: number; bottom: number; left: number; right: number }[] = [];
			for (const rect of Array.from(range.getClientRects())) {
				if (rect.width < 1) continue;
				const row = rows.find((l) => Math.abs(l.top - rect.top) < rect.height / 2);
				if (row) {
					row.left = Math.min(row.left, rect.left);
					row.right = Math.max(row.right, rect.right);
				} else {
					rows.push({ top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right });
				}
			}
			const next = rows.map((row) => ({
				x0: r((row.left - origin.left) / s),
				x1: r((row.right - origin.left) / s),
				y: r(((row.top + row.bottom) / 2 - origin.top) / s + 0.5),
			}));
			setLines((prev) =>
				prev.length === next.length && prev.every((l, i) => l.x0 === next[i].x0 && l.x1 === next[i].x1 && l.y === next[i].y)
					? prev
					: next,
			);
		};

		measure();
		const observer = new ResizeObserver(measure);
		observer.observe(wrap);
		document.fonts?.ready.then(() => alive && measure());
		return () => {
			alive = false;
			observer.disconnect();
		};
	}, []);

	return (
		<li className="flex items-start gap-3.5 border-b border-line py-3.5 text-[16px] leading-6">
			<span className="relative mt-0.5 size-5 flex-none rounded-md bg-card inset-ring inset-ring-line-strong" aria-hidden>
				<svg viewBox="0 0 24 24" fill="none" className="pointer-events-none absolute -top-2 -left-0.5 size-6 overflow-visible text-fg">
					<path
						d={check.d}
						pathLength={1}
						stroke="currentColor"
						strokeWidth={check.width}
						strokeLinecap="round"
						strokeLinejoin="round"
						strokeDasharray="1 2"
						style={strokeStyle(checked, 0, CHECK_MS, reduceMotion)}
					/>
				</svg>
			</span>
			<span ref={wrapRef} className="relative min-w-0">
				<span ref={textRef} className="text-fg transition-colors duration-200 ease-out data-checked:text-muted" data-checked={checked || undefined}>
					{label}
				</span>
				<svg aria-hidden fill="none" className="pointer-events-none absolute inset-0 size-full overflow-visible text-[rgb(237_237_237/0.6)]">
					{lines.map((line, i) => {
						const delay = lines.slice(0, i).reduce((sum, l) => sum + strikeMs(l), STRIKE_DELAY_MS);
						const strike = strikePath(line, seed + i + 1);
						return (
							<path
								key={i}
								d={strike.d}
								pathLength={1}
								stroke="currentColor"
								strokeWidth={strike.width}
								strokeLinecap="round"
								strokeDasharray="1 2"
								style={strokeStyle(checked, delay, strikeMs(line), reduceMotion)}
							/>
						);
					})}
				</svg>
			</span>
		</li>
	);
}

export default function Checklist({ items, done = false }: { items: string[]; done?: boolean | number }) {
	const reduceMotion = useReducedMotion();
	const list = useRef<HTMLUListElement>(null);
	const [ticked, setTicked] = useState(0);
	const count = done === true ? items.length : done || 0;
	const gaps = items.slice(0, count).map((label) => 420 + label.length * 5).join();

	useEffect(() => {
		const element = list.current;
		if (!element || !count) return;
		const timers: ReturnType<typeof setTimeout>[] = [];
		const observer = new IntersectionObserver(
			([e]) => {
				if (!e.isIntersecting) return;
				observer.disconnect();
				if (reduceMotion) return setTicked(count);
				let at = 300;
				gaps.split(",").forEach((gap, i) => {
					timers.push(setTimeout(() => setTicked(i + 1), at));
					at += Number(gap);
				});
			},
			{ threshold: 0.35 },
		);
		observer.observe(element);
		return () => {
			observer.disconnect();
			timers.forEach(clearTimeout);
		};
	}, [count, gaps, reduceMotion]);

	return (
		<ul ref={list}>
			{items.map((label, i) => (
				<Item key={label} label={label} checked={i < ticked} reduceMotion={reduceMotion} />
			))}
		</ul>
	);
}
