"use client";

import { useState, type AnchorHTMLAttributes } from "react";
import { Metal, TONE_PARAMS } from "argentui";
import { BrandGlyph } from "./glyphs";

TONE_PARAMS.gunmetal = { ...TONE_PARAMS.gunmetal, colorBack: "#1c1f24", colorTint: "#c9d0da", shiftRed: 0.08, shiftBlue: 0.12, softness: 0.3, distortion: 0.08 };

type Props = {
	href: string;
	children: React.ReactNode;
	className?: string;
};

export default function MetalButton({ href, children, className = "" }: Props) {
	const [hot, setHot] = useState(false);
	const link: AnchorHTMLAttributes<HTMLAnchorElement> = { href };

	return (
		<Metal
			as="a"
			{...link}
			tone="gunmetal"
			finish="button"
			effect="flow"
			borderWidth={2}
			radius={999}
			halo={4}
			speed={hot ? 1.8 : 0.8}
			sheen
			onPointerEnter={() => setHot(true)}
			onPointerLeave={() => setHot(false)}
			onBlur={() => setHot(false)}
			onFocus={() => setHot(true)}
			className={`argent-btn h-12 flex-none justify-center font-sans [--argent-panel:#0a0a0c] [--argent-sheen:rgb(255_255_255/0.35)] *:[.argent-core]:transition-opacity *:[.argent-core]:duration-500 *:[.argent-core]:ease-settle hover:*:[.argent-core]:opacity-75 focus-visible:*:[.argent-core]:opacity-75 active:*:[.argent-core]:opacity-65 *:[.argent-content]:h-full *:[.argent-content]:gap-2 *:[.argent-content]:px-6 *:[.argent-content]:text-[15px] *:[.argent-content]:font-medium *:[.argent-content]:whitespace-nowrap ${className}`}
		>
			<BrandGlyph id="apple" size={15} />
			{children}
		</Metal>
	);
}
