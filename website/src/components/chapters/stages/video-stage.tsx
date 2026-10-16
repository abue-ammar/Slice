import Video from "../../video";

type Fit = "cover" | "contain" | "window" | "lyrics";

type Props = { src: string; poster: string; label: string; fit?: Fit };

const ROOT: Record<Fit, string> = {
	cover: "",
	contain: "px-[4%]",
	window: "",
	lyrics: "bg-[#18191c]",
};

const VIDEO: Record<Fit, string> = {
	cover: "absolute inset-0 h-full object-cover",
	contain: "h-auto object-contain",
	window: "h-auto object-contain",
	lyrics: "absolute inset-0 h-full scale-106 object-cover object-[50%_14%]",
};

export default function VideoStage({ src, poster, label, fit = "cover" }: Props) {
	return (
		<div className={`absolute inset-0 grid place-items-center ${ROOT[fit]}`}>
			<Video className={`block w-full ${VIDEO[fit]}`} src={src} poster={poster} label={label} />
		</div>
	);
}
