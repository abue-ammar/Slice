# Slice website

The landing page for Slice, built with Next.js and deployed to Cloudflare Workers through OpenNext. Dark only.

```sh
npm install
npm run dev       # http://localhost:3000
npm run preview   # build and run on the Cloudflare runtime locally
npm run deploy    # build and deploy to Cloudflare
```

Links (download, source, socials) and the version live in `src/lib/site.ts`.

Set `NEXT_PUBLIC_SITE_URL` to the deployed origin (for example `NEXT_PUBLIC_SITE_URL=https://your-domain npm run deploy`, or in `.env.production`). It's baked in at build time and used for canonical links, `sitemap.xml`, `robots.txt` and the absolute URLs of social previews; without it they point at localhost. Page titles, descriptions and Open Graph tags come from `pageMetadata` in `src/lib/metadata.ts`; the favicon (`src/app/favicon.ico`, 16–48 px), `icon.png`, `apple-icon.png` and `manifest.ts` sit in `src/app`, and `public/media/og.jpg` is the 1200×630 preview. A social with an empty `href` (Discord, for now) is hidden everywhere until it's filled in.

## Where things come from

- `src/fonts/` – Latin subsets (WOFF2) of the SF Pro Rounded files in `inspo/assets/hero-video/fonts`, loaded with `next/font/local`.
- `public/media/slice-editor.mp4` – the hero, `inspo/assets/hero-video/recorder-editor-hero.mov`, video only, H.264 at 2240 px and 3.6 Mbps.
- `public/media/slice-demo.mp4` – the Output section, `inspo/assets/hero-video/hero-video-slice-2.mp4` from 3.3 s, H.264 at 1920 px and 2.6 Mbps.
- `public/media/capture-bar.mp4` – the Record feature, `inspo/assets/hero-video/floating-nav.mov`, H.264 at 2052 px.
- `public/media/liquid-lens.mp4` – the Zoom feature, `inspo/assets/hero-video/liquid-lens-hero.mp4`, H.264 at 1080 px.
- `public/media/iphone-3d.mp4` – `inspo/assets/hero-video/mockup-recording-test.mp4`, video only, H.264 at 1440 px and 2.2 Mbps.
- `public/media/slice-wallpaper.jpg` – the Welcome post's cover, a screenshot of the editor flattened onto black and cropped to 16:10.
- `public/dock/` – Finder, Safari, Messages and Mail icons rendered from this Mac's apps with NSWorkspace, plus Slice's own icon.
- `public/media/apple-logo.png` – `inspo/assets/hero-video/png-apple-logo-9711.png` at 512 px, drawn through Paper's `Heatmap` shader in `ThermalApple`.

## Motion

Timing and easing follow the expo-content-transition site: entrances blur in over 0.7 s on `cubic-bezier(0.22, 1, 0.36, 1)`, 80 ms apart (`.blur-in`, `[data-reveal]`). `SwapText` is the ChatGPT ⇄ Codex switcher from sohna.dev/waterlemon, ported to Motion with the same values: outgoing letters blur to 16px, drop 16px and shrink to 0.7; incoming letters fall in from 16px above out of an 8px blur on a spring (bounce 0.56), 50 ms apart. Distances are scaled from the reference's 72px headline.

The Download buttons are `MetalButton`, the liquid-metal rim from rit3zh-gradients (Paper's `liquidMetal` shader behind a black face). The dock in the Mac section is `motion`-driven, with magnification, tooltips and a launch hop. `border-beam` outlines the dock. The FAQ is a fisheye accordion: rows scale by their distance from the pointer and the nearest one opens. The hero video settles from 0.92 scale as it scrolls in, using a CSS scroll-driven animation (transform only). Everything respects `prefers-reduced-motion`.

Record, Zoom and iPhone in the Features section are real recordings; Cursor, Transcript and Voice are drawn in HTML and CSS.

The nav is a floating bar that eases into a compact, frosted state once you scroll past the top (one `data-settled` switch, CSS transitions). It shows only Features, Roadmap and Blog; Explore grows the bar into a three-column menu over the blurred page, and on narrow screens the same menu opens from the menu button. The page ends in `End`: a single footer row with the social links.

## Blog

Posts are MDX files in `content/blog/`, read by fumadocs-mdx (`source.config.ts`, `src/lib/blog.ts`) and served at `/blog` and `/blog/<file-name>`. Frontmatter: `title`, `description`, `date` and an optional `cover` from `public/media`. Inside a post, `<Figure src poster alt caption />` shows a still or a real recording. A post page follows Vercel's blog: the title and author (`public/media/rit3zh.jpg`), then the text beside a sticky rail with the date, reading time, a Copy menu (link or Markdown) and the post's sections. The `cover` shows on the blog list and in link previews, not on the post itself. The blog is set in Geist and Geist Mono, like the expo-content-transition site.

## Roadmap

`/roadmap` is built from `src/components/Roadmap/content.ts`: two hand-drawn checklists. Planned items keep an empty box; shipped ones are ticked and struck through in turn as the list scrolls into view.

## License page

`/license` is built from `src/components/License/content.ts`. Its text is a **draft**: the repository's `LICENSE` is still the Unlicense. Until `license.final` is set to `true`, the page shows a draft notice and is `noindex`. It is linked from the nav and footer. "To decide" blocks mark open questions and are left out of the copied text.
