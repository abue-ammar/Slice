import type { MetadataRoute } from "next";
import { license } from "@/components/license/content";
import { posts } from "@/lib/blog";
import { site } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
	const pages = ["/", "/roadmap", "/blog", "/credits", ...(license.final ? ["/license"] : [])];
	return [
		...pages.map((path) => ({ url: `${site.url}${path === "/" ? "" : path}`, changeFrequency: "weekly" as const, priority: path === "/" ? 1 : 0.7 })),
		...posts().map((post) => ({ url: `${site.url}${post.url}`, lastModified: post.data.date, priority: 0.6 })),
	];
}
