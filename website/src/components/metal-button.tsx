"use client";

import { useEffect, useId, useRef, type CSSProperties, type PointerEvent } from "react";
import { siApple } from "simple-icons";
import { useReducedMotion } from "@/lib/use-reduced-motion";

const GLYPH = 18;
const MOTION = { speed: 0.8, attraction: 0.7 };
const EDGE = { width: 2.4, intensity: 1, speed: 1, prism: 0.8, flow: 0.75 };
const HOVER = 0.72;
const ANGLE = 135;

const RING: CSSProperties = {
	WebkitMask: "linear-gradient(#fff 0 0) content-box,linear-gradient(#fff 0 0)",
	WebkitMaskComposite: "xor",
	mask: "linear-gradient(#fff 0 0) content-box,linear-gradient(#fff 0 0)",
	maskComposite: "exclude",
};

const EDGE_PADDING = "var(--orb-edge-top,var(--orb-edge-width)) var(--orb-edge-right,var(--orb-edge-width)) var(--orb-edge-bottom,var(--orb-edge-width)) var(--orb-edge-left,var(--orb-edge-width))";

const EDGE_FILL: CSSProperties = {
	...RING,
	padding: EDGE_PADDING,
	background:
		"radial-gradient(ellipse at var(--orb-light-x,24%) var(--orb-light-y,14%),rgba(255,255,255,.86),transparent 38%),conic-gradient(from var(--orb-phase,-55deg) at var(--orb-pool-x,48%) var(--orb-pool-y,52%),#8995a6 0deg,#e6f0ff 21deg,#101621 42deg,#445268 56deg,#fff 68deg,#fff 80deg,var(--orb-edge-cool) 88deg,#181e2b 99deg,#cbd7e8 137deg,#69788e 163deg,#0a111b 183deg,#eff8ff 210deg,#fff 224deg,var(--orb-edge-warm) 232deg,#283a54 242deg,#a6b6cc 275deg,#e9f3ff 300deg,#192434 327deg,#8995a6 360deg)",
};

const EDGE_RIDGE: CSSProperties = {
	...RING,
	padding: "clamp(.45px,calc(var(--orb-edge-width)*.25),1px)",
	background:
		"conic-gradient(from var(--orb-counter,75deg),#fff 0deg,#d6e3f5 24deg,#0c1524 70deg,#fff 112deg,var(--orb-edge-cool) 131deg,#112034 166deg,#fff 205deg,#fff 239deg,var(--orb-edge-warm) 252deg,#131c2d 284deg,#bacadd 334deg,#fff 360deg)",
	opacity: EDGE.intensity,
};

const HOVER_EDGE: CSSProperties = {
	...RING,
	padding: EDGE_PADDING,
	background: "radial-gradient(ellipse 64% 170% at var(--orb-wake-x,50%) var(--orb-wake-y,50%),rgba(255,255,255,.98),transparent 56%)",
};

const WAKE: CSSProperties = {
	background:
		"radial-gradient(ellipse 42% 120% at var(--orb-wake-x,50%) var(--orb-wake-y,50%),rgba(240,249,255,.30),rgba(167,203,255,.10) 42%,transparent 76%)",
	boxShadow: "inset 0 0 16px rgba(216,233,255,.10)",
};

const ROOT_VARS = {
	"--orb-hover-intensity": HOVER,
	"--orb-edge-width": `${EDGE.width}px`,
	"--orb-edge-cool": `color-mix(in srgb,#80B8FF ${EDGE.prism * 100}%,#E8F0FA)`,
	"--orb-edge-warm": `color-mix(in srgb,#F4B777 ${EDGE.prism * 100}%,#E8F0FA)`,
} as CSSProperties;

const layer = "pointer-events-none absolute inset-0 rounded-[inherit] forced-colors:hidden";

type Props = {
	href: string;
	children: React.ReactNode;
	className?: string;
};

