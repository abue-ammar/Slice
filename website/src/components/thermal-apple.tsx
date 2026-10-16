"use client";

import { Suspense, useEffect, useState } from "react";
import { Heatmap } from "@paper-design/shaders-react";

const LOGO = "/media/apple-logo.png";

const COLORS = ["#2346b8", "#3d72f2", "#7fb0ff", "#d6e7ff", "#fff1d4", "#ffc48a", "#ff9150"];

function Thermal({ still, onReady }: { still: boolean; onReady: () => void }) {
	useEffect(() => {
		let inner = 0;
		const outer = requestAnimationFrame(() => (inner = requestAnimationFrame(onReady)));
		return () => {
			cancelAnimationFrame(outer);
			cancelAnimationFrame(inner);
		};
	}, [onReady]);

	return (
		<Heatmap
			className="absolute inset-0 opacity-0 transition-opacity duration-900 ease-settle group-data-ready/apple:opacity-100"
			image={LOGO}
			suspendWhenProcessingImage
			colorBack="#00000000"
			colors={COLORS}
			contour={0.6}
			angle={20}
			noise={0}
			innerGlow={0.6}
			outerGlow={0.12}
			speed={still ? 0 : 0.45}
			scale={0.75}
			fit="contain"
			minPixelRatio={2}
		/>
	);
}

export default function ThermalApple() {
	const [mounted, setMounted] = useState(false);
	const [ready, setReady] = useState(false);
	const [still, setStill] = useState(false);

	useEffect(() => {
		setStill(matchMedia("(prefers-reduced-motion: reduce)").matches);
		setMounted(!!document.createElement("canvas").getContext("webgl2"));
	}, []);

	return (
		<span className="group/apple relative -ml-[0.06em] mr-[0.02em] inline-block size-[1.04em] align-[-0.16em]" data-ready={ready || undefined} aria-hidden>
			<span className="absolute inset-[12.5%] bg-fg transition-[opacity,background-color] duration-900 ease-settle [mask:url(/media/apple-logo.png)_center/contain_no-repeat] group-data-ready/apple:bg-[#1d2a52]" />
			{mounted && (
				<Suspense fallback={null}>
					<Thermal still={still} onReady={() => setReady(true)} />
				</Suspense>
			)}
		</span>
	);
}
