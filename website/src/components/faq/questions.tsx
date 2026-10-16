import { site } from "@/lib/site";

export const QUESTIONS: { q: string; a: React.ReactNode }[] = [
	{
		q: "Is Slice really free?",
		a: "Yes. It’s released into the public domain, so you can use it for anything, including paid client work. There’s no account and no watermark.",
	},
	{
		q: "Which Macs does it run on?",
		a: "Any Mac running macOS 15 or later. Transcription and subtitles need macOS 26. Recording goes up to 120 fps on ProMotion displays.",
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
				<a href={site.repo}>README</a> has the full steps, including signing with your own Developer ID.
			</>
		),
	},
];
