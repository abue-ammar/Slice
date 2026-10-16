"use client";

import { MotionConfig } from "motion/react";

export default function MotionPreferences({ children }: { children: React.ReactNode }) {
	return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
