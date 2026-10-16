import { reveal } from "@/lib/reveal";

type Props = {
	eyebrow?: string;
	title: React.ReactNode;
	children?: React.ReactNode;
	center?: boolean;
};

export const sectionClass = "mx-auto max-w-site px-(--gutter) pt-[clamp(96px,13vw,160px)]";

export default function SectionHeading({ eyebrow, title, children, center = false }: Props) {
	return (
		<div className={`max-w-[40rem] ${center ? "mx-auto text-center" : ""}`}>
			{eyebrow && (
				<p {...reveal(0)} className="text-[13px] font-medium text-muted">
					{eyebrow}
				</p>
			)}
			<h2
				{...reveal(1)}
				className="mt-3 font-rounded text-[clamp(28px,3.4vw,38px)] leading-[1.12] font-bold tracking-[-0.02em] text-balance text-fg first:mt-0"
			>
				{title}
			</h2>
			{children && (
				<p {...reveal(2)} className={`mt-4 text-[16px] leading-[1.65] text-pretty text-muted ${center ? "mx-auto max-w-[34rem]" : ""}`}>
					{children}
				</p>
			)}
		</div>
	);
}
