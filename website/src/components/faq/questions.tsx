import { site } from "@/lib/site";

export const QUESTIONS: { q: string; a: React.ReactNode }[] = [
	{
		q: "Is Slice really free?",
		a: "Yes. It’s free to use for anything, including paid client work, and the source is on GitHub. There’s no account and no watermark. Selling or redistributing Slice itself needs permission (see the license).",
	},
	{
		q: "Which Macs does it run on?",
		a: "Any Mac running macOS 15 or later. Transcription and subtitles need macOS 26. Recording goes up to 120 fps on ProMotion displays.",
	},
	{
		q: "macOS says it can’t verify Slice. Is it safe?",
		a: (
			<>
				Slice isn’t notarized by Apple yet, so macOS warns you the first time. Open it once and click Done, then go to
				System Settings › Privacy &amp; Security and click <b>Open Anyway</b> next to Slice. You only do this once.
				The full source is on <a href={site.repo}>GitHub</a> if you’d like to check it or build it yourself.
			</>
		),
	},
	{
		q: "Does anything get uploaded?",
		a: "No. Recordings, transcripts and exports stay on your Mac. Voice enhancement needs a one-time 35.9 MB download, and Slice asks before it fetches anything.",
	},
	{
		q: "Can I record my iPhone?",
		a: "Yes. Plug it in with a USB cable and trust the Mac. It shows up as a source with its own window, in the matching device frame, and its sound can be recorded too.",
	},
	{
		q: "Can I build it from source?",
		a: (
			<>
				Yes. You need Xcode 26 and XcodeGen. Run <code>xcodegen generate</code>, then open the project. The{" "}
				<a href={site.repo}>README</a> has the full steps, including signing and building the DMG.
			</>
		),
	},
];
