"use client";

import { useEffect, useRef, useState, type MouseEvent } from "react";
import { liquidMetalFragmentShader, ShaderMount } from "@paper-design/shaders";

const SPEED = { rest: 0.6, hover: 1, click: 2.4 };

const UNIFORMS = {
	u_repetition: 4,
	u_softness: 0.4,
	u_shiftRed: 0.05,
	u_shiftBlue: 0.2,
	u_distortion: 0.1,
	u_contour: 0.4,
	u_angle: 60,
	u_scale: 8,
	u_shape: 1,
	u_offsetX: 0.1,
	u_offsetY: -0.1,
	u_colorBack: [0, 0, 0, 0],
	u_colorTint: [0.62, 0.78, 1, 0.7],
};

type Props = {
	href: string;
	children: React.ReactNode;
	width?: number;
	height?: number;
};

export default function MetalButton({ href, children, width = 200, height = 48 }: Props) {
	const host = useRef<HTMLDivElement>(null);
	const shader = useRef<ShaderMount | null>(null);
	const hovered = useRef(false);
	const id = useRef(0);
	const [pressed, setPressed] = useState(false);
	const [ripples, setRipples] = useState<{ x: number; y: number; id: number }[]>([]);

	useEffect(() => {
		if (!host.current) return;
		const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
		try {
			shader.current = new ShaderMount(host.current, liquidMetalFragmentShader, UNIFORMS, undefined, still ? 0 : SPEED.rest);
		} catch {
		}
		return () => {
			shader.current?.dispose();
			shader.current = null;
		};
	}, []);

	const hover = (on: boolean) => {
		hovered.current = on;
		if (!on) setPressed(false);
		shader.current?.setSpeed(on ? SPEED.hover : SPEED.rest);
	};

	const click = (event: MouseEvent<HTMLAnchorElement>) => {
		shader.current?.setSpeed(SPEED.click);
		setTimeout(() => shader.current?.setSpeed(hovered.current ? SPEED.hover : SPEED.rest), 300);
		const rect = event.currentTarget.getBoundingClientRect();
		const ripple = { x: event.clientX - rect.left, y: event.clientY - rect.top, id: id.current++ };
		setRipples((list) => [...list, ripple]);
		setTimeout(() => setRipples((list) => list.filter((r) => r.id !== ripple.id)), 600);
	};

	return (
		<span className="group/metal relative inline-block flex-none" data-pressed={pressed || undefined} style={{ width, height }}>
			<span className="absolute inset-0 z-1 rounded-full shadow-[0_10px_28px_-12px_rgb(77_141_255/0.4),0_1px_3px_rgb(0_0_0/0.4)] transition-[translate,scale] duration-500 ease-press group-data-pressed/metal:translate-y-px group-data-pressed/metal:scale-98">
				<span ref={host} className="absolute inset-0 overflow-hidden rounded-[inherit] bg-linear-to-b from-[#d6e4ff] to-[#7aa6f7] [&_canvas]:absolute! [&_canvas]:inset-0! [&_canvas]:block! [&_canvas]:size-full! [&_canvas]:rounded-full!" />
			</span>
			<span className="absolute inset-[1.5px] z-2 rounded-full bg-[linear-gradient(180deg,#26272b_0%,#0e0e10_55%,#050506_100%)] shadow-[inset_0_1px_0_rgb(160_196_255/0.16)] transition-[translate,scale,box-shadow] duration-500 ease-press group-data-pressed/metal:translate-y-px group-data-pressed/metal:scale-98 group-data-pressed/metal:shadow-[inset_0_2px_4px_rgb(0_0_0/0.4),inset_0_1px_2px_rgb(0_0_0/0.3)]" />
			<span className="pointer-events-none absolute inset-0 z-3 flex items-center justify-center gap-2 rounded-full text-[15px] font-medium whitespace-nowrap text-[#f2f4f8] [text-shadow:0_1px_2px_rgb(0_0_0/0.6)] transition-[translate,scale] duration-500 ease-press group-data-pressed/metal:translate-y-px group-data-pressed/metal:scale-98">{children}</span>
			<a
				href={href}
				className="absolute inset-0 z-4 overflow-hidden rounded-full focus-visible:rounded-full focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-accent"
				onClick={click}
				onPointerEnter={() => hover(true)}
				onPointerLeave={() => hover(false)}
				onPointerDown={() => setPressed(true)}
				onPointerUp={() => setPressed(false)}
			>
				{ripples.map((r) => (
					<span key={r.id} aria-hidden className="pointer-events-none absolute size-5 animate-ripple rounded-full bg-[radial-gradient(circle,rgb(255_255_255/0.4)_0%,rgb(255_255_255/0)_70%)]" style={{ left: r.x, top: r.y }} />
				))}
				<span className="sr-only">{children}</span>
			</a>
		</span>
	);
}
