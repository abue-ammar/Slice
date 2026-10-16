import { reveal } from "@/lib/reveal";
import SectionHeading, { sectionClass } from "./section-heading";
import Video from "./video";

export default function OutputSection() {
	return (
		<section id="output" className={sectionClass}>
			<SectionHeading title="What comes out the other end." center>
				One take, finished in the editor: a Liquid Glass lens on the address bar, zooms that follow the cursor and a
				3D iPhone at the end.
			</SectionHeading>
			<div
				{...reveal(3)}
				className="mt-[clamp(40px,6vw,64px)] aspect-[1920/1206] overflow-hidden rounded-[18px] bg-black shadow-[0_0_0_1px_var(--color-line-strong),0_60px_120px_-50px_rgb(0_0_0/0.9)]"
			>
				<Video
					className="block size-full object-cover"
					src="/media/slice-demo.mp4"
					poster="/media/slice-demo.jpg"
					label="A video exported from Slice: a Liquid Glass lens magnifies the address bar, then the view zooms and follows the cursor through a website and onto a 3D iPhone."
				/>
			</div>
		</section>
	);
}
