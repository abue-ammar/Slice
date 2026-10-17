"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";

type Clip = { id: string; label: string; src: string; poster: string; alt: string; rest: number };

const CLIPS: Clip[] = [
	{
		id: "editor",
		label: "Editor",
		src: "/media/slice-editor.mp4",
		poster: "/media/slice-editor.jpg",
		alt: "The Slice editor: a recording on a wallpaper background in the preview, the inspector switching between background, cursor and click settings, and a timeline of zooms under the take.",
		rest: 0,
	},
	{
		id: "spotlight",
		label: "Spotlight",
		src: "/media/spotlight.mp4",
		poster: "/media/spotlight.jpg",
		alt: "A website recorded in Slice with a spotlight on the cursor: everything outside a soft circle is blurred, and the circle follows the pointer from row to row.",
		rest: 0,
	},
	{
		id: "sensitive",
		label: "Sensitive text",
		src: "/media/sensitive-text.mp4",
		poster: "/media/sensitive-text.jpg",
		alt: "A Gmail account menu recorded in Slice, with every email address found and blurred automatically as the view zooms out.",
		rest: 4,
	},
];

const add = (set: Set<number>, ...items: number[]) => (items.every((i) => set.has(i)) ? set : new Set([...set, ...items]));

export default function HeroShowcase() {
	const [active, setActive] = useState(0);
	const [loaded, setLoaded] = useState(() => new Set([0]));
	const stage = useRef<HTMLDivElement>(null);
	const videos = useRef<(HTMLVideoElement | null)[]>([]);
	const fills = useRef<(HTMLSpanElement | null)[]>([]);
	const tabs = useRef<(HTMLButtonElement | null)[]>([]);

	const select = (i: number) => {
		setLoaded((s) => add(s, i, (i + 1) % CLIPS.length));
		setActive(i);
	};

	useEffect(() => {
		const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
		const video = videos.current[active];
		videos.current.forEach((v, i) => i !== active && v?.pause());
		fills.current.forEach((f) => f && (f.style.transform = `scaleX(${still ? 1 : 0})`));
		if (!video || !stage.current || still) return;

		video.currentTime = 0;
		let visible = false;
		let rested = 0;
		let last = performance.now();
		let frame = 0;

		const observer = new IntersectionObserver(
			([e]) => {
				visible = e.isIntersecting;
				if (visible && !video.ended) video.play().catch(() => {});
				else video.pause();
				if (visible) setLoaded((s) => add(s, (active + 1) % CLIPS.length));
			},
			{ threshold: 0.15 },
		);
		observer.observe(stage.current);

		const tick = (now: number) => {
			const dt = (now - last) / 1000;
			last = now;
			const duration = video.duration;
			if (Number.isFinite(duration) && duration > 0) {
				if (video.ended && visible) rested += dt;
				const progress = Math.min(1, (video.ended ? duration + rested : video.currentTime) / (duration + CLIPS[active].rest));
				const fill = fills.current[active];
				if (fill) fill.style.transform = `scaleX(${progress})`;
				if (progress >= 1) {
					const next = (active + 1) % CLIPS.length;
					setLoaded((s) => add(s, next, (next + 1) % CLIPS.length));
					setActive(next);
					return;
				}
			}
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);

		return () => {
			observer.disconnect();
			cancelAnimationFrame(frame);
		};
	}, [active]);

	const onKey = (e: KeyboardEvent) => {
		const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
		if (!d) return;
		e.preventDefault();
		const i = (active + d + CLIPS.length) % CLIPS.length;
		select(i);
		tabs.current[i]?.focus();
	};

	return (
		<>
			<div
				ref={stage}
				id="hero-stage"
				role="tabpanel"
				aria-labelledby={`hero-tab-${CLIPS[active].id}`}
				className="scroll-settle relative aspect-[16/10] origin-top overflow-hidden rounded-[20px] bg-black ring-1 ring-line will-change-transform max-[520px]:rounded-xl"
			>
				{CLIPS.map((c, i) => (
					<video
						key={c.id}
						ref={(el) => {
							videos.current[i] = el;
						}}
						className={`absolute inset-0 block size-full object-cover transition-[opacity,filter,scale] duration-700 ease-settle motion-reduce:duration-300 ${
							i === active ? "opacity-100" : "pointer-events-none scale-[1.02] opacity-0 blur-md motion-reduce:scale-100 motion-reduce:blur-none"
						}`}
						src={loaded.has(i) ? c.src : undefined}
						poster={c.poster}
						aria-label={c.alt}
						aria-hidden={i !== active}
						muted
						playsInline
						preload={loaded.has(i) ? "auto" : "none"}
					/>
				))}
			</div>

			<div role="tablist" aria-label="What Slice can do" className="mx-auto mt-5 grid max-w-[27rem] grid-cols-3 gap-[clamp(12px,3vw,24px)]">
				{CLIPS.map((c, i) => (
					<button
						key={c.id}
						ref={(el) => {
							tabs.current[i] = el;
						}}
						id={`hero-tab-${c.id}`}
						type="button"
						role="tab"
						aria-selected={i === active}
						aria-controls="hero-stage"
						tabIndex={i === active ? 0 : -1}
						onClick={() => i !== active && select(i)}
						onPointerEnter={() => setLoaded((s) => add(s, i))}
						onKeyDown={onKey}
						className="flex w-full cursor-pointer flex-col gap-2.5 pt-1 text-[13.5px] leading-[1.3] font-medium text-balance text-faint transition-colors duration-300 ease-quart hover:text-muted aria-selected:text-fg"
					>
						<span className="block h-0.5 w-full overflow-hidden rounded-full bg-line-strong">
							<span
								ref={(el) => {
									fills.current[i] = el;
								}}
								style={{ transform: "scaleX(0)" }}
								className={`block h-full origin-left rounded-full bg-fg transition-opacity duration-300 ${i === active ? "opacity-100" : "opacity-0"}`}
							/>
						</span>
						{c.label}
					</button>
				))}
			</div>
		</>
	);
}
