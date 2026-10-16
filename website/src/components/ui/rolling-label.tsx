"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { spring } from "@/lib/motion";

export default function RollingLabel({ value }: { value: string }) {
	const inner = useRef<HTMLSpanElement>(null);
	const [width, setWidth] = useState<number>();

	useEffect(() => {
		const element = inner.current;
		if (!element) return;
		const observer = new ResizeObserver(([entry]) => setWidth(entry.borderBoxSize[0].inlineSize));
		observer.observe(element);
		return () => observer.disconnect();
	}, []);

	return (
		<span
			className="relative inline-flex overflow-hidden transition-[width] duration-300 ease-settle motion-reduce:transition-none"
			style={width === undefined ? undefined : { width }}
		>
			<span ref={inner} className="inline-grid w-max shrink-0 whitespace-nowrap" role="status" aria-live="polite">
				<AnimatePresence mode="popLayout" initial={false}>
					<motion.span
						key={value}
						className="col-start-1 row-start-1"
						initial={{ opacity: 0, y: 8, filter: "blur(2px)" }}
						animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
						exit={{ opacity: 0, y: -8, filter: "blur(2px)" }}
						transition={spring.smooth}
					>
						{value}
					</motion.span>
				</AnimatePresence>
			</span>
		</span>
	);
}
