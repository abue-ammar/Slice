import type { Transition } from "motion/react";

export const spring = {
	snappy: { type: "spring", stiffness: 400, damping: 28, mass: 0.8 },
	smooth: { type: "spring", stiffness: 220, damping: 24, mass: 1 },
	glide: { type: "spring", stiffness: 340, damping: 38, mass: 0.9 },
} satisfies Record<string, Transition>;

export const blurIn = {
	initial: { opacity: 0, scale: 0.96, filter: "blur(4px)" },
	animate: { opacity: 1, scale: 1, filter: "blur(0px)" },
	exit: { opacity: 0, scale: 0.96, filter: "blur(4px)" },
} as const;
