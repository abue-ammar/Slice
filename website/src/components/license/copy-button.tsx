"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { doc } from "@/lib/doc";
import { blurIn, spring } from "@/lib/motion";

const ICON = {
	copy: (
		<>
			<rect x="5.5" y="5.5" width="8" height="8" rx="2" fill="none" stroke="currentColor" strokeWidth="1.4" />
			<path d="M10.5 3.5v-.5a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
		</>
	),
	check: <path d="m3.5 8.5 3 3 6-7" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />,
};

export default function CopyButton({ text, label = "Copy license" }: { text: string; label?: string }) {
	const [copied, setCopied] = useState(false);
	const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
	useEffect(() => () => clearTimeout(timer.current), []);

	const copy = async () => {
		try {
			await navigator.clipboard.writeText(text);
		} catch {
			return;
		}
		setCopied(true);
		clearTimeout(timer.current);
		timer.current = setTimeout(() => setCopied(false), 1600);
	};

	return (
		<motion.button type="button" className={doc.pill} onClick={copy} whileTap={{ scale: 0.97 }} transition={spring.snappy} layout>
			<span className="grid size-3.5 *:col-start-1 *:row-start-1">
				<AnimatePresence mode="popLayout" initial={false}>
					<motion.svg key={copied ? "check" : "copy"} width="14" height="14" viewBox="0 0 16 16" aria-hidden {...blurIn} transition={spring.snappy}>
						{copied ? ICON.check : ICON.copy}
					</motion.svg>
				</AnimatePresence>
			</span>
			<AnimatePresence mode="popLayout" initial={false}>
				<motion.span
					key={copied ? "copied" : "idle"}
					initial={{ opacity: 0, y: 6, filter: "blur(2px)" }}
					animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
					exit={{ opacity: 0, y: -6, filter: "blur(2px)" }}
					transition={spring.smooth}
					role="status"
					aria-live="polite"
				>
					{copied ? "Copied" : label}
				</motion.span>
			</AnimatePresence>
		</motion.button>
	);
}
