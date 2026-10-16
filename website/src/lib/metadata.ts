import type { Metadata } from "next";
import { site } from "./site";

export const OG_IMAGE = { url: "/media/og.jpg", width: 1200, height: 630, alt: "The Slice editor with a recording on a wallpaper, zooms on the timeline." };

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