export default function MetalButton({ href, children, className = "" }: Props) {
	const gradientId = `orbit-icon-${useId().replace(/:/g, "")}`;
	const gradientRef = useRef<SVGLinearGradientElement>(null);
	const rootRef = useRef<HTMLAnchorElement>(null);
	const engineRef = useRef<{ wake: () => void } | null>(null);
	const input = useRef({ sx: 0.5, sy: 0.5, hovering: false, focused: false, pressed: false });
	const phaseRef = useRef(1.4);
	const reduced = useReducedMotion();

	useEffect(() => {
		const root = rootRef.current;
		if (!root) return;
		let frame = 0;
		let last = 0;
		let visible = true;
		let hover = 0;
		let sx = 0.5;
		let sy = 0.5;
		const set = (name: string, value: string) => root.style.setProperty(name, value);

		const draw = () => {
			const edgePhase = phaseRef.current * EDGE.speed;
			set("--orb-phase", `${edgePhase * 46 - 85}deg`);
			set("--orb-counter", `${-edgePhase * 31 + 75}deg`);
			set("--orb-pool-x", `${50 + Math.sin(edgePhase * 0.73) * 16 * EDGE.flow}%`);
			set("--orb-pool-y", `${50 + Math.cos(edgePhase * 0.57) * 22 * EDGE.flow}%`);
			const pull = hover * MOTION.attraction * HOVER;
			const lightX = 50 + Math.cos(edgePhase * 0.91) * 48;
			const lightY = 50 + Math.sin(edgePhase * 0.91) * 48;
			set("--orb-light-x", `${lightX + (sx * 100 - lightX) * pull}%`);
			set("--orb-light-y", `${lightY + (sy * 100 - lightY) * pull}%`);
			set("--orb-wake-x", `${sx * 100}%`);
			set("--orb-wake-y", `${sy * 100}%`);
			(["top", "right", "bottom", "left"] as const).forEach((side, index) => {
				const pooling = 1 + Math.sin(edgePhase * 1.13 + index * Math.PI * 0.5) * 0.28 * EDGE.flow;
				set(`--orb-edge-${side}`, `${EDGE.width * pooling}px`);
			});
			const shift = Math.sin(phaseRef.current * 0.8) * 35;
			gradientRef.current?.setAttribute("gradientTransform", `rotate(${ANGLE - 90 + shift * 0.45} .5 .5)`);
		};

		const tick = (now: number) => {
			frame = 0;
			if (!visible || document.hidden || reduced) {
				last = 0;
				return;
			}
			const dt = last ? Math.min(0.05, (now - last) / 1e3) : 1 / 60;
			last = now;
			const i = input.current;
			const k = 1 - Math.exp(-dt * 10);
			hover += ((i.hovering || i.focused ? 1 : 0) - hover) * k;
			sx += (i.sx - sx) * k;
			sy += (i.sy - sy) * k;
			phaseRef.current += dt * MOTION.speed;
			draw();
			frame = requestAnimationFrame(tick);
		};

		const wake = () => {
			if (!frame && !reduced && visible && !document.hidden) frame = requestAnimationFrame(tick);
		};
		const halt = () => {
			cancelAnimationFrame(frame);
			frame = 0;
			last = 0;
		};
		engineRef.current = { wake };
		const onVisibility = () => (document.hidden ? halt() : wake());
		const io = new IntersectionObserver((entries) => {
			visible = entries[0]?.isIntersecting ?? false;
			if (visible) wake();
			else halt();
		});
		io.observe(root);
		document.addEventListener("visibilitychange", onVisibility);
		draw();
		wake();

		return () => {
			halt();
			engineRef.current = null;
			io.disconnect();
			document.removeEventListener("visibilitychange", onVisibility);
		};
	}, [reduced]);

	const active = () => {
		rootRef.current?.setAttribute("data-active", String(input.current.hovering || input.current.focused));
		engineRef.current?.wake();
	};
	const press = (value: boolean) => {
		input.current.pressed = value;
		rootRef.current?.setAttribute("data-pressed", String(value));
		engineRef.current?.wake();
	};
	const pointer = (e: PointerEvent<HTMLAnchorElement>) => {
		const face = e.currentTarget.getBoundingClientRect();
		input.current.sx = Math.min(1, Math.max(0, (e.clientX - face.left) / Math.max(1, face.width)));
		input.current.sy = Math.min(1, Math.max(0, (e.clientY - face.top) / Math.max(1, face.height)));
	};

	return (
		<a
			ref={rootRef}
			href={href}
						className={`group/orb relative isolate inline-flex h-12 max-w-full flex-none rounded-full text-[#F6F8FC] [-webkit-tap-highlight-color:transparent] touch-manipulation focus-visible:outline-2 focus-visible:outline-offset-[5px] focus-visible:outline-[#749EE8] ${className}`}
			style={ROOT_VARS}
			onPointerEnter={(e) => {
				if (e.pointerType === "touch") return;
				input.current.hovering = true;
				pointer(e);
				active();
			}}
			onPointerMove={pointer}
			onPointerLeave={() => {
				input.current.hovering = false;
				press(false);
				active();
			}}
			onPointerDown={(e) => {
				if (e.button !== 0) return;
				pointer(e);
				press(true);
			}}
			onPointerUp={() => press(false)}
			onPointerCancel={() => press(false)}
			onFocus={(e) => {
				if (!e.currentTarget.matches(":focus-visible")) return;
				input.current.focused = true;
				input.current.sx = 0.5;
				input.current.sy = 0.5;
				active();
			}}
			onBlur={() => {
				input.current.focused = false;
				press(false);
				active();
			}}
			onKeyDown={(e) => !e.repeat && e.key === "Enter" && press(true)}
			onKeyUp={(e) => e.key === "Enter" && press(false)}
		>
			<svg width="0" height="0" aria-hidden className="pointer-events-none absolute">
				<defs>
					<linearGradient ref={gradientRef} id={gradientId} x1="0" y1="0" x2="1" y2="0" gradientTransform={`rotate(${ANGLE - 90} .5 .5)`}>
						<stop offset="0%" stopColor="#FFFFFF" />
						<stop offset="28%" stopColor="#7A879B" />
						<stop offset="43%" stopColor="#D7E4F5" />
						<stop offset="54%" stopColor="#FFFFFF" />
						<stop offset="65%" stopColor="#FFFFFF" />
						<stop offset="84%" stopColor="#7A879B" />
						<stop offset="100%" stopColor="#FFFFFF" />
					</linearGradient>
				</defs>
			</svg>
			<span
				className="relative isolate flex min-w-0 flex-1 items-center justify-center gap-2 rounded-full bg-[rgba(21,24,30,.91)] px-6 shadow-[0_12px_24px_-12px_rgba(0,0,0,0.45)] backdrop-blur-[18px] backdrop-saturate-[1.2] transition-[translate,scale] duration-180 ease-[cubic-bezier(.2,.8,.2,1)] group-data-[pressed=true]/orb:translate-y-px group-data-[pressed=true]/orb:scale-[.988] motion-reduce:transition-none motion-reduce:group-data-[pressed=true]/orb:translate-none motion-reduce:group-data-[pressed=true]/orb:scale-none forced-colors:bg-[ButtonFace] forced-colors:inset-ring forced-colors:inset-ring-[ButtonText]"
			>
				<span aria-hidden className={`${layer} opacity-0 transition-opacity duration-260 ease-out group-data-[active=true]/orb:opacity-(--orb-hover-intensity) motion-reduce:hidden`} style={WAKE} />
				<span
					aria-hidden
					className={`${layer} border border-[rgba(234,241,255,.16)] opacity-70 shadow-[inset_0_1px_2px_rgba(255,255,255,.22),inset_0_-1px_3px_rgba(0,0,0,.10)]`}
					style={{ background: "linear-gradient(145deg,rgba(255,255,255,.15),transparent 37%,rgba(255,255,255,.025) 70%,rgba(255,255,255,.09))" }}
				/>
				<span aria-hidden className={`${layer} blur-[3.5px]`} style={{ ...EDGE_FILL, opacity: EDGE.intensity * 0.4 }} />
				<span aria-hidden className={layer} style={{ ...EDGE_FILL, opacity: EDGE.intensity }} />
				<span aria-hidden className={layer} style={EDGE_RIDGE} />
				<span aria-hidden className={`${layer} opacity-0 transition-opacity duration-220 ease-out group-data-[active=true]/orb:opacity-(--orb-hover-intensity) motion-reduce:hidden`} style={HOVER_EDGE} />

				<svg
					width={GLYPH}
					height={GLYPH}
					viewBox="0 0 24 24"
					aria-hidden
					className="relative -mt-px block drop-shadow-[0_1px_1px_rgba(0,0,0,.4)] forced-colors:fill-[ButtonText]"
					fill={`url(#${gradientId})`}
				>
					<path d={siApple.path} />
				</svg>
				<span className="relative min-w-0 truncate text-[15px] font-medium tracking-[-0.01em] forced-colors:text-[ButtonText]">{children}</span>
			</span>
		</a>
	);
}
