"use client";

import { useId, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import HoverGroup from "@/components/ui/hover-group";
import { spring } from "@/lib/motion";
import type { Question } from "./content";

export default function Faq({ items }: { items: Question[] }) {
	const [open, setOpen] = useState<number[]>([]);
	const id = useId();
	const toggle = (i: number) => setOpen((list) => (list.includes(i) ? list.filter((n) => n !== i) : [...list, i]));

	return (
		<HoverGroup item="button" pill="rounded-xl bg-surface">
			<div className="mt-2 flex flex-col">
				{items.map((item, i) => {
					const expanded = open.includes(i);
					return (
						<div key={item.q} className="border-b border-line">
							<h3>
								<button
									type="button"
									className="group/q -mx-3 my-1 flex w-[calc(100%+24px)] cursor-pointer items-center justify-between gap-6 rounded-xl p-3 text-left text-[15px] text-fg"
									aria-expanded={expanded}
									aria-controls={`${id}-${i}`}
									onClick={() => toggle(i)}
								>
									<span>{item.q}</span>
									<motion.svg
										width="14"
										height="14"
										viewBox="0 0 16 16"
										aria-hidden
										className="flex-none text-muted transition-colors duration-200 ease-out group-hover/q:text-fg"
										animate={{ rotate: expanded ? 180 : 0 }}
										transition={spring.smooth}
									>
										<path d="m4 6 4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
									</motion.svg>
								</button>
							</h3>
							<AnimatePresence initial={false}>
								{expanded && (
									<motion.div
										id={`${id}-${i}`}
										className="overflow-hidden"
										initial={{ height: 0 }}
										animate={{ height: "auto" }}
										exit={{ height: 0 }}
										transition={{ type: "spring", duration: 0.34, bounce: 0 }}
									>
										<motion.p
											className="max-w-[58ch] pb-[18px] text-[14.5px] leading-[1.65] text-muted"
											initial={{ opacity: 0, y: -4, filter: "blur(2px)" }}
											animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
											exit={{ opacity: 0, y: -4, filter: "blur(2px)" }}
											transition={{ duration: 0.3, ease: [0.23, 1, 0.32, 1] }}
										>
											{item.a}
										</motion.p>
									</motion.div>
								)}
							</AnimatePresence>
						</div>
					);
				})}
			</div>
		</HoverGroup>
	);
}
