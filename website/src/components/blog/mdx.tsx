import Image, { type ImageProps } from "next/image";
import type { MDXComponents } from "mdx/types";
import Video from "@/components/video";
import { doc } from "@/lib/doc";

function Figure({ src, poster, alt, caption }: { src: string; poster?: string; alt: string; caption?: string }) {
	const video = /\.(mp4|mov|webm)$/.test(src);
	return (
		<figure className="my-8">
			<div className="overflow-hidden rounded-xl bg-card ring-1 ring-line">
				{video ? (
					<Video className="block h-auto w-full" src={src} poster={poster ?? ""} label={alt} />
				) : (
					<img className="block h-auto w-full" src={src} alt={alt} loading="lazy" />
				)}
			</div>
			{caption && <figcaption className="mt-2.5 text-center text-[13px] leading-normal text-faint">{caption}</figcaption>}
		</figure>
	);
}

export const mdxComponents: MDXComponents = {
	h2: (props) => <h2 {...props} className={doc.h2} />,
	h3: (props) => <h3 {...props} className={doc.h3} />,
	p: (props) => <p {...props} className="mb-4 text-pretty" />,
	ul: (props) => <ul {...props} className={doc.ul} />,
	ol: (props) => <ol {...props} className={doc.ol} />,
	li: (props) => <li {...props} className={doc.li} />,
	a: (props) => <a {...props} className={doc.link} />,
	strong: (props) => <strong {...props} className="font-medium text-fg" />,
	blockquote: (props) => <blockquote {...props} className={`${doc.note} text-[15px] [&>p]:mb-0`} />,
	hr: () => <hr className="my-10 border-line" />,
	pre: ({ className, ...props }) => (
		<pre
			{...props}
			className={`${className ?? ""} my-6 overflow-x-auto rounded-xl bg-surface! py-4 font-mono text-[13px] leading-[1.7] [&_.line]:px-4`}
		/>
	),
	img: (props) => (
		<Image
			{...(props as ImageProps)}
			sizes="(max-width: 720px) 100vw, 720px"
			className="my-8 block h-auto w-full rounded-xl ring-1 ring-line"
		/>
	),
	Figure,
};
