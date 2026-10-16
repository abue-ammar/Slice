import type { Metadata } from "next";
import { site } from "./site";

export const OG_IMAGE = {
	url: "/media/og.jpg",
	width: 2400,
	height: 1200,
	type: "image/jpeg",
	alt: "Slice: screen recordings, beautifully simple. The editor with a recording on a wallpaper and zooms on the timeline.",
};

export const OG_VIDEO = { url: `${site.url}/media/slice-editor.mp4`, secureUrl: `${site.url}/media/slice-editor.mp4`, width: 2240, height: 1476, type: "video/mp4" };

type Page = {
	title: string;
	description: string;
	path: string;
	image?: string;
	type?: "website" | "article";
	publishedTime?: string;
};

export function pageMetadata({ title, description, path, image, type = "website", publishedTime }: Page): Metadata {
	const images = image ? [{ url: image, alt: title }] : [OG_IMAGE];
	const full = title.includes(site.name) ? title : `${title} · ${site.name}`;
	return {
		title: { absolute: full },
		description,
		alternates: { canonical: path },
		openGraph: {
			type,
			url: path,
			siteName: site.name,
			locale: "en_US",
			title: full,
			description,
			images,
			...(publishedTime && { publishedTime, authors: [site.author.url] }),
		},
		twitter: {
			card: "summary_large_image",
			creator: site.author.handle,
			title: full,
			description,
			images: images.map((i) => i.url),
		},
	};
}
