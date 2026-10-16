import { reveal } from "@/lib/reveal";
import SectionHeading from "../section-heading";
import { CHAPTERS, type ChapterId } from "./content";
import CursorStage from "./stages/cursor-stage";
import VideoStage from "./stages/video-stage";
import VoiceStage from "./stages/voice-stage";

const STAGES: Record<ChapterId, () => React.ReactElement> = {
	record: () => (
		<VideoStage
			src="/media/capture-bar.mp4"
			poster="/media/capture-bar.jpg"
			label="Slice's capture bar: Display, Window, Area and Device, microphone and camera, Options and Record."
			fit="contain"
		/>
	),
	zoom: () => (
		<VideoStage
			src="/media/liquid-lens.mp4"
			poster="/media/liquid-lens.jpg"
			label="A Liquid Glass lens following the cursor across a website, magnifying and bending what's beneath it."
		/>
	),
	cursor: CursorStage,
	transitions: () => (
		<VideoStage
			src="/media/transitions.mp4"
			poster="/media/transitions.jpg"
			label="The Slice editor: a transition between two clips on the timeline, switched between Zoom Blur, Page Curl and Burn in the inspector as the preview plays it."
			fit="window"
		/>
	),
	transcript: () => (
		<VideoStage
			src="/media/transcript.mp4"
			poster="/media/transcript.jpg"
			label="Slice's transcript highlighting each word as it's spoken, with the lines around it blurred like lyrics."
			fit="lyrics"
		/>
	),
	voice: VoiceStage,
	iphone: () => (
		<VideoStage
			src="/media/iphone-3d.mp4"
			poster="/media/iphone-3d.jpg"
			label="An iPhone recording on a 3D iPhone, edited in Slice."
		/>
	),
};

export default function Chapters() {
	return (
		<section id="features" className="mx-auto max-w-site px-(--gutter) pt-[clamp(120px,15vw,192px)]">
			<SectionHeading title="Everything between record and export." center>
				Every setting can be changed after you stop recording.
			</SectionHeading>

			<div className="mt-[clamp(40px,6vw,72px)]">
				{CHAPTERS.map((c) => {
					const Stage = STAGES[c.id];
					return (
						<article key={c.id} id={c.id} className="grid grid-cols-[minmax(0,5fr)_minmax(0,6fr)] items-center gap-[clamp(32px,6vw,88px)] py-[clamp(48px,7vw,88px)] max-[860px]:grid-cols-1">
							<div>
								<p {...reveal(0)} className="text-[13px] font-medium text-faint">
									{c.label}
								</p>
								<h3 {...reveal(1)} className="mt-3 font-rounded text-[clamp(23px,2.5vw,28px)] leading-[1.18] font-bold tracking-[-0.015em] text-balance text-fg">{c.title}</h3>
								<p {...reveal(2)} className="mt-3.5 max-w-[28rem] text-[15.5px] leading-[1.65] text-pretty text-muted">{c.body}</p>
							</div>
							<div {...reveal(1)} className="@container relative grid aspect-[5/4] place-items-center overflow-hidden rounded-[22px] bg-black text-fg inset-ring inset-ring-line *:text-[calc(100cqi/48)]" role="img" aria-label={c.stage}>
								<Stage />
							</div>
						</article>
					);
				})}
			</div>
		</section>
	);
}
