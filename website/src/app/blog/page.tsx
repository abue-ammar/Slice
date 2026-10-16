import type { Metadata } from "next";
import PostCard from "@/components/blog/post-card";
import { doc } from "@/lib/doc";
import { posts } from "@/lib/blog";
import { pageMetadata } from "@/lib/metadata";
import { step } from "@/lib/reveal";

export const metadata: Metadata = pageMetadata({
	title: "Blog",
	description: "News, updates and the thinking behind Slice, the screen recorder and editor for Mac.",
	path: "/blog",
});

export default function BlogIndex() {
	return (
		<main className="mx-auto max-w-[720px] px-(--gutter) pt-14 font-blog">
			<header>
				<p className={`blur-in ${doc.eyebrow}`} style={step(0)}>
					Blog
				</p>
				<h1 className={`blur-in ${doc.title}`} style={step(1)}>
					From the making of Slice
				</h1>
				<p className={`blur-in ${doc.lede}`} style={step(2)}>
					News, updates and the thinking behind Slice.
				</p>
			</header>

			<section className="blur-in mt-10 border-t border-line" style={step(3)} aria-label="Posts">
				{posts().map((post, i) => (
					<PostCard key={post.url} post={post} priority={i === 0} />
				))}
			</section>
		</main>
	);
}
