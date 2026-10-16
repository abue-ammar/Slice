export type ChapterId = "record" | "zoom" | "cursor" | "transitions" | "transcript" | "voice" | "iphone";

export type Chapter = {
	id: ChapterId;
	label: string;
	title: string;
	body: string;
	stage: string;
};

export const CHAPTERS: Chapter[] = [
	{
		id: "record",
		label: "Record",
		title: "Pick a display, a window, or drag out an area.",
		body: "Slice records at native Retina resolution, up to 120 fps on ProMotion displays. Camera, microphone and system audio each land on their own track, so you can fix one without touching the others. Pause, resume, and stack several takes into one project.",
		stage: "The capture bar switching between Display, Window, Area and iPhone, with a live microphone meter.",
	},
	{
		id: "zoom",
		label: "Zoom",
		title: "Zoom in where it matters.",
		body: "Set a focal point and Slice glides in, holds, and eases back out. Pan to a second spot or follow the cursor. Auto-zoom suggests zooms from your clicks. Or reach for the Liquid Glass lens: a refracting circle, squircle or pill that magnifies what’s under it and flows into the next one.",
		stage: "A glass lens gliding over a settings list, magnifying the rows beneath it.",
	},
	{
		id: "cursor",
		label: "Cursor",
		title: "Your cursor is saved as a path, not pixels.",
		body: "So you can change it after recording. Smooth out a shaky hand without adding lag, make the pointer bigger, switch between Big Sur and Tahoe artwork, add motion blur, or hide it. Every click can leave a soft ripple or a liquid wave.",
		stage: "A jittery recorded pointer path next to the smoothed path the cursor actually follows.",
	},
	{
		id: "transitions",
		label: "Transitions",
		title: "Cut between clips with a transition.",
		body: "Split a take and drop a transition on the seam: Zoom Blur, Page Curl, Revolve, Burn, Wave Scramble or Thanos Snap. Each one is a Metal shader, so it plays live in the preview. Drag its edges on the timeline to change the length, or delete it to go back to a hard cut.",
		stage: "A transition between two clips on the timeline, switched between Zoom Blur, Page Curl and Burn as the preview plays it.",
	},
	{
		id: "transcript",
		label: "Transcript",
		title: "Edit the video by editing the text.",
		body: "Slice transcribes what you say on your Mac, with the timing of every word. Select a word, a sentence or a false start and delete it, and that part of the video goes with it. Each cut starts and ends in the gap between words, so nothing is clipped mid-word, and anything you cut can be put back. Transcripts come from Apple’s on-device speech model, so this needs macOS 26.",
		stage: "The transcript highlighting each word as it's spoken, with the lines around it blurred like lyrics.",
	},
	{
		id: "voice",
		label: "Voice",
		title: "Your voice, minus the room.",
		body: "DeepFilterNet3 lifts fan hum, keyboard clatter and room noise off your microphone and leaves the voice itself natural. Podcast polish adds a gentle EQ, light compression and even loudness. Switch between Original and Enhanced any time; the recording is never overwritten, and it all runs offline.",
		stage: "A microphone waveform switching between a noisy original and a clean enhanced version.",
	},
	{
		id: "iphone",
		label: "iPhone",
		title: "Plug in your iPhone.",
		body: "It opens in its own window, inside the matching device frame, at the screen’s full refresh rate. Record it like any other source. In the editor, drop the take onto a 3D iPhone, pose it, keyframe it, or let it float.",
		stage: "A recording of an iPhone app placed on a 3D iPhone in Slice, turning as the take plays.",
	},
];
