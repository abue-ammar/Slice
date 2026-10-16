"use client";

import { useEffect, useState } from "react";
import SwapText from "./swap-text";
import ThermalApple from "./thermal-apple";

const WORDS = ["demos,", "tutorials,", "walkthroughs,", "launch videos,"];

export default function HeroTitle() {
	const [index, setIndex] = useState(0);

	useEffect(() => {
		if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
		const timer = setInterval(() => setIndex((i) => (i + 1) % WORDS.length), 2700);
		return () => clearInterval(timer);
	}, []);

	return (
		<h1 className="m-0 font-rounded text-[clamp(36px,5.4vw,62px)] leading-[1.1] font-bold tracking-[-0.022em] text-fg max-[520px]:text-[clamp(22px,7.2vw,36px)]">
			<span className="sr-only">Polished demos, straight from your Mac.</span>
			<span className="block whitespace-nowrap" aria-hidden>
				Polished <SwapText words={WORDS} index={index} />
			</span>
			<span className="block whitespace-nowrap" aria-hidden>
				straight from your <ThermalApple />
				Mac.
			</span>
		</h1>
	);
}
