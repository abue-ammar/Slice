"use client";

import { AnimatePresence, motion, useMotionValue, useSpring, useTransform, type MotionValue } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { reveal } from "@/lib/reveal";
import { useReducedMotion } from "@/lib/use-reduced-motion";
import SectionHeading, { sectionClass } from "../section-heading";
import { QUESTIONS } from "./questions";

const RANGE = 110;
const MAX_SCALE = 1.04;
const TRACK_SPRING = { stiffness: 260, damping: 26, mass: 0.6 } as const;
const OPEN_SPRING = { type: "spring", visualDuration: 0.42, bounce: 0.2 } as const;
const CLOSE_SPRING = { type: "spring", visualDuration: 0.4, bounce: 0 } as const;
const ICON_SPRING = { type: "spring", visualDuration: 0.3, bounce: 0.25 } as const;

type RowProps = {
	index: number;
	q: string;
	a: React.ReactNode;
	pointerY: MotionValue<number>;
	centers: { current: number[] };
	active: boolean;
	onHover: () => void;
	onToggle: () => void;
	registerRef: (el: HTMLDivElement | null) => void;
	reduce: boolean;
};

function Row({ index, q, a, pointerY, centers, active, onHover, onToggle, registerRef, reduce }: RowProps) {
	const target = useTransform(pointerY, (y) => {
		const c = centers.current[index];
		if (c == null || !Number.isFinite(c)) return 1;
		return 1 + Math.max(0, 1 - Math.abs(y - c) / RANGE) * (MAX_SCALE - 1);
	});
	const scale = useSpring(target, TRACK_SPRING);
	const id = `faq-${index}`;

	return (
		<motion.div
			ref={registerRef}
			onMouseEnter={onHover}
			style={{ scale: reduce ? 1 : scale, zIndex: active ? 2 : 1 }}
			className="relative origin-center rounded-[14px] bg-card inset-ring inset-ring-line transition-shadow duration-300 ease-quart will-change-transform data-active:inset-ring-line-strong"
			data-active={active || undefined}
		>
			<button type="button" className="flex w-full cursor-pointer items-center justify-between gap-4 px-[18px] py-[15px] text-left text-[15px] font-medium text-fg focus-visible:rounded-[14px] focus-visible:-outline-offset-2" aria-expanded={active} aria-controls={id} onClick={onToggle}>
				<span>{q}</span>
				<motion.span aria-hidden className="flex-none text-[20px] leading-none font-light text-faint" animate={{ rotate: active ? 45 : 0 }} transition={ICON_SPRING}>
					+
				</motion.span>
			</button>

			<AnimatePresence initial={false}>
				{active && (
					<motion.div
						key="answer"
						id={id}
						initial={{ height: 0, opacity: 0, filter: reduce ? "none" : "blur(8px)" }}
						animate={{ height: "auto", opacity: 1, filter: "blur(0px)", transition: OPEN_SPRING }}
						exit={{ height: 0, opacity: 0, filter: reduce ? "none" : "blur(8px)", transition: CLOSE_SPRING }}
						className="overflow-hidden"
					>
						<p className="max-w-[36rem] px-[18px] pb-4 text-[14.5px] leading-[1.6] text-muted [&_a]:text-fg [&_a]:underline [&_a]:decoration-faint [&_a]:underline-offset-3 [&_code]:rounded-md [&_code]:bg-raised [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-[13px] [&_code]:text-fg">
							{a}
						</p>
					</motion.div>
				)}
			</AnimatePresence>
		</motion.div>
	);
}

export default function Faq() {
	const reduce = useReducedMotion();
	const pointerY = useMotionValue(-9999);
	const [active, setActive] = useState<number | null>(null);
	const rows = useRef<(HTMLDivElement | null)[]>([]);
	const centers = useRef<number[]>([]);

	useEffect(() => {
		const measure = () => {
			centers.current = rows.current.map((el) => {
				if (!el) return Infinity;
				const r = el.getBoundingClientRect();
				return r.top + r.height / 2;
			});
		};
		measure();
		const ro = new ResizeObserver(measure);
		rows.current.forEach((el) => el && ro.observe(el));
		addEventListener("scroll", measure, { capture: true, passive: true });
		addEventListener("resize", measure);
		return () => {
			ro.disconnect();
			removeEventListener("scroll", measure, { capture: true });
			removeEventListener("resize", measure);
		};
	}, []);

	return (
		<section id="faq" className={`${sectionClass} grid grid-cols-[minmax(0,4fr)_minmax(0,7fr)] items-start gap-[clamp(32px,6vw,80px)] max-[860px]:grid-cols-1`}>
			<div className="sticky top-[104px] max-[860px]:static">
				<SectionHeading title="Questions, answered." />
			</div>
			<div
				{...reveal(2)}
				className="flex flex-col gap-2"
				onMouseMove={(e) => pointerY.set(e.clientY)}
				onMouseLeave={() => {
					pointerY.set(-9999);
					setActive(null);
				}}
			>
				{QUESTIONS.map((item, i) => (
					<Row
						key={item.q}
						index={i}
						q={item.q}
						a={item.a}
						pointerY={pointerY}
						centers={centers}
						active={active === i}
						onHover={() => setActive(i)}
						onToggle={() => setActive((current) => (current === i ? null : i))}
						registerRef={(el) => {
							rows.current[i] = el;
						}}
						reduce={reduce}
					/>
				))}
			</div>
		</section>
	);
}
