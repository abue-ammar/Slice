import { defineConfig, defineDocs, frontmatterSchema } from "fumadocs-mdx/config";
import { z } from "zod";

export const blog = defineDocs({
	dir: "content/blog",
	docs: {
		schema: frontmatterSchema.extend({
			date: z.coerce.date(),
			cover: z.string().optional(),
		}),
	},
});

export default defineConfig({
	mdxOptions: {
		rehypeCodeOptions: {
			themes: { light: "github-dark-default", dark: "github-dark-default" },
		},
	},
});
