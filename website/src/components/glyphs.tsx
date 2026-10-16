import { siApple, siBuymeacoffee, siDiscord, siGithub, siX } from "simple-icons";
import type { Social } from "@/lib/site";

const BRANDS = { github: siGithub, x: siX, discord: siDiscord, coffee: siBuymeacoffee, apple: siApple };

export function BrandGlyph({ id, size = 16 }: { id: Social["id"] | "apple"; size?: number }) {
	return (
		<svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
			<path d={BRANDS[id].path} />
		</svg>
	);
}
