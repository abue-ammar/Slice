import type { Metadata } from "next";
import PageShell from "@/components/page-shell";
import { MODEL_LICENSE, MODELS } from "@/components/credits/content";
import { doc } from "@/lib/doc";
import { pageMetadata } from "@/lib/metadata";
import { reveal, step } from "@/lib/reveal";

export const metadata: Metadata = pageMetadata({
	title: "Credits",
	description: "The artists behind the 3D iPhone models in Slice's editor, shared under CC BY 4.0.",
	path: "/credits",
	image: "/media/iphone-3d.jpg",
});

function Arrow() {
	return (
		<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden>
			<path d="M3 2h5v5M8 2 2 8" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
		</svg>
	);
}

export default function CreditsPage() {
	return (
		<PageShell>
			<main className="mx-auto max-w-[640px] px-(--gutter) pt-14 font-blog">
				<header>
					<p className={`blur-in ${doc.eyebrow}`} style={step(0)}>
						Credits
					</p>
					<h1 className={`blur-in ${doc.title}`} style={step(1)}>
						3D iPhone models
					</h1>
					<p className={`blur-in ${doc.lede}`} style={step(2)}>
						The iPhones you can drop a recording onto in Slice were made by these artists and shared on Sketchfab
						under{" "}
						<a href={MODEL_LICENSE.url} target="_blank" rel="noreferrer" className={doc.link}>
							{MODEL_LICENSE.name}
						</a>
						. Thank you.
					</p>
				</header>

				<ul className="blur-in mt-10 border-t border-line" style={step(3)}>
					{MODELS.map((m) => (
						<li key={m.model} className="flex items-center justify-between gap-4 border-b border-line py-4">
							<div className="flex min-w-0 flex-col gap-[3px]">
								<span className="text-[15px] font-medium text-fg">{m.model}</span>
								<span className="text-[13.5px] text-muted">
									“{m.title}” by{" "}
									<a
										href={m.authorURL}
										target="_blank"
										rel="noreferrer"
										className="underline decoration-white/18 underline-offset-3 transition-colors duration-150 ease-out hover:text-fg hover:decoration-fg"
									>
										{m.author}
									</a>
								</span>
							</div>
							<a href={m.url} target="_blank" rel="noreferrer" className={`${doc.pill} flex-none`}>
								Sketchfab
								<Arrow />
							</a>
						</li>
					))}
				</ul>

				<section {...reveal(0)} className="mt-10">
					<h2 className="mb-2 text-[15px] font-medium text-fg">Changes</h2>
					<p className="text-[14px] leading-[1.7] text-pretty text-muted">
						Slice turns each model to face the camera, re-maps its display’s texture coordinates, hides any stage
						modelled around the phone, recolours the body for other finishes and draws your recording on the display as
						it plays. The model files themselves ship unmodified.
					</p>
				</section>
			</main>
		</PageShell>
	);
}
