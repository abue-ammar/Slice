import { site } from "@/lib/site";
import { step } from "@/lib/reveal";
import { BrandGlyph } from "./glyphs";
import HeroTitle from "./hero-title";
import MetalButton from "./metal-button";
import Video from "./video";

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

			<div className="blur-in mx-auto mt-[clamp(72px,10vw,112px)] max-w-site" style={step(3)}>
				<div className={`${frame} aspect-[2240/1476]`}>
					<Video
						className="block size-full object-cover"
						src="/media/slice-editor.mp4"
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
