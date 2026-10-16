# Slice website

The site for [Slice](https://slice.rit3zh.dev), built with Next.js and deployed to Cloudflare Workers via OpenNext.

```sh
npm install
npm run dev       # http://localhost:3000
npm run preview   # run the Cloudflare build locally
npm run deploy    # deploy to Cloudflare
```

- Links and version: `src/lib/site.ts`
- Page metadata: `src/lib/metadata.ts`
- Blog posts: `content/blog/*.mdx`
- Social preview: `public/media/og.jpg`

`NEXT_PUBLIC_SITE_URL` sets the origin for canonical links and previews (defaults to `https://slice.rit3zh.dev`).
