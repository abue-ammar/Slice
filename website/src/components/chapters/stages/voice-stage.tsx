
const BARS = Array.from({ length: 44 }, (_, i) => {
	const speaking = (i > 3 && i < 18) || (i > 23 && i < 40);
	const voice = speaking ? 0.35 + 0.6 * Math.abs(Math.sin(i * 0.8) * Math.cos(i * 0.31)) : 0.04;
	const noise = 0.22 + 0.16 * Math.abs(Math.sin(i * 3.1));
	return { clean: Math.round(voice * 100), noisy: Math.round(Math.min(1, voice + noise) * 100) };
});

export default function VoiceStage() {
	return (
		<div className="absolute inset-0 flex animate-enhance flex-col items-center justify-center gap-[3.4em]" aria-hidden>
			<span className="relative grid w-[22em] grid-cols-2 rounded-[1.2em] bg-white/6 p-[0.35em]">
				<span className="absolute inset-y-[0.35em] left-[0.35em] w-[calc(50%-0.35em)] translate-x-[calc(var(--m)*100%)] rounded-[0.9em] bg-white/13" />
				<span className="relative py-[0.5em] text-center text-[1.25em] font-medium text-[#ededf0]">Original</span>
				<span className="relative py-[0.5em] text-center text-[1.25em] font-medium text-[#ededf0]">Enhanced</span>
			</span>
			<div className="flex h-[14em] items-center gap-[0.34em]">
				{BARS.map((b, i) => (
					<i
						key={i}
						className="h-[calc((var(--a)*(1-var(--m))+var(--b)*var(--m))*1%)] min-h-[0.4em] w-[0.5em] rounded-[1em] bg-[color-mix(in_srgb,#33a39e_calc(var(--m)*100%),#6a6c73)]"
						style={{ "--a": b.noisy, "--b": b.clean } as React.CSSProperties}
					/>
				))}
			</div>
			<span className="text-[1.2em] text-faint">DeepFilterNet3 · Podcast polish · −16 LUFS</span>
		</div>
	);
}
