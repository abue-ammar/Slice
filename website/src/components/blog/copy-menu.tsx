"use client";

import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { AnimatePresence, motion, type Transition } from "motion/react";
import HoverGroup from "@/components/ui/hover-group";
import RollingLabel from "@/components/ui/rolling-label";
import { blurIn, spring } from "@/lib/motion";
import { ChatGPTIcon, ClaudeIcon, PerplexityIcon } from "./assistant-icons";

const SEGMENT =
	"flex h-8 cursor-pointer items-center bg-surface text-[13px] text-muted transition-[color,background-color] duration-200 ease-out outline-offset-2 hover:bg-surface-strong hover:text-fg focus-visible:outline-2 aria-expanded:bg-surface-strong aria-expanded:text-fg";

const OPEN: Transition = { type: "spring", duration: 0.34, bounce: 0 };
const CLOSE: Transition = { duration: 0.16, ease: [0.4, 0, 1, 1] };

const noop = () => () => {};

const ICONS = {
	copy: (
		<>
			<rect x="5.5" y="5.5" width="8" height="8" rx="2" fill="none" stroke="currentColor" strokeWidth="1.4" />
			<path d="M10.5 3.5v-.5a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
		</>
	),
	check: <path d="m3.5 8.5 3 3 6-7" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />,
	link: (
		<path
			d="M6.75 9.25a2.75 2.75 0 0 0 3.9 0l2.1-2.1a2.75 2.75 0 0 0-3.9-3.9l-.6.6M9.25 6.75a2.75 2.75 0 0 0-3.9 0l-2.1 2.1a2.75 2.75 0 0 0 3.9 3.9l.6-.6"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.4"
			strokeLinecap="round"
		/>
	),
	chevron: <path d="m4 6 4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />,
};

function Glyph({ name, className = "size-3.5" }: { name: keyof typeof ICONS; className?: string }) {
	return (
		<span className={`grid ${className} *:col-start-1 *:row-start-1`}>
			<AnimatePresence mode="popLayout" initial={false}>
				<motion.svg key={name} viewBox="0 0 16 16" className="size-full" aria-hidden {...blurIn} transition={spring.snappy}>
					{ICONS[name]}
				</motion.svg>
			</AnimatePresence>
		</span>
	);
}

function useCopy() {
	const [copied, setCopied] = useState<string | null>(null);
	const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
	useEffect(() => () => clearTimeout(timer.current), []);
	const copy = async (key: string, text: string) => {
		try {
			await navigator.clipboard.writeText(text);
		} catch {
			return false;
		}
		setCopied(key);
		clearTimeout(timer.current);
		timer.current = setTimeout(() => setCopied(null), 1600);
		return true;
	};
	return { copied, copy };
}

const ROW = "flex h-9 w-full cursor-pointer items-center gap-2.5 rounded-lg px-2.5 text-left text-[13px] text-fg outline-none select-none";

function Arrow() {
	return (
		<svg viewBox="0 0 16 16" className="size-3.5 text-muted/70 transition-transform duration-200 ease-out group-hover/item:translate-x-px group-hover/item:-translate-y-px" aria-hidden>
			<path d="M5 11 11 5M6 5h5v5" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
		</svg>
	);
}

function MenuLink({ href, icon, children }: { href: string; icon: ReactNode; children: string }) {
	return (
		<a role="menuitem" href={href} target="_blank" rel="noreferrer" className={`group/item ${ROW}`}>
			<span className="grid size-5 place-items-center">{icon}</span>
			<span className="flex-1">{children}</span>
			<Arrow />
		</a>
	);
}

export default function CopyMenu({ markdown }: { markdown: string }) {
	const [open, setOpen] = useState(false);
	const { copied, copy } = useCopy();
	const root = useRef<HTMLDivElement>(null);
	const page = useSyncExternalStore(noop, () => location.href.split("#")[0], () => "");
	const prompt = encodeURIComponent(`Read ${page}, I want to ask questions about it.`);

	useEffect(() => {
		if (!open) return;
		const onDown = (e: PointerEvent) => !root.current?.contains(e.target as Node) && setOpen(false);
		const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
		addEventListener("pointerdown", onDown);
		addEventListener("keydown", onKey);
		return () => {
			removeEventListener("pointerdown", onDown);
			removeEventListener("keydown", onKey);
		};
	}, [open]);

	return (
		<div ref={root} className="relative flex shrink-0 items-center gap-px">
			<motion.button
				type="button"
				onClick={() => void copy("page", markdown)}
				whileTap={{ scale: 0.97 }}
				transition={spring.snappy}
				className={`${SEGMENT} gap-1.5 rounded-l-full pr-3 pl-3 ${copied === "page" ? "text-fg" : ""}`}
			>
				<Glyph name={copied === "page" ? "check" : "copy"} />
				<RollingLabel value={copied === "page" ? "Copied" : "Copy page"} />
			</motion.button>
			<button
				type="button"
				aria-label="More ways to share this post"
				aria-haspopup="menu"
				aria-expanded={open}
				onClick={() => setOpen(!open)}
				className={`${SEGMENT} rounded-r-full pr-2.5 pl-2`}
			>
				<motion.span className="grid size-3.5" animate={{ rotate: open ? 180 : 0 }} transition={spring.smooth}>
					<svg viewBox="0 0 16 16" className="size-full" aria-hidden>
						{ICONS.chevron}
					</svg>
				</motion.span>
			</button>

			<AnimatePresence>
				{open && (
					<motion.div
						role="menu"
						initial={{ opacity: 0, scale: 0.94, y: -6, filter: "blur(8px)" }}
						animate={{ opacity: 1, scale: 1, y: 0, filter: "blur(0px)", transition: OPEN, transitionEnd: { filter: "none" } }}
						exit={{ opacity: 0, scale: 0.97, y: -4, filter: "blur(6px)", transition: CLOSE }}
						style={{ transformOrigin: "top right" }}
						className="absolute top-[calc(100%+8px)] right-0 z-50 w-60 rounded-2xl bg-[#121214] p-1.5 shadow-[0_0_0_1px_var(--color-line-strong),0_12px_32px_-8px_rgb(0_0_0/0.6)] will-change-[transform,opacity]"
					>
						<HoverGroup item='[role="menuitem"]' pill="rounded-lg bg-white/6">
							<button role="menuitem" type="button" className={ROW} onClick={() => void copy("link", page)}>
								<span className="grid size-5 place-items-center text-muted">
									<Glyph name={copied === "link" ? "check" : "link"} className="size-4" />
								</span>
								<span className="flex-1">
									<RollingLabel value={copied === "link" ? "Copied" : "Copy link"} />
								</span>
							</button>
							<p className="px-2.5 pt-2.5 pb-1 text-[11px] font-medium text-muted/70">Ask about this post</p>
							<MenuLink href={`https://chatgpt.com/?hints=search&q=${prompt}`} icon={<ChatGPTIcon className="size-4 text-fg" />}>
								Open in ChatGPT
							</MenuLink>
							<MenuLink href={`https://claude.ai/new?q=${prompt}`} icon={<ClaudeIcon className="size-4" />}>
								Open in Claude
							</MenuLink>
							<MenuLink href={`https://www.perplexity.ai/search/new?q=${prompt}`} icon={<PerplexityIcon className="size-4" />}>
								Open in Perplexity
							</MenuLink>
						</HoverGroup>
					</motion.div>
				)}
			</AnimatePresence>
		</div>
	);
}
