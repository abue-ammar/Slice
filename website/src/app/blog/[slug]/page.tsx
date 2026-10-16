import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import CopyMenu from "@/components/blog/copy-menu";
import { mdxComponents } from "@/components/blog/mdx";
import JsonLd from "@/components/json-ld";
import Toc from "@/components/license/toc";
import { formatDate, neighbours, readingTime, source } from "@/lib/blog";
import { doc } from "@/lib/doc";
import { pageMetadata } from "@/lib/metadata";
import { step } from "@/lib/reveal";
import { site } from "@/lib/site";

export default async function BlogPost({ params }: PageProps<"/blog/[slug]">) {
	const { slug } = await params;
	const post = source.getPage([slug]);
	if (!post) notFound();

	const MDX = post.data.body;
	const { newer, older } = neighbours(post);
	const toc = post.data.toc.filter((item) => item.depth === 2);
	const markdown = `# ${post.data.title}\n\n${await post.data.getText("raw")}`;
	const pager = [
		{ post: older, label: "Previous" },
		{ post: newer, label: "Next" },
	];

	return (
		<main className={doc.twoColumn}>
			<JsonLd
				data={{
					"@context": "https://schema.org",
					"@type": "BlogPosting",
					headline: post.data.title,
					description: post.data.description,
					datePublished: post.data.date.toISOString(),
					image: post.data.cover ? `${site.url}${post.data.cover}` : undefined,
					url: `${site.url}${post.url}`,
					author: { "@type": "Person", name: site.author.name, url: site.author.url },
					publisher: { "@type": "Organization", name: site.name, logo: `${site.url}/icon-512.png` },
				}}
			/>

			<article className={doc.article}>
				<header className={doc.header}>
					<Link href="/blog" className={`blur-in ${doc.eyebrow} transition-colors duration-200 ease-out hover:text-fg`} style={step(0)}>
						Blog
					</Link>
					<h1 className={`blur-in ${doc.title}`} style={step(1)}>
						{post.data.title}
					</h1>
					{post.data.description && (
						<p className={`blur-in ${doc.lede}`} style={step(2)}>
							{post.data.description}
						</p>
					)}
					<div className="blur-in relative z-20 mt-6 flex flex-wrap items-center justify-between gap-4" style={step(3)}>
						<p className="flex flex-wrap items-center gap-2 text-[13px] text-faint">
							<a
								href={site.author.url}
								target="_blank"
								rel="noreferrer"
								className="inline-flex items-center gap-2 font-medium text-muted transition-colors duration-200 ease-out hover:text-fg"
							>
								<Image src="/media/rit3zh.jpg" alt="" width={20} height={20} className="size-5 rounded-full ring-1 ring-line-strong" />
								{site.author.name}
							</a>
							<span aria-hidden>·</span>
							<time dateTime={post.data.date.toISOString()}>{formatDate(post.data.date)}</time>
							<span aria-hidden>·</span>
							<span>{await readingTime(post)}</span>
						</p>
						<CopyMenu markdown={markdown} />
					</div>
				</header>

				<div
					className="blur-in mt-8 border-t border-line pt-8 text-[16px] leading-[1.75] text-body [&_:not(pre)>code]:rounded-md [&_:not(pre)>code]:bg-raised [&_:not(pre)>code]:px-[0.35em] [&_:not(pre)>code]:py-[0.1em] [&_:not(pre)>code]:font-mono [&_:not(pre)>code]:text-[0.82em] [&_:not(pre)>code]:text-fg [&>:first-child]:mt-0"
					style={step(4)}
				>
					<MDX components={mdxComponents} />
				</div>

				{(newer || older) && (
					<nav className="mt-14 grid grid-cols-2 gap-4 border-t border-line pt-6 max-[640px]:grid-cols-1" aria-label="More posts">
						{pager.map(({ post, label }) =>
							post ? (
								<Link
									key={label}
									href={post.url}
									data-side={label}
									className="group/pager flex flex-col gap-1 data-[side=Next]:col-start-2 data-[side=Next]:text-right max-[640px]:data-[side=Next]:col-start-1 max-[640px]:data-[side=Next]:text-left"
								>
									<span className="text-[13px] text-faint">{label}</span>
									<span className="text-[15px] leading-[1.3] font-medium text-balance text-muted transition-colors duration-200 ease-out group-hover/pager:text-fg">
										{post.data.title}
									</span>
								</Link>
							) : (
								<span key={label} />
							),
						)}
					</nav>
				)}
			</article>

			{toc.length > 0 && (
				<aside className={`blur-in ${doc.aside}`} style={step(3)}>
					<Toc items={toc} />
				</aside>
			)}
		</main>
	);
}

export function generateStaticParams() {
	return source.getPages().map((post) => ({ slug: post.slugs[0] }));
}

export async function generateMetadata({ params }: PageProps<"/blog/[slug]">): Promise<Metadata> {
	const { slug } = await params;
	const post = source.getPage([slug]);
	if (!post) notFound();
	return pageMetadata({
		title: post.data.title,
		description: post.data.description ?? "",
		path: post.url,
		image: post.data.cover,
		type: "article",
		publishedTime: post.data.date.toISOString(),
	});
}
