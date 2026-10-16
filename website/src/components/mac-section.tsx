import { BorderBeam } from "./beam";
import { reveal } from "@/lib/reveal";
import Dock, { type DockApp } from "./dock";

const APPS: DockApp[] = [
	{ label: "Finder", icon: "/dock/finder.png" },
	{ label: "Safari", icon: "/dock/safari.png" },
	{ label: "Slice", icon: "/dock/slice.png" },
	{ label: "Messages", icon: "/dock/messages.png" },
	{ label: "Mail", icon: "/dock/mail.png" },
];

const POINTS = [
	{
		lead: "Native, all the way down.",
		body: "SwiftUI for the interface, Metal for the preview and ScreenCaptureKit for capture, the same frameworks the apps around it use.",
	},
	{
		lead: "Smooth on big displays.",
		body: "The preview renders on its own thread at your display’s refresh rate, up to 120 Hz, at full Retina resolution.",
	},
	{
		lead: "Exports through AVFoundation.",
		body: "HEVC or H.264 from 1080p to 4K, at 30, 60 or 120 fps, using the Mac’s own video encoder.",
	},
];

export default function MacSection() {
	return (
		<section className="mx-auto max-w-site px-(--gutter) pt-[clamp(112px,14vw,176px)] text-center">
			<h2 {...reveal(0)} className="font-rounded text-[clamp(30px,4.4vw,50px)] leading-[1.08] font-bold tracking-[-0.022em] text-balance text-fg">
				At home on your Mac.
			</h2>
			<p {...reveal(1)} className="mx-auto mt-[18px] max-w-[38rem] text-[clamp(17px,1.6vw,19px)] leading-normal text-balance text-muted [&_b]:font-medium [&_b]:text-fg">
				Slice is made for macOS and nothing else. <b>It looks and behaves like the apps you already use,</b> and leans
				on the best of what your Mac can do.
			</p>

			<div {...reveal(2)} className="mt-[clamp(72px,9vw,112px)] flex justify-center">
				<BorderBeam colorVariant="ocean" strength={0.55} duration={5} borderRadius={24} style={{ overflow: "visible" }}>
					<Dock apps={APPS} home="Slice" defaultRunning={["Finder", "Slice"]} />
				</BorderBeam>
			</div>

			<div className="mt-[clamp(56px,7vw,80px)] grid grid-cols-3 gap-[clamp(28px,4vw,56px)] pt-[clamp(36px,4vw,48px)] text-left shadow-[inset_0_1px_0_var(--color-line-strong)] max-[860px]:grid-cols-1">
				{POINTS.map((p, i) => (
					<p key={p.lead} {...reveal(i)} className="text-[16px] leading-[1.55] text-muted">
						<b className="font-medium text-fg">{p.lead}</b> {p.body}
					</p>
				))}
			</div>
		</section>
	);
}
