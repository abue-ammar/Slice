"use client";

import { useEffect, useLayoutEffect, useRef } from "react";
import { animate, type AnimationPlaybackControls } from "motion/react";

const STAGGER = 0.05;
const EASE = [0.65, 0, 0.35, 1] as const;
const OUT_FADE = { duration: 0.366, times: [0, 0.45, 1], ease: EASE };
const IN_FADE = { duration: 0.467, times: [0, 0.35, 1], ease: EASE };
const SPRING = { type: "spring", visualDuration: 0.383, bounce: 0.56 } as const;
const OUT_SPRING = { ...SPRING, visualDuration: 0.349 };
const SCALE = { duration: 0.35, ease: [0.22, 1, 0.36, 1] as const };
const OUT_SCALE = { ...SCALE, duration: 0.311 };

type Props = { words: string[]; index: number; className?: string };

export default function SwapText({ words, index, className = "" }: Props) {
	const stack = useRef<HTMLSpanElement>(null);
	const initial = useRef(index).current;
	const shown = useRef(index);
	const running = useRef<AnimationPlaybackControls[]>([]);
	const generation = useRef(0);

	const labels = () => Array.from(stack.current?.children ?? []) as HTMLElement[];

	const fit = (i: number, glide: boolean) => {
		const host = stack.current;
		const label = labels()[i];
		if (!host || !label) return;
		if (!glide) host.style.transition = "none";
		host.style.width = `${label.scrollWidth}px`;
		if (!glide) {
			void host.offsetWidth;
			host.style.transition = "";
		}
	};

	const settle = (i: number) => {
		labels().forEach((label, n) => {
			label.toggleAttribute("data-active", n === i);
			for (const char of Array.from(label.children) as HTMLElement[]) {
				char.getAnimations().forEach((a) => a.cancel());
				char.style.removeProperty("opacity");
				char.style.removeProperty("filter");
				char.style.removeProperty("transform");
			}
		});
	};

	useLayoutEffect(() => {
		fit(shown.current, false);
		const refit = () => fit(shown.current, false);
		document.fonts?.addEventListener("loadingdone", refit);
		document.fonts?.ready.then(refit);
		addEventListener("resize", refit);
		return () => {
			document.fonts?.removeEventListener("loadingdone", refit);
			removeEventListener("resize", refit);
			running.current.forEach((a) => a.stop());
		};
	}, []);

	useEffect(() => {
		const from = shown.current;
		if (from === index || !stack.current) return;
		shown.current = index;
		const token = ++generation.current;
		running.current.forEach((a) => a.stop());
		settle(from);

		if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
			settle(index);
			fit(index, false);
			return;
		}

		fit(index, true);
		const u = parseFloat(getComputedStyle(stack.current).fontSize) / 72;
		const blur = (px: number) => `blur(${px * u}px)`;
		const outgoing = Array.from(labels()[from].children);
		const incoming = Array.from(labels()[index].children);

		running.current = [
			...outgoing.flatMap((char, i) => {
				const delay = i * STAGGER;
				return [
					animate(char, { opacity: [1, 0.85, 0], filter: [blur(0), blur(12), blur(16)] }, { ...OUT_FADE, delay }),
					animate(
						char,
						{ y: [0, 16 * u], scale: [1, 0.7] },
						{ y: { ...OUT_SPRING, delay }, scale: { ...OUT_SCALE, delay } },
					),
				];
			}),
			...incoming.flatMap((char, i) => {
				const delay = i * STAGGER;
				return [
					animate(char, { opacity: [0, 0.7, 1], filter: [blur(8), blur(4), blur(0)] }, { ...IN_FADE, delay }),
					animate(char, { y: [-16 * u, 0], scale: [0.7, 1] }, { y: { ...SPRING, delay }, scale: { ...SCALE, delay } }),
				];
			}),
		];

		Promise.all(running.current).then(() => {
			if (token !== generation.current) return;
			requestAnimationFrame(() => token === generation.current && settle(index));
		});
	}, [index]);

	return (
		<span ref={stack} className={`inline-grid align-baseline whitespace-nowrap transition-[width] duration-600 ease-swap ${className}`} aria-hidden>
			{words.map((word, i) => (
				<span key={word} className="group/label col-start-1 row-start-1 inline-flex w-0 justify-self-start data-active:w-auto" data-active={i === initial ? "" : undefined}>
					{Array.from(word).map((char, j) => (
						<span key={j} className="inline-block opacity-0 blur-[0.11em] will-change-[filter,opacity,transform] [transform:translateY(-0.22em)_scale(0.7)] group-data-active/label:opacity-100 group-data-active/label:blur-none group-data-active/label:[transform:none]">
							{char === " " ? " " : char}
						</span>
					))}
				</span>
			))}
		</span>
	);
}
