import { blog } from "fumadocs-mdx:collections/server";
import { loader } from "fumadocs-core/source";

export const source = loader({
	baseUrl: "/blog",
	source: blog.toFumadocsSource(),
});

export type Post = NonNullable<ReturnType<typeof source.getPage>>;

export const posts = () => source.getPages().sort((a, b) => b.data.date.getTime() - a.data.date.getTime());

export const formatDate = (date: Date) =>
	date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });

const WORDS_PER_MINUTE = 230;

export async function readingTime(post: Post) {
	const words = (await post.data.getText("processed")).split(/\s+/).filter(Boolean).length;
	return `${Math.max(1, Math.round(words / WORDS_PER_MINUTE))} min read`;
}

export function neighbours(post: Post) {
	const list = posts();
	const index = list.findIndex((p) => p.url === post.url);
	return { newer: list[index - 1], older: list[index + 1] };
}
