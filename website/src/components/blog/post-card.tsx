import Image from "next/image";
import Link from "next/link";
import { formatDate, type Post } from "@/lib/blog";

type Props = {
	post: Post;
	priority?: boolean;
};

export default function PostCard({ post, priority = false }: Props) {
	const { title, description, date, cover } = post.data;
	return (
		<Link
			href={post.url}
			className="group/post grid grid-cols-[176px_minmax(0,1fr)] items-center gap-6 border-b border-line py-5 last:border-b-0 max-[560px]:grid-cols-1 max-[560px]:gap-3.5"
		>
			<span className="relative block aspect-[16/10] overflow-hidden rounded-[10px] bg-raised after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:inset-ring after:inset-ring-line-strong">
				{cover && (
					<Image
						src={cover}
						alt=""
						fill
						priority={priority}
						sizes="(max-width: 560px) 100vw, 176px"
						className="object-cover transition-[scale] duration-700 ease-settle group-hover/post:scale-104 motion-reduce:group-hover/post:scale-100"
					/>
				)}
			</span>
			<span className="flex min-w-0 flex-col">
				<time className="text-[13px] text-faint" dateTime={date.toISOString()}>
					{formatDate(date)}
				</time>
				<span className="mt-1 text-[17px] leading-[1.3] font-medium tracking-[-0.015em] text-balance text-fg">{title}</span>
				{description && (
					<span className="mt-1.5 line-clamp-2 text-[14px] leading-[1.6] text-pretty text-muted transition-colors duration-200 ease-out group-hover/post:text-body">
						{description}
					</span>
				)}
			</span>
		</Link>
	);
}
