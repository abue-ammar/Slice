import { Geist, Geist_Mono } from "next/font/google";
import localFont from "next/font/local";

export const rounded = localFont({
	src: [
		{ path: "../fonts/sf-pro-rounded-regular.woff2", weight: "400" },
		{ path: "../fonts/sf-pro-rounded-medium.woff2", weight: "500" },
		{ path: "../fonts/sf-pro-rounded-bold.woff2", weight: "700" },
	],
	variable: "--font-sf-rounded",
	display: "swap",
});

export const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
export const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

