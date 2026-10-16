import Link from "next/link";
import { OG_VIDEO } from "@/lib/metadata";
import { site } from "@/lib/site";
import { step } from "@/lib/reveal";
import { BrandGlyph } from "./glyphs";
import CopyButton from "./license/copy-button";
import HeroTitle from "./hero-title";
import MetalButton from "./metal-button";
import Video from "./video";

const INSTALL = `curl -fsSL ${site.url}/install.sh | bash`;

const frame = "scroll-settle origin-top overflow-hidden rounded-[20px] bg-black ring-1 ring-line will-change-transform max-[520px]:rounded-xl";

export default function Hero() {
	return (
		<header className="overflow-x-clip px-(--gutter) pt-[clamp(80px,14vh,144px)] text-center" id="top">
			<div className="blur-in" style={step(0)}>
				<HeroTitle />
			</div>
			<p className="blur-in mx-auto mt-[22px] max-w-[30rem] text-[17px] leading-[1.55] text-balance text-muted" style={step(1)}>
				Record your screen, then turn the take into a finished video. Free, and it never leaves your Mac.
			</p>
			<div className="blur-in mt-9 flex flex-wrap justify-center gap-3" style={step(2)}>
				<MetalButton href={site.download}>Download for Mac</MetalButton>
				<a
					href={site.repo}
					className="inline-flex h-12 items-center gap-2 rounded-full bg-raised px-[22px] text-[15px] font-medium whitespace-nowrap text-fg inset-ring inset-ring-line-strong transition-[color,background-color,box-shadow,scale] duration-200 ease-quart hover:bg-white hover:text-black hover:inset-ring-white active:scale-97"
					target="_blank"
					rel="noreferrer"
				>
					<BrandGlyph id="github" size={16} />
					Star on GitHub
				</a>
			</div>
			<div className="blur-in mx-auto mt-6 flex max-w-[34rem] flex-col items-center gap-3" style={step(2.5)}>
				<p className="text-[13.5px] text-pretty text-faint">
					Or install from Terminal and skip the “can’t verify” warning.{" "}
					<Link
						href="/roadmap#notarized"
						className="group/learn inline-flex items-center gap-1 font-medium text-muted transition-colors duration-200 ease-quart hover:text-fg"
					>
						Learn more
						<svg
							width="10"
							height="10"
							viewBox="0 0 10 10"
							aria-hidden
							className="transition-transform duration-300 ease-settle group-hover/learn:translate-x-0.5 motion-reduce:transition-none"
						>
							<path d="M2 5h6M5.5 2.5 8 5 5.5 7.5" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
						</svg>
					</Link>
				</p>
				<div className="flex max-w-full items-center gap-1.5 rounded-full bg-raised p-1 pl-4 inset-ring inset-ring-line max-[520px]:flex-col max-[520px]:rounded-3xl max-[520px]:p-2">
					<code className="min-w-0 font-mono text-[12.5px] break-all text-muted">{INSTALL}</code>
					<CopyButton text={INSTALL} label="Copy" />
				</div>
			</div>

			<div className="blur-in mx-auto mt-[clamp(72px,10vw,112px)] max-w-site" style={step(3)}>
				<div className={`${frame} aspect-[2240/1476]`}>
					<Video
						className="block size-full object-cover"
						src={OG_VIDEO.url}
						poster="/media/slice-editor.jpg"
						label="The Slice editor: a recording on a wallpaper background in the preview, the inspector switching between background, cursor and click settings, and a timeline of zooms under the take."
						eager
					/>
				</div>
				<div className="mt-4 max-[520px]:mt-3">
					<div className={`${frame} aspect-[2526/1134]`}>
						<Video
							className="block size-full object-cover"
							src="/media/delete-project.mp4"
							poster="/media/delete-project.jpg"
							label="Slice's projects page: a recording card slides aside to reveal a red delete button and eases out of the grid."
						/>
					</div>
				</div>
			</div>
		</header>
	);
}
