"use client";

import { useEffect, useRef, useState } from "react";

type Props = {
	src: string;
	poster: string;
	label: string;
	eager?: boolean;
	className?: string;
};

export default function Video({ src, poster, label, eager = false, className }: Props) {
	const ref = useRef<HTMLVideoElement>(null);
	const visible = useRef(false);
	const [near, setNear] = useState(eager);

	const sync = () => {
		const video = ref.current;
		if (!video?.getAttribute("src") || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
		if (visible.current) video.play().catch(() => {});
		else video.pause();
	};

	useEffect(() => {
		const video = ref.current;
		if (!video) return;
		const loader = new IntersectionObserver(([e]) => e.isIntersecting && setNear(true), { rootMargin: "600px 0px" });
		const player = new IntersectionObserver(
			([e]) => {
				visible.current = e.isIntersecting;
				sync();
			},
			{ threshold: 0.15 },
		);
		loader.observe(video);
		player.observe(video);
		return () => {
			loader.disconnect();
			player.disconnect();
		};
	}, []);

	useEffect(sync, [near]);

	return (
		<video
			ref={ref}
			className={className}
			src={near ? src : undefined}
			poster={poster}
			aria-label={label}
			muted
			loop
			playsInline
			preload={eager ? "auto" : "none"}
		/>
	);
}
