"use client";

import { useRef, useState, type ReactNode } from "react";
import { motion } from "motion/react";
import { spring } from "@/lib/motion";

type Box = { x: number; y: number; width: number; height: number };
type Spot = { box: Box; visible: boolean; instant: boolean };

function measure(element: HTMLElement, container: HTMLElement): Box {
	const a = element.getBoundingClientRect();
	const b = container.getBoundingClientRect();
	return { x: a.left - b.left, y: a.top - b.top, width: a.width, height: a.height };
}

const same = (a: Box, b: Box) => a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;

function place(previous: Spot | null, box: Box): Spot {
	if (previous?.visible && same(previous.box, box)) return previous;
	return { box, visible: true, instant: !previous?.visible };
}

const hide = (previous: Spot | null) => (previous?.visible ? { ...previous, visible: false } : previous);

export default function HoverGroup({
	children,
	item = "a, button",
	pill,
	className,
}: {
	children: ReactNode;
	item?: string;
	pill: string;
	className?: string;
}) {
	const container = useRef<HTMLDivElement>(null);
	const [spot, setSpot] = useState<Spot | null>(null);

	const land = (target: EventTarget | null) => {
		const root = container.current;
		const element = (target as HTMLElement | null)?.closest<HTMLElement>(item);
		if (!root || !element || !root.contains(element)) return;
		const box = measure(element, root);
		setSpot((previous) => place(previous, box));
	};

	return (
		<div
			ref={container}
			className={className}
			style={{ position: "relative", isolation: "isolate" }}
			onPointerOver={(event) => event.pointerType !== "touch" && land(event.target)}
			onPointerLeave={() => setSpot(hide)}
			onFocus={(event) => (event.target as HTMLElement).matches(":focus-visible") && land(event.target)}
			onBlur={(event) => !container.current?.contains(event.relatedTarget as Node) && setSpot(hide)}
		>
			{spot && (
				<motion.span
					aria-hidden
					className={pill}
					style={{ position: "absolute", top: 0, left: 0, zIndex: -1, pointerEvents: "none" }}
					initial={{ ...spot.box, opacity: 0 }}
					animate={{ ...spot.box, opacity: spot.visible ? 1 : 0 }}
					transition={{
						default: spot.instant ? { duration: 0 } : spring.glide,
						opacity: { duration: spot.visible ? 0.2 : 0.28, ease: "easeOut" },
					}}
				/>
			)}
			{children}
		</div>
	);
}
