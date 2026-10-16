import type { Metadata } from "next";
import PageShell from "@/components/page-shell";
import Checklist from "@/components/roadmap/checklist";
import { NOTARIZED, PLANNED, SHIPPED } from "@/components/roadmap/content";
import { pageMetadata } from "@/lib/metadata";
import { site } from "@/lib/site";
import { reveal, step } from "@/lib/reveal";

export const metadata: Metadata = pageMetadata({
	title: "Roadmap",
	description: "What's coming next to Slice, and everything that's already in.",
	path: "/roadmap",
});

const heading = "flex items-baseline justify-between border-b border-line pb-1.5 text-[14px] font-medium text-muted";

export default function RoadmapPage() {
	return (
		<PageShell>
			<main className="mx-auto max-w-[640px] px-(--gutter) pt-[clamp(56px,9vw,96px)] font-blog">
				<header>
					<h1 className="blur-in text-[clamp(36px,5vw,44px)] leading-[1.05] font-semibold tracking-[-0.045em]" style={step(0)}>
						Roadmap
					</h1>
					<p className="blur-in mt-3.5 text-[16.5px] leading-[1.6] text-pretty text-muted" style={step(1)}>
						What’s coming to Slice, and what’s already in. Plans can move while it’s early.
					</p>
				</header>

				<section className="blur-in mt-14" style={step(2)} aria-labelledby="next">
					<h2 id="next" className={heading}>
						Up next
					</h2>
					<Checklist items={PLANNED} />
				</section>

				<section {...reveal(0)} className="mt-14" aria-labelledby="notarized">
					<h2 id="notarized" className={`${heading} scroll-mt-28`}>
						Approved by Apple <span className="font-mono text-[12.5px] font-normal text-faint">$99 / year</span>
					</h2>
					<Checklist items={NOTARIZED.items} done={NOTARIZED.done} />
					<p className="mt-4 text-[15px] leading-[1.6] text-pretty text-muted">
						Slice isn’t notarized yet, so macOS asks you to click Open Anyway the first time. A paid Apple developer
						account fixes that for everyone.{" "}
						<a
							href={site.donate}
							target="_blank"
							rel="noreferrer"
							className="text-fg underline decoration-white/25 underline-offset-3 transition-[text-decoration-color] duration-200 ease-quart hover:decoration-fg"
						>
							Chip in
						</a>
					</p>
				</section>

				<section {...reveal(0)} className="mt-14" aria-labelledby="shipped">
					<h2 id="shipped" className={heading}>
						Already in Slice <span className="font-mono text-[12.5px] font-normal text-faint">{site.version}</span>
					</h2>
					<Checklist items={SHIPPED} done />
				</section>

				<p {...reveal(0)} className="mt-12 text-[15px] text-muted">
					Something missing?{" "}
					<a
						href={`${site.repo}/issues/new`}
						target="_blank"
						rel="noreferrer"
						className="text-fg underline decoration-white/25 underline-offset-3 transition-[text-decoration-color] duration-200 ease-quart hover:decoration-fg"
					>
						Suggest a feature
					</a>
				</p>
			</main>
		</PageShell>
	);
}
