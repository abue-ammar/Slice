"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { site, socials } from "@/lib/site";
import { BrandGlyph } from "./glyphs";

const SETTLE = 24;

type Item = { label: string; href: string };

const LINKS: Item[] = [
	{ label: "Features", href: "/#features" },
	{ label: "Roadmap", href: "/roadmap" },
	{ label: "Blog", href: "/blog" },
];

const GROUPS: { label: string; items: Item[] }[] = [
	{
		label: "Slice",
		items: [
			{ label: "Download for Mac", href: site.download },
			{ label: "Features", href: "/#features" },
			{ label: "Roadmap", href: "/roadmap" },
			{ label: "Blog", href: "/blog" },
		],
	},
	{
		label: "Help",
		items: [
			{ label: "FAQ", href: "/#faq" },
			{ label: "Report a bug", href: `${site.repo}/issues/new` },
			{ label: "License", href: "/license" },
			{ label: "Credits", href: "/credits" },
		],
	},
	{
		label: "Community",
		items: socials.map((s) => ({ label: s.label, href: s.href })),
	},
];

const external = (href: string) => href.startsWith("http");

const stagger =
	"opacity-0 blur-[4px] -translate-y-1 transition-[opacity,filter,translate] duration-200 ease-quart motion-reduce:blur-none motion-reduce:translate-y-0 group-data-open/nav:opacity-100 group-data-open/nav:blur-none group-data-open/nav:translate-y-0 group-data-open/nav:duration-500 group-data-open/nav:ease-settle group-data-open/nav:delay-[calc(80ms+var(--i,0)*35ms)]";

function NavLink({ item, className, current }: { item: Item; className?: string; current?: boolean }) {
	return external(item.href) ? (
		<a href={item.href} className={className} target="_blank" rel="noreferrer">
			{item.label}
		</a>
	) : (
		<Link href={item.href} className={className} aria-current={current ? "page" : undefined}>
			{item.label}
		</Link>
	);
}

