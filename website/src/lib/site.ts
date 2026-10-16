export const site = {
	name: "Slice",
	url: (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000").replace(/\/$/, ""),
	tagline: "Screen recorder and editor for Mac",
	description:
		"Slice is a native Mac app that records your screen, camera and microphone, then turns the take into a polished video. Free, no account, and it stays on your Mac.",
	author: { name: "rit3zh", url: "https://x.com/rit3zh", handle: "@rit3zh" },
	version: "0.1.0",
	repo: "https://github.com/infinite-toby/screen-recorder",
	download: "https://github.com/infinite-toby/screen-recorder/releases/latest",
	requirement: "macOS 15 or later",
	donate: "https://buymeacoffee.com/rit3zh",
};

export type Social = { id: "github" | "x" | "discord" | "coffee"; label: string; href: string };

export const socials: Social[] = (
	[
		{ id: "github", label: "GitHub", href: site.repo },
		{ id: "x", label: "X", href: "https://x.com/rit3zh" },
		{ id: "discord", label: "Discord", href: "" },
		{ id: "coffee", label: "Buy Me a Coffee", href: site.donate },
	] satisfies Social[]
).filter((s) => s.href);
