"use client";

import { useEffect, useRef, useState } from "react";
import StepPlayer from "./step-player";

type Clip = { id: string; label: string; src: string; poster: string; alt: string; rest: number };

const CLIPS: Clip[] = [
	{
		id: "annotations",
		label: "Annotations",
		src: "/media/annotations.mp4",
		poster: "/media/annotations.jpg",
		alt: "The Slice README on GitHub being marked up while recording: a red pen scribble, a box around the Product Hunt badge and an arrow pointing at the title, as the view zooms in.",
		rest: 0,
	},
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
	const [playing, setPlaying] = useState(true);
	const [loaded, setLoaded] = useState(() => new Set([0]));
	const stage = useRef<HTMLDivElement>(null);
	const videos = useRef<(HTMLVideoElement | null)[]>([]);
	const progress = useRef(0);
	const on = useRef(true);
	const visible = useRef(false);

	const peek = (i: number) => setLoaded((s) => add(s, i));

	const pick = (i: number) => {
		on.current = true;
		setPlaying(true);
		setLoaded((s) => add(s, i, (i + 1) % CLIPS.length));
		setActive(i);
	};

	const toggle = () => {
		on.current = !on.current;
		setPlaying(on.current);
		const video = videos.current[active];
		if (!video) return;
		if (on.current && visible.current && !video.ended) video.play().catch(() => {});
		else video.pause();
	};

	useEffect(() => {
		if (!matchMedia("(prefers-reduced-motion: reduce)").matches) return;
		on.current = false;
		setPlaying(false);
	}, []);

	useEffect(() => {
		const video = videos.current[active];
		videos.current.forEach((v, i) => i !== active && v?.pause());
		progress.current = 0;
		if (!video || !stage.current) return;

		video.currentTime = 0;
		let rested = 0;
		let last = performance.now();
		let frame = 0;

		const observer = new IntersectionObserver(
			([e]) => {
				visible.current = e.isIntersecting;
				if (visible.current && on.current && !video.ended) video.play().catch(() => {});
				else video.pause();
				if (visible.current) setLoaded((s) => add(s, (active + 1) % CLIPS.length));
			},
			{ threshold: 0.15 },
		);
		observer.observe(stage.current);

		const tick = (now: number) => {
			const dt = (now - last) / 1000;
			last = now;
			const duration = video.duration;
			if (Number.isFinite(duration) && duration > 0) {
				if (video.ended && visible.current && on.current) rested += dt;
				progress.current = Math.min(1, (video.ended ? duration + rested : video.currentTime) / (duration + CLIPS[active].rest));
				if (progress.current >= 1) {
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

	return (
		<>
			<div
				ref={stage}
				id="hero-stage"
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

			<div className="mt-5 flex flex-col items-center gap-3">
				<StepPlayer
					labels={CLIPS.map((c) => c.label)}
					at={active}
					playing={playing}
					progress={progress}
					onPick={pick}
					onPeek={peek}
					onToggle={toggle}
				/>
				<p key={active} className="blur-in text-[13.5px] font-medium text-muted [--i:0]" aria-live="polite">
					{CLIPS[active].label}
				</p>
			</div>
		</>
	);
}
