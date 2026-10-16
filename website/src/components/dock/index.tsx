"use client";

import { useEffect, useRef, useState } from "react";
import {
	animate,
	motion,
	useMotionValue,
	useSpring,
	useTransform,
	type AnimationPlaybackControls,
	type MotionValue,
	type Transition,
} from "motion/react";
import { useReducedMotion } from "@/lib/use-reduced-motion";

const REST = 58;
const PEAK = 84;
const COMPACT = { rest: 44, peak: 62, query: "(max-width: 480px)" };
const REACH = 150;
const SIZE_SPRING = { mass: 0.1, stiffness: 170, damping: 12 };
const TOOLTIP_DELAY = 300;
const HOP: { y: number[]; transition: Transition } = {
	y: [0, -22, 0, -9, 0],
	transition: { duration: 0.7, times: [0, 0.3, 0.55, 0.78, 1], ease: ["easeOut", "easeIn", "easeOut", "easeIn"] },
};
const SQUASH: { scaleX: number[]; scaleY: number[]; transition: Transition } = {
	scaleY: [1, 1.04, 0.9, 1.02, 0.96, 1],
	scaleX: [1, 0.97, 1.08, 0.99, 1.03, 1],
	transition: { duration: 0.7, times: [0, 0.3, 0.55, 0.7, 0.8, 1] },
};

export type DockApp = { label: string; icon: string };
type Tip = { label: string; instant: boolean };

type Props = {
	apps: DockApp[];
	home: string;
	defaultRunning?: string[];
};

export default function Dock({ apps, home, defaultRunning = [] }: Props) {
	const reduceMotion = useReducedMotion();
	const mouseX = useMotionValue(Infinity);
	const homeRef = useRef<HTMLButtonElement>(null);
	const [tip, setTip] = useState<Tip | null>(null);
	const [running, setRunning] = useState(defaultRunning);
	const [compact, setCompact] = useState(false);
	const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

	const rest = () => {
		const box = homeRef.current?.getBoundingClientRect();
		mouseX.set(box ? box.left + box.width / 2 : Infinity);
	};

	useEffect(() => {
		const media = matchMedia(COMPACT.query);
		const sync = () => setCompact(media.matches);
		sync();
		media.addEventListener("change", sync);
		return () => media.removeEventListener("change", sync);
	}, []);

	useEffect(() => {
		mouseX.set(Infinity);
		const frame = requestAnimationFrame(rest);
		return () => cancelAnimationFrame(frame);
	}, [compact]);

	useEffect(() => {
		const frame = requestAnimationFrame(rest);
		addEventListener("resize", rest);
		return () => {
			cancelAnimationFrame(frame);
			removeEventListener("resize", rest);
			clearTimeout(timer.current);
		};
	}, []);

	const showTip = (label: string) => {
		clearTimeout(timer.current);
		if (tip) setTip({ label, instant: true });
		else timer.current = setTimeout(() => setTip({ label, instant: false }), TOOLTIP_DELAY);
	};

	const hideTip = () => {
		clearTimeout(timer.current);
		setTip(null);
	};

	return (
		<nav
			aria-label="Dock"
			className="flex h-[76px] items-end gap-1.5 rounded-3xl bg-[rgb(38_38_41/0.72)] px-2.5 pb-[9px] shadow-[inset_0_0_0_1px_rgb(255_255_255/0.09),inset_0_1px_0_rgb(255_255_255/0.06),0_24px_60px_-24px_rgb(0_0_0/0.9)] backdrop-blur-[24px] backdrop-saturate-150 max-[480px]:h-[60px] max-[480px]:gap-1 max-[480px]:rounded-[20px] max-[480px]:px-2 max-[480px]:pb-[7px]"
			onPointerMove={(e) => {
				if (reduceMotion || e.pointerType === "touch") return;
				mouseX.set(e.clientX);
			}}
			onPointerLeave={() => {
				rest();
				hideTip();
			}}
		>
			{apps.map((app) => (
				<DockItem
					key={app.label}
					app={app}
					buttonRef={app.label === home ? homeRef : undefined}
					sizes={compact ? [COMPACT.rest, COMPACT.peak] : [REST, PEAK]}
					mouseX={mouseX}
					tip={tip?.label === app.label ? tip : null}
					onEnter={() => showTip(app.label)}
					onFocus={() => setTip({ label: app.label, instant: false })}
					onBlur={hideTip}
					running={running.includes(app.label)}
					onLaunch={() => setRunning((r) => (r.includes(app.label) ? r : [...r, app.label]))}
				/>
			))}
		</nav>
	);
}

