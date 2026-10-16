import type { MetadataRoute } from "next";
import { site } from "@/lib/site";

export default function manifest(): MetadataRoute.Manifest {
	return {
		name: `${site.name} · ${site.tagline}`,
		short_name: site.name,
		description: site.description,
		start_url: "/",
		display: "standalone",
		background_color: "#000000",
		theme_color: "#000000",
		icons: [
			{ src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
			{ src: "/apple-icon.png", sizes: "256x256", type: "image/png" },
		],
	};
}