export default function Nav() {
	const [settled, setSettled] = useState(false);
	const [openOn, setOpenOn] = useState<string | null>(null);
	const pathname = usePathname();
	const open = openOn === pathname;
	const setOpen = (on: boolean) => setOpenOn(on ? pathname : null);

	useEffect(() => {
		const update = () => setSettled(scrollY > SETTLE);
		update();
		addEventListener("scroll", update, { passive: true });
		return () => removeEventListener("scroll", update);
	}, []);

	useEffect(() => {
		if (!open) return;
		const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpenOn(null);
		addEventListener("keydown", onKey);
		return () => removeEventListener("keydown", onKey);
	}, [open]);

	const isCurrent = (href: string) => (href === "/blog" ? pathname.startsWith("/blog") : pathname === href);
	const look = open ? "open" : settled ? "settled" : "top";

	return (
		<header
			className="group/nav pointer-events-none sticky top-0 z-50 h-[74px] px-(--gutter) pt-3.5 transition-[padding] duration-600 ease-glide data-settled:pt-2.5 motion-reduce:transition-none"
			data-settled={settled || undefined}
			data-open={open || undefined}
		>
			<div
				className="invisible fixed inset-0 bg-black/30 opacity-0 backdrop-blur-[6px] transition-[opacity,visibility] duration-400 ease-quart group-data-open/nav:pointer-events-auto group-data-open/nav:visible group-data-open/nav:opacity-100"
				onClick={() => setOpen(false)}
				aria-hidden
			/>

			<nav
				aria-label="Main"
				data-look={look}
				className="pointer-events-auto relative z-1 mx-auto flex max-w-site flex-col rounded-[18px] bg-[rgb(22_22_24/0.3)] pr-2.5 pl-3.5 shadow-[0_18px_40px_-18px_rgb(0_0_0/0)] inset-ring inset-ring-white/5 backdrop-blur-[8px] transition-[max-width,border-radius,background-color,backdrop-filter,box-shadow] duration-600 ease-glide motion-reduce:transition-none data-[look=open]:rounded-3xl data-[look=open]:bg-[rgb(20_20_22/0.72)] data-[look=open]:shadow-[0_30px_60px_-24px_rgb(0_0_0/0.8)] data-[look=open]:inset-ring-white/8 data-[look=open]:backdrop-blur-[10px] data-[look=open]:backdrop-saturate-120 data-[look=settled]:max-w-[920px] data-[look=settled]:bg-[rgb(22_22_24/0.78)] data-[look=settled]:shadow-[0_18px_40px_-18px_rgb(0_0_0/0.7)] data-[look=settled]:inset-ring-white/8 max-[520px]:pr-2 max-[520px]:pl-3"
			>
				<div className="flex h-[60px] items-center gap-7 transition-[height] duration-600 ease-glide group-data-settled/nav:h-[54px] motion-reduce:transition-none">
					<Link href="/" className="flex items-center gap-[9px] font-rounded text-[18px] font-semibold tracking-[-0.01em]">
						<Image src="/icon.png" alt="" width={28} height={28} priority className="-m-0.5" />
						<span>Slice</span>
					</Link>

					<div className="ml-auto flex items-center gap-6 text-[14.5px] text-muted max-[760px]:hidden">
						{LINKS.map((item) => (
							<NavLink
								key={item.href}
								item={item}
								current={isCurrent(item.href)}
								className="transition-colors duration-200 ease-quart hover:text-fg aria-[current=page]:text-fg"
							/>
						))}
						<button
							type="button"
							className="-mr-0.5 -ml-1 inline-flex h-[34px] cursor-pointer items-center gap-1.5 rounded-[10px] bg-white/4 px-[11px] text-muted inset-ring inset-ring-line transition-colors duration-200 ease-quart hover:bg-white/8 hover:text-fg aria-expanded:bg-white/8 aria-expanded:text-fg"
							aria-expanded={open}
							aria-controls="nav-panel"
							onClick={() => setOpen(!open)}
						>
							Explore
							<svg
								width="10"
								height="10"
								viewBox="0 0 10 10"
								aria-hidden
								className="transition-[rotate] duration-400 ease-glide group-data-open/nav:rotate-180 motion-reduce:transition-none"
							>
								<path d="m2 3.75 3 3 3-3" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
							</svg>
						</button>
					</div>

					<a
						href={site.download}
						className="inline-flex h-10 items-center gap-2 rounded-[11px] bg-brand px-4 text-[14.5px] font-medium whitespace-nowrap text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.18)] transition-[height,color,background-color,box-shadow,scale] duration-200 ease-quart hover:bg-white hover:text-black hover:shadow-none active:scale-97 group-data-settled/nav:h-9 max-[760px]:ml-auto max-[520px]:px-3.5"
					>
						<span className="-mt-0.5">
							<BrandGlyph id="apple" size={15} />
						</span>
						<span className="max-[520px]:hidden">Download for Mac</span>
						<span className="hidden max-[520px]:inline">Download</span>
					</a>

					<button
						type="button"
						className="relative -ml-[18px] hidden size-[38px] flex-none cursor-pointer rounded-[11px] bg-white/6 text-fg transition-colors duration-200 ease-quart hover:bg-white/10 max-[760px]:block"
						aria-label={open ? "Close menu" : "Open menu"}
						aria-expanded={open}
						aria-controls="nav-panel"
						onClick={() => setOpen(!open)}
					>
						<span className="absolute inset-x-3 top-[calc(50%-0.75px)] h-[1.5px] -translate-y-[3.5px] rounded-xs bg-current transition-[translate,rotate] duration-400 ease-glide group-data-open/nav:translate-y-0 group-data-open/nav:rotate-45 motion-reduce:transition-none" />
						<span className="absolute inset-x-3 top-[calc(50%-0.75px)] h-[1.5px] translate-y-[3.5px] rounded-xs bg-current transition-[translate,rotate] duration-400 ease-glide group-data-open/nav:translate-y-0 group-data-open/nav:-rotate-45 motion-reduce:transition-none" />
					</button>
				</div>

				<div
					id="nav-panel"
					className="invisible grid grid-rows-[0fr] transition-[grid-template-rows,visibility] duration-500 ease-glide group-data-open/nav:visible group-data-open/nav:grid-rows-[1fr] motion-reduce:transition-none"
					inert={!open}
				>
					<div className="min-h-0 overflow-hidden">
						<div
							className="mx-1 grid grid-cols-3 gap-6 border-t border-line pt-7 pb-8 max-[760px]:grid-cols-2 max-[760px]:gap-x-5 max-[760px]:gap-y-7 max-[760px]:pt-6 max-[760px]:pb-[26px]"
							onClick={(e) => (e.target as HTMLElement).closest("a") && setOpen(false)}
						>
							{GROUPS.map((group, g) => (
								<div key={group.label} className="flex flex-col items-start gap-1.5">
									<p className={`mb-1.5 text-[13px] text-faint ${stagger}`} style={{ "--i": g } as React.CSSProperties}>
										{group.label}
									</p>
									{group.items.map((item, i) => (
										<span key={item.label} className={stagger} style={{ "--i": g + i + 1 } as React.CSSProperties}>
											<NavLink
												item={item}
												current={isCurrent(item.href)}
												className="inline-block text-[19px] leading-normal font-medium tracking-[-0.015em] text-[#d4d4d6] transition-colors duration-200 ease-quart hover:text-white aria-[current=page]:text-white max-[760px]:text-[17px]"
											/>
										</span>
									))}
								</div>
							))}
						</div>
					</div>
				</div>
			</nav>
		</header>
	);
}
