import type { Metadata, Viewport } from "next";
import RevealOnScroll from "@/components/reveal-on-scroll";
import { OG_IMAGE, OG_VIDEO } from "@/lib/metadata";
import { site } from "@/lib/site";
import { geistMono, geistSans, rounded } from "./fonts";
import "./globals.css";

const title = `${site.name} · ${site.tagline}`;

export const metadata: Metadata = {
	metadataBase: new URL(site.url),
	title: { default: title, template: `%s · ${site.name}` },
	description: site.description,
	applicationName: site.name,
	authors: [{ name: site.author.name, url: site.author.url }],
	creator: site.author.name,
	publisher: site.author.name,
	category: "technology",
	keywords: [
		"screen recorder",
		"Mac screen recorder",
		"free screen recorder for mac",
		"screen recording editor",
		"macOS",
		"product demo",
		"tutorial video",
		"auto zoom",
		"screen recorder with automatic zoom",
		"smooth cursor",
		"webcam recording",
		"system audio recording",
		"record iPhone on Mac",
		"wallpaper background",
		"captions",
		"transcript editing",
		"voice enhancement",
		"export to gif",
		"screen studio alternative",
		"loom alternative",
		"open source",
		"Slice",
	],
	alternates: { canonical: "/" },
	openGraph: {
		type: "website",
		url: "/",
		siteName: site.name,
		locale: "en_US",
		title,
		description: site.description,
		images: [OG_IMAGE],
		videos: [OG_VIDEO],
	},
	twitter: {
		card: "summary_large_image",
		creator: site.author.handle,
		title,
		description: site.description,
		images: [{ url: OG_IMAGE.url, alt: OG_IMAGE.alt }],
	},
	robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large" } },
	appleWebApp: { title: site.name, statusBarStyle: "black-translucent" },
	formatDetection: { telephone: false, email: false, address: false },
	referrer: "strict-origin-when-cross-origin",
	other: { "apple-mobile-web-app-capable": "yes" },
};

export const viewport: Viewport = {
	themeColor: "#000000",
	colorScheme: "dark",
};

export default function RootLayout({
	children,
}: Readonly<{
	children: React.ReactNode;
}>) {
	return (
		<html lang="en" data-scroll-behavior="smooth" className={`${rounded.variable} ${geistSans.variable} ${geistMono.variable}`}>
			<head>
				<noscript>
					<style>{"[data-reveal]{opacity:1!important}"}</style>
				</noscript>
			</head>
			<body>
				{children}
				<RevealOnScroll />
			</body>
		</html>
	);
}
