import PageShell from "@/components/page-shell";

export default function BlogLayout({ children }: LayoutProps<"/blog">) {
	return <PageShell>{children}</PageShell>;
}
