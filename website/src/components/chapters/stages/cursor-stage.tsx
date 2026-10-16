
const P0 = [70, 250];
const P1 = [150, 40];
const P2 = [330, 300];
const P3 = [410, 90];
const SMOOTH = `M${P0} C${P1} ${P2} ${P3}`;

function bezier(t: number, i: 0 | 1) {
	const u = 1 - t;
	return u * u * u * P0[i] + 3 * u * u * t * P1[i] + 3 * u * t * t * P2[i] + t * t * t * P3[i];
}

const RAW = Array.from({ length: 34 }, (_, k) => {
	const t = k / 33;
	const n = k === 0 || k === 33 ? 0 : 1;
	const x = bezier(t, 0) + n * 9 * Math.sin(k * 2.7);
	const y = bezier(t, 1) + n * 11 * Math.cos(k * 1.9 + 0.4);
	return `${x.toFixed(1)},${y.toFixed(1)}`;
}).join(" ");

export default function CursorStage() {
	return (
		<div className="absolute inset-0" aria-hidden>
			<div className="absolute top-[2.4em] left-[2.6em] flex gap-[1.8em]">
				<span className="flex items-center gap-[0.6em] text-[1.2em] text-[#8a8c93]">
					<i className="h-0 w-[1.6em] border-t-[0.14em] border-dashed border-[#5e6067]" />
					Recorded
				</span>
				<span className="flex items-center gap-[0.6em] text-[1.2em] text-[#8a8c93]">
					<i className="h-0 w-[1.6em] border-t-[0.16em] border-[#66a3ff]" />
					Smoothed
				</span>
			</div>
			<svg className="absolute inset-x-0 top-[3em] h-[calc(100%-3em)] w-full overflow-visible" viewBox="0 0 480 340">
				<polyline points={RAW} className="fill-none stroke-[#5e6067] [stroke-width:1.5] [stroke-dasharray:3_4] [stroke-linejoin:round]" />
				<path d={SMOOTH} className="fill-none stroke-[#66a3ff] stroke-2 [stroke-linecap:round]" />
				<circle cx={P3[0]} cy={P3[1]} r="0" className="fill-[rgb(77_140_245/0.18)] stroke-[#4d8cf5] stroke-2">
					<animate
						attributeName="r"
						dur="3.6s"
						repeatCount="indefinite"
						values="0;0;26;26"
						keyTimes="0;0.72;0.92;1"
					/>
					<animate
						attributeName="opacity"
						dur="3.6s"
						repeatCount="indefinite"
						values="0;0.9;0;0"
						keyTimes="0;0.72;0.92;1"
					/>
				</circle>
				<g>
					<animateMotion
						dur="3.6s"
						repeatCount="indefinite"
						path={SMOOTH}
						keyPoints="0;0;1;1"
						keyTimes="0;0.08;0.7;1"
						calcMode="spline"
						keySplines="0 0 1 1;0.45 0 0.55 1;0 0 1 1"
					/>
					<path
						d="M0 0v21.6l5.3-5.1 3.4 8 3.3-1.4-3.4-7.9h7.3L0 0Z"
						fill="#0b0b0d"
						stroke="#fff"
						strokeWidth="1.6"
						strokeLinejoin="round"
					/>
				</g>
			</svg>
		</div>
	);
}
