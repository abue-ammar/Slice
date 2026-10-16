import End from "./end";
import Nav from "./nav";
import MotionPreferences from "./ui/motion-preferences";

export default function PageShell({ children }: { children: React.ReactNode }) {
	return (
		<div className="flex min-h-dvh flex-col">
			<Nav />
			<MotionPreferences>
				<div className="flex-1">{children}</div>
			</MotionPreferences>
			<End compact />
		</div>
	);
}
