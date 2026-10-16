"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

export default function RevealOnScroll() {
	const pathname = usePathname();

	useEffect(() => {
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (!entry.isIntersecting) continue;
					entry.target.setAttribute("data-revealed", "");
					observer.unobserve(entry.target);
				}
			},
			{ rootMargin: "0px 0px -8% 0px" },
		);
		document.querySelectorAll("[data-reveal]:not([data-revealed])").forEach((el) => observer.observe(el));
		return () => observer.disconnect();
	}, [pathname]);

	return null;
}
