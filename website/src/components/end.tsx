import Image from "next/image";
import Link from "next/link";
import { site, socials } from "@/lib/site";
import { BrandGlyph } from "./glyphs";
import { license } from "./license/content";

type Item = { label: string; href: string };

const GROUPS: { label: string; items: Item[] }[] = [
	{
		label: "Slice",
		items: [
			{ label: "Download for Mac", href: site.download },
			{ label: "Features", href: "/#features" },
			{ label: "What’s new", href: "/blog" },
			{ label: "Roadmap", href: "/roadmap" },
		],
	},
	{
		label: "Help",
		items: [
			{ label: "FAQ", href: "/#faq" },
			{ label: "Report a bug", href: `${site.repo}/issues/new` },
			{
				label: "Suggest a feature",
				href: `${site.repo}/issues/new?labels=enhancement`,
			},
			{ label: "Get in touch", href: site.author.url },
		],
	},
	{
		label: "Source",
		items: [
			{ label: "Code on GitHub", href: site.repo },
			{ label: "All releases", href: `${site.repo}/releases` },
			{ label: "License", href: "/license" },
			{ label: "Credits", href: "/credits" },
		],
	},
];

const link = "w-fit text-[14.5px] text-muted transition-colors duration-200 ease-quart hover:text-fg";

function FooterLink({ item }: { item: Item }) {
	return item.href.startsWith("http") ? (
		<a href={item.href} className={link} target="_blank" rel="noreferrer">
			{item.label}
		</a>
	) : (
		<Link href={item.href} className={link}>
			{item.label}
		</Link>
	);
}

export default function End({ compact = false }: { compact?: boolean }) {
	return (
		<footer className={`px-(--gutter) ${compact ? "pt-24" : "pt-[clamp(112px,14vw,176px)]"}`}>
			<div className="relative mx-auto max-w-site overflow-hidden rounded-t-[28px] bg-[linear-gradient(to_bottom,rgb(255_255_255/0.035),rgb(255_255_255/0.012)_60%,transparent)] px-[clamp(22px,4.5vw,56px)] pt-[clamp(32px,4.5vw,52px)] pb-10">
				<div
					className="pointer-events-none absolute inset-x-[18%] top-0 h-px bg-[linear-gradient(90deg,transparent,rgb(77_141_255/0.7),transparent)]"
					aria-hidden
				/>
				<div className="pointer-events-none absolute inset-x-[25%] -top-10 h-20 rounded-full bg-[rgb(43_108_243/0.18)] blur-3xl" aria-hidden />

				<div className="relative flex items-center justify-between gap-6 max-[640px]:flex-col max-[640px]:items-start">
					<Link href="/" className="flex items-center gap-3.5">
						<Image src="/icon.png" alt="" width={44} height={44} className="-m-1" />
						<span className="flex flex-col">
							<span className="font-rounded text-[19px] leading-tight font-semibold tracking-[-0.01em] text-fg">{site.name}</span>
							<span className="text-[14px] leading-snug text-muted">{site.tagline}. Free, and it stays on your Mac.</span>
						</span>
					</Link>

					<a
						href={site.download}
						className="inline-flex h-10 flex-none items-center gap-2 rounded-[11px] bg-brand px-4 text-[14.5px] font-medium whitespace-nowrap text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.18)] transition-[color,background-color,box-shadow,scale] duration-200 ease-quart hover:bg-white hover:text-black hover:shadow-none active:scale-97"
					>
						<span className="-mt-0.5">
							<BrandGlyph id="apple" size={15} />
						</span>
						Download for Mac
					</a>
				</div>

				<nav
					aria-label="Footer"
					className="relative mt-[clamp(32px,4vw,44px)] grid grid-cols-3 gap-8 border-t border-line pt-[clamp(28px,3.5vw,40px)] max-[640px]:grid-cols-2 max-[640px]:gap-y-9"
				>
					{GROUPS.map((group) => (
						<div key={group.label} className="flex flex-col gap-2.5">
							<p className="mb-1 text-[14px] font-medium text-fg">{group.label}</p>
							{group.items.map((item) => (
								<FooterLink key={item.label} item={item} />
							))}
						</div>
					))}
				</nav>

				<div className="relative mt-[clamp(32px,4vw,44px)] flex items-center justify-between gap-6 border-t border-line pt-7 max-[640px]:flex-col-reverse max-[640px]:items-start">
					<div className="flex flex-col gap-1 text-[13px] text-faint">
						<span>
							<span className="text-muted">v{site.version}</span> · {license.type} · Made on a Mac by{" "}
							<a href={site.author.url} target="_blank" rel="noreferrer" className="text-muted transition-colors duration-200 ease-quart hover:text-fg">
								{site.author.name}
							</a>
						</span>
						<span>Requires {site.requirement}. Some features depend on your Mac.</span>
					</div>

					<div className="flex gap-1.5">
						{socials.map((s) => (
							<a
								key={s.id}
								href={s.href}
								aria-label={s.label}
								title={s.label}
								target="_blank"
								rel="noreferrer"
								className="grid size-9 place-items-center rounded-[11px] text-muted inset-ring inset-ring-line transition-colors duration-200 ease-quart hover:bg-white/6 hover:text-fg"
							>
								<BrandGlyph id={s.id} />
							</a>
						))}
					</div>
				</div>
			</div>
		</footer>
	);
}