type ItemProps = {
	app: DockApp;
	buttonRef?: React.RefObject<HTMLButtonElement | null>;
	sizes: [number, number];
	mouseX: MotionValue<number>;
	tip: Tip | null;
	onEnter: () => void;
	onFocus: () => void;
	onBlur: () => void;
	running: boolean;
	onLaunch: () => void;
};

function DockItem({ app, buttonRef, sizes, mouseX, tip, onEnter, onFocus, onBlur, running, onLaunch }: ItemProps) {
	const own = useRef<HTMLButtonElement>(null);
	const ref = buttonRef ?? own;
	const reduceMotion = useReducedMotion();
	const hop = useRef<AnimationPlaybackControls[]>([]);
	useEffect(() => () => hop.current.forEach((a) => a.stop()), []);

	const distance = useTransform(mouseX, (x) => {
		const box = ref.current?.getBoundingClientRect();
		return box ? x - box.left - box.width / 2 : Infinity;
	});
	const [rest, peak] = sizes;
	const target = useTransform(distance, [-REACH, 0, REACH], [rest, peak, rest]);
	const size = useSpring(target, SIZE_SPRING);

	const launch = () => {
		if (running) return;
		onLaunch();
		if (reduceMotion || !ref.current) return;
		hop.current.forEach((a) => a.stop());
		hop.current = [
			animate(ref.current, { y: HOP.y }, HOP.transition),
			animate(ref.current, { scaleX: SQUASH.scaleX, scaleY: SQUASH.scaleY }, SQUASH.transition),
		];
	};

	return (
		<span className="relative flex flex-none">
			<motion.button
				ref={ref}
				type="button"
				aria-label={running ? `${app.label}, running` : app.label}
				style={{ width: size, height: size, originY: 1 }}
				className="grid flex-none cursor-default place-items-center transition-[scale] duration-150 ease-quart active:scale-96 focus-visible:rounded-[22%] focus-visible:outline-fg focus-visible:outline-offset-2"
				onPointerEnter={(e) => e.pointerType !== "touch" && onEnter()}
				onClick={launch}
				onFocus={onFocus}
				onBlur={onBlur}
			>
				<img src={app.icon} alt="" draggable={false} className="pointer-events-none block size-full select-none [-webkit-user-drag:none]" />
			</motion.button>
			<span aria-hidden className="pointer-events-none absolute bottom-full left-1/2 mb-3.5 -translate-x-1/2 translate-y-1 rounded-[7px] bg-[rgb(44_44_47/0.95)] px-[9px] py-1 text-[12.5px] font-medium whitespace-nowrap text-fg opacity-0 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.1),0_6px_16px_-6px_rgb(0_0_0/0.7)] transition-[opacity,translate] duration-150 ease-out data-instant:transition-none data-shown:translate-y-0 data-shown:opacity-100" data-shown={tip ? "" : undefined} data-instant={tip?.instant ? "" : undefined}>
				{app.label}
			</span>
			<span aria-hidden className="pointer-events-none absolute top-[calc(100%+3px)] left-1/2 -ml-0.5 size-1 scale-50 rounded-full bg-white/75 opacity-0 transition-[opacity,scale] duration-150 ease-quart data-on:scale-100 data-on:opacity-100 data-on:duration-200 data-on:delay-385 motion-reduce:data-on:delay-0" data-on={running ? "" : undefined} />
		</span>
	);
}
