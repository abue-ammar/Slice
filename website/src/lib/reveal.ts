import type { CSSProperties } from "react";

export const reveal = (i = 0) => ({ "data-reveal": "", style: { "--i": i } as CSSProperties });

export const step = (i: number) => ({ "--i": i }) as CSSProperties;
