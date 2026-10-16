"use client";

import { useLayoutEffect, useRef, useState, type RefObject } from "react";
import { AnchorProvider, ScrollProvider, TOCItem, useActiveAnchors, type TOCItemType } from "fumadocs-core/toc";
import { AnimatePresence, motion, useMotionValueEvent, useScroll, useSpring, type MotionValue } from "motion/react";
import HoverGroup from "@/components/ui/hover-group";
import { blurIn, spring } from "@/lib/motion";

function ProgressRing({ progress }: { progress: MotionValue<number> }) {
	return (
		<svg viewBox="0 0 16 16" width="14" height="14" className="-rotate-90" aria-hidden>
			<circle cx="8" cy="8" r="6" fill="none" strokeWidth="2" className="stroke-surface-strong" />
			<motion.circle cx="8" cy="8" r="6" fill="none" strokeWidth="2" strokeLinecap="round" className="stroke-[rgb(237_237_237/0.7)]" style={{ pathLength: progress }} />
		</svg>
	);
}

function ReadingProgress() {
	const { scrollYProgress } = useScroll();
	const progress = useSpring(scrollYProgress, { stiffness: 200, damping: 30, restDelta: 0.001 });
	const [percent, setPercent] = useState(0);
	useMotionValueEvent(scrollYProgress, "change", (value) => {
		const next = Math.round(Math.min(1, Math.max(0, value)) * 100);
		setPercent((current) => (current === next ? current : next));
	});
	return (
		<span className="inline-flex items-center gap-1.5 text-[11px] font-medium text-muted tabular-nums" aria-label={`${percent}% read`}>
			{percent}%
			<ProgressRing progress={progress} />
		</span>
	);
}

function ActiveBlock({ list }: { list: RefObject<HTMLUListElement | null> }) {
	const active = useActiveAnchors();
	const [block, setBlock] = useState<{ top: number; height: number; instant: boolean } | null>(null);

	useLayoutEffect(() => {
		const element = list.current;
		if (!element) return;
		const measure = () => {
			const rows = active
				.map((id) => element.querySelector<HTMLElement>(`a[href="#${CSS.escape(id)}"]`))
				.filter((row): row is HTMLElement => row !== null);
			if (rows.length === 0) return setBlock(null);
			const origin = element.getBoundingClientRect().top;
			const top = Math.min(...rows.map((row) => row.getBoundingClientRect().top)) - origin;
			const bottom = Math.max(...rows.map((row) => row.getBoundingClientRect().bottom)) - origin;
			setBlock((previous) => ({ top, height: bottom - top, instant: previous === null }));
		};
		measure();
		const observer = new ResizeObserver(measure);
		observer.observe(element);
		return () => observer.disconnect();
	}, [active, list]);

	return (
		<motion.span
			aria-hidden
			className="pointer-events-none absolute inset-x-0 top-0 -z-1 rounded-lg bg-surface will-change-transform"
			initial={false}
			animate={block ? { y: block.top, height: block.height, opacity: 1 } : { opacity: 0 }}
			transition={{ default: block?.instant ? { duration: 0 } : spring.glide, opacity: { duration: 0.2 } }}
		/>
	);
}

function Items({ items, list }: { items: TOCItemType[]; list: RefObject<HTMLUListElement | null> }) {
	return (
		<HoverGroup item="a" pill="rounded-lg bg-[rgb(25_25_27/0.6)]">
			<ul ref={list} className="relative flex flex-col pb-4">
				<ActiveBlock list={list} />
				{items.map((item, index) => (
					<motion.li
						key={item.url}
						initial={{ opacity: 0, x: -4, filter: "blur(2px)" }}
						animate={{ opacity: 1, x: 0, filter: "blur(0px)" }}
						transition={{ ...spring.smooth, delay: Math.min(index, 12) * 0.025 }}
					>
						<TOCItem href={item.url} className="block rounded-lg px-2.5 py-1.5 text-[13px] leading-[1.4] text-[rgb(143_143_143/0.75)] transition-colors duration-200 ease-out hover:text-fg data-[active=true]:text-fg">
							{item.title}
						</TOCItem>
					</motion.li>
				))}
			</ul>
		</HoverGroup>
	);
}

function Compact({ items }: { items: TOCItemType[] }) {
	const active = useActiveAnchors();
	const [open, setOpen] = useState(false);
	const list = useRef<HTMLUListElement>(null);
	const current = items.find((item) => item.url === `#${active[0]}`) ?? items[0];

	return (
		<div className="hidden rounded-[14px] bg-[#121214] inset-ring inset-ring-line-strong max-[1000px]:block" onClick={(e) => (e.target as HTMLElement).closest("a") && setOpen(false)}>
			<button type="button" className="flex h-11 w-full cursor-pointer items-center gap-2.5 px-3.5 text-fg" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
				<span className="relative min-w-0 flex-1 overflow-hidden text-left text-[14px] font-medium text-ellipsis whitespace-nowrap">
					<AnimatePresence mode="popLayout" initial={false}>
						<motion.span key={current.url} {...blurIn} transition={spring.smooth} className="block overflow-hidden text-ellipsis">
							{current.title}
						</motion.span>
					</AnimatePresence>
				</span>
				<ReadingProgress />
				<motion.svg width="12" height="12" viewBox="0 0 16 16" aria-hidden className="flex-none text-muted" animate={{ rotate: open ? 180 : 0 }} transition={spring.smooth}>
					<path d="m4 6 4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
				</motion.svg>
			</button>
			<AnimatePresence initial={false}>
				{open && (
					<motion.div
						className="max-h-[60dvh] overflow-y-auto px-1.5"
						initial={{ height: 0, opacity: 0 }}
						animate={{ height: "auto", opacity: 1 }}
						exit={{ height: 0, opacity: 0 }}
						transition={{ type: "spring", duration: 0.34, bounce: 0 }}
					>
						<Items items={items} list={list} />
					</motion.div>
				)}
			</AnimatePresence>
		</div>
	);
}

export default function Toc({ items }: { items: TOCItemType[] }) {
	const container = useRef<HTMLDivElement>(null);
	const list = useRef<HTMLUListElement>(null);
	const { scrollY } = useScroll();
	const [scrolled, setScrolled] = useState(false);
	useMotionValueEvent(scrollY, "change", (y) => setScrolled(y > 480));

	return (
		<AnchorProvider toc={items}>
			<div className="sticky top-28 max-[1000px]:hidden">
				<div className="mb-3.5 flex items-center justify-between gap-2">
					<p className="text-[13px] font-medium text-fg">On this page</p>
					<ReadingProgress />
				</div>
				<div ref={container} className="relative max-h-[calc(100dvh-260px)] overflow-y-auto overscroll-contain [scrollbar-width:none] mask-b-from-[calc(100%-24px)]">
					<ScrollProvider containerRef={container}>
						<Items items={items} list={list} />
					</ScrollProvider>
				</div>
				<AnimatePresence initial={false}>
					{scrolled && (
						<motion.button
							type="button"
							className="mt-5 inline-flex cursor-pointer items-center gap-2 text-[13px] text-muted transition-colors duration-200 ease-out hover:text-fg"
							{...blurIn}
							transition={spring.smooth}
							whileTap={{ scale: 0.96 }}
							onClick={() => window.scrollTo({ top: 0, behavior: "smooth" })}
						>
							<svg width="14" height="14" viewBox="0 0 16 16" aria-hidden>
								<path d="M8 13V3M4 7l4-4 4 4" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
							</svg>
							Back to top
						</motion.button>
					)}
				</AnimatePresence>
			</div>
			<Compact items={items} />
		</AnchorProvider>
	);
}
