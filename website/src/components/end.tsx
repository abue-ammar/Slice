import Image from "next/image";
import Link from "next/link";
import { site, socials } from "@/lib/site";
import { BrandGlyph } from "./glyphs";
import { license } from "./license/content";

const LINKS = [
	{ label: "Features", href: "/#features" },
	{ label: "FAQ", href: "/#faq" },
	{ label: "Blog", href: "/blog" },
	{ label: "Roadmap", href: "/roadmap" },
	{ label: "License", href: "/license" },
	{ label: "Credits", href: "/credits" },
];

export default function End({ compact = false }: { compact?: boolean }) {
	return (
		<section className={`mx-auto w-full max-w-site px-(--gutter) ${compact ? "pt-16" : "pt-[clamp(96px,12vw,144px)]"}`}>
			<footer
				className={`grid grid-cols-[1fr_auto_1fr] items-center gap-6 px-1 pt-10 pb-12 text-[13.5px] text-muted max-[720px]:grid-cols-1 max-[720px]:justify-items-center max-[720px]:gap-[22px] max-[720px]:text-center ${compact ? "border-t border-line" : ""}`}
			>
				<div className="flex flex-col gap-1 max-[720px]:items-center">
					<span className="flex items-center gap-2 font-rounded text-[15px] font-semibold text-fg">
						<Image src="/icon.png" alt="" width={22} height={22} className="-m-px" />
						Slice
					</span>
					<span className="text-[12.5px] text-faint">
						v{site.version} · {license.final ? license.type : "Public domain"} · Made on a Mac
					</span>
				</div>

				<nav className="flex flex-wrap justify-center gap-x-[26px] gap-y-2.5" aria-label="Footer">
					{LINKS.map((link) => (
						<Link key={link.href} href={link.href} className="transition-colors duration-200 ease-quart hover:text-fg">
							{link.label}
						</Link>
					))}
					<a href={site.download} className="transition-colors duration-200 ease-quart hover:text-fg">
						Releases
					</a>
				</nav>

				<div className="flex justify-end gap-1.5 max-[720px]:justify-center">
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
			</footer>
		</section>
	);
}
