import type { Metadata } from "next";
import PageShell from "@/components/page-shell";
import CopyButton from "@/components/license/copy-button";
import Faq from "@/components/license/faq";
import Toc from "@/components/license/toc";
import { CLAUSES, FAQ, license, licenseText, type Block } from "@/components/license/content";
import { doc } from "@/lib/doc";
import { pageMetadata } from "@/lib/metadata";
import { reveal, step } from "@/lib/reveal";

const title = "Slice License — Source-Available Software";
const description =
	"Slice is source-available: use it, study the code, change it for yourself and contribute back. Commercial redistribution and resale need permission.";

export const metadata: Metadata = pageMetadata({ title, description, path: "/license", image: "/media/slice-demo.jpg" });

const TOC = [
	...CLAUSES.map((clause, i) => ({ url: `#${clause.id}`, title: `${i + 1}. ${clause.title}`, depth: 2 })),
	{ url: "#contributing", title: "Contributing", depth: 2 },
	{ url: "#faq", title: "FAQ", depth: 2 },
];

function Body({ block }: { block: Block }) {
	if ("p" in block) return <p className={doc.p}>{block.p}</p>;
	if ("list" in block)
		return (
			<ul className={doc.ul}>
				{block.list.map((item) => (
					<li key={item} className={doc.li}>
						{item}
					</li>
				))}
			</ul>
		);
	return (
		<ul className="mt-2 mb-5 border-t border-line">
			{block.components.map((c) => (
				<li key={c.name} className="flex items-baseline justify-between gap-4 border-b border-line py-3">
					<span className="flex min-w-0 flex-col gap-[2px]">
						<a
							href={c.url}
							{...(c.url.startsWith("/") ? {} : { target: "_blank", rel: "noreferrer" })}
							className="text-[15px] font-medium text-fg underline decoration-white/18 underline-offset-3 transition-colors duration-150 ease-out hover:decoration-fg"
						>
							{c.name}
						</a>
						<span className="text-[13.5px] leading-[1.5] text-muted">{c.use}</span>
					</span>
					<span className="flex-none text-right text-[13px] text-faint">{c.license}</span>
				</li>
			))}
		</ul>
	);
}

export default function LicensePage() {
	const facts = [
		license.type,
		`Version ${license.version}`,
		`Updated ${license.updated}`,
		license.copyright,
	];

	return (
		<PageShell>
			<main className={doc.twoColumn}>
				<article className={doc.article}>
					<header className={doc.header}>
						<p className={`blur-in ${doc.eyebrow}`} style={step(0)}>
							Legal &amp; Licensing
						</p>
						<h1 className={`blur-in ${doc.title}`} style={step(1)}>
							{license.name}
						</h1>
						<p className={`blur-in ${doc.lede}`} style={step(2)}>
							Slice makes its source code available so you can use it, experiment with it, change it for yourself and
							contribute back. Selling it or redistributing it commercially needs permission. It’s source-available, not
							open source.
						</p>
						<div className="blur-in mt-6 flex flex-wrap items-center justify-between gap-4" style={step(3)}>
							<p className="text-[13px] text-faint">
								{facts.map((fact, i) => (
									<span key={fact}>
										{i > 0 && <span aria-hidden> · </span>}
										{fact}
									</span>
								))}
							</p>
							<CopyButton text={licenseText()} />
						</div>
					</header>


					<div className="mt-4 text-[15px] leading-[1.75] text-body">
						{CLAUSES.map((clause, i) => (
							<section key={clause.id} {...reveal(0)}>
								<h2 id={clause.id} className={doc.h2}>
									<span className="text-faint tabular-nums">{i + 1}.</span>
									{clause.title}
								</h2>
								{clause.body.map((block, j) => (
									<Body key={j} block={block} />
								))}
							</section>
						))}

						<section {...reveal(0)}>
							<h2 id="contributing" className={doc.h2}>
								Contributing
							</h2>
							<p className={doc.p}>
								Report bugs, suggest improvements and submit pull requests on{" "}
								<a href={license.repo} target="_blank" rel="noreferrer" className={doc.link}>
									GitHub
								</a>
								: open an{" "}
								<a href={`${license.repo}/issues`} target="_blank" rel="noreferrer" className={doc.link}>
									issue
								</a>{" "}
								for bugs and ideas, or a{" "}
								<a href={`${license.repo}/pulls`} target="_blank" rel="noreferrer" className={doc.link}>
									pull request
								</a>{" "}
								for changes. Contributions are covered by section 6, and{" "}
								<a href={`${license.repo}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noreferrer" className={doc.link}>
									CONTRIBUTING.md
								</a>{" "}
								explains how to build Slice and send a change.
							</p>
						</section>

						<section {...reveal(0)}>
							<h2 id="faq" className={doc.h2}>
								FAQ
							</h2>
							<Faq items={FAQ} />
						</section>
					</div>
				</article>

				<aside className={`blur-in ${doc.aside}`} style={step(3)}>
					<Toc items={TOC} />
				</aside>
			</main>
		</PageShell>
	);
}
