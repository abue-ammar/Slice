import Chapters from "@/components/chapters";
import End from "@/components/end";
import Faq from "@/components/faq";
import Hero from "@/components/hero";
import JsonLd from "@/components/json-ld";
import MacSection from "@/components/mac-section";
import Nav from "@/components/nav";
import OutputSection from "@/components/output-section";
import { OG_IMAGE } from "@/lib/metadata";
import { site } from "@/lib/site";

const app = {
	"@context": "https://schema.org",
	"@type": "SoftwareApplication",
	name: site.name,
	description: site.description,
	url: site.url,
	image: `${site.url}${OG_IMAGE.url}`,
	applicationCategory: "MultimediaApplication",
	operatingSystem: site.requirement,
	softwareVersion: site.version,
	downloadUrl: site.download,
	author: { "@type": "Person", name: site.author.name, url: site.author.url },
	offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export default function Home() {
	return (
		<>
			<JsonLd data={app} />
			<Nav />
			<main>
				<Hero />
				<OutputSection />
				<Chapters />
				<Faq />
				<MacSection />
				<End />
			</main>
		</>
	);
}
