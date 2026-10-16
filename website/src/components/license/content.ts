export const license = {
	final: false,
	name: "Slice Source-Available License",
	type: "Source-available",
	version: "",
	updated: "",
	copyright: "Copyright © 2026 rit3zh",
	repo: "https://github.com/infinite-toby/screen-recorder",
};

export type Block = { p: string } | { list: string[] } | { todo: string };

export type Clause = { id: string; title: string; body: Block[] };

export const CLAUSES: Clause[] = [
	{
		id: "purpose",
		title: "Purpose",
		body: [
			{
				p: "Slice is source-available software. Its source code is published so that people can use it, learn from it, change it for themselves, and help improve it. This license grants those freedoms while keeping the right to sell or commercially redistribute Slice with the Licensor.",
			},
			{
				p: "Slice is not open source software as defined by the Open Source Initiative, because this license restricts commercial redistribution.",
			},
		],
	},
	{
		id: "definitions",
		title: "Definitions",
		body: [
			{
				list: [
					"“Licensor” means rit3zh, the copyright holder of Slice.",
					"“Software” means Slice, including its source code, compiled applications, documentation and other files published in the official repository.",
					"“You” means the individual or entity exercising the rights granted by this license.",
					"“Modified Version” means any work that contains the Software, or a substantial part of it, with changes.",
					"“Distribute” means to make the Software or a Modified Version available to anyone else, by any means.",
					"“Commercial” means intended for, or directed toward, payment, commercial advantage or monetary compensation, including through sales, subscriptions, advertising or bundling with a paid product or service.",
				],
			},
		],
	},
	{
		id: "personal-use",
		title: "Personal use",
		body: [
			{
				p: "You may download, install and run the Software, free of charge, on any device you own or control.",
			},
			{
				p: "Recordings, videos and other content you create with the Software belong to you. This license places no restrictions on how you use them.",
			},
			{
				todo: "Decide whether using Slice at work, or inside a company, counts as permitted use, and say so here.",
			},
		],
	},
	{
		id: "source-access",
		title: "Inspecting and cloning the source",
		body: [
			{
				p: "You may view, download, clone and fork the source code from the official repository, build it yourself, and study how it works.",
			},
		],
	},
	{
		id: "modifications",
		title: "Personal modifications",
		body: [
			{
				p: "You may modify the Software and run your Modified Version for your own use.",
			},
			{
				p: "Modifying the Software for yourself is permitted. Distributing a Modified Version commercially is not, unless the Licensor has given you written permission under section 11.",
			},
			{
				todo: "Decide whether non-commercial sharing of a Modified Version (for example, a public fork) is allowed, and on what conditions.",
			},
		],
	},
	{
		id: "contributions",
		title: "Contributions",
		body: [
			{
				p: "You may propose changes to the Software by opening issues and submitting pull requests to the official repository.",
			},
			{
				p: "By submitting a contribution, you confirm that you have the right to submit it, and you grant the Licensor a perpetual, worldwide, non-exclusive, royalty-free license to use, modify and distribute that contribution as part of the Software under this license or any later license the Licensor chooses.",
			},
			{
				p: "You keep the copyright in your contribution. Submitting a pull request does not transfer ownership of any code to you or to the Licensor beyond the contribution itself, and gives you no rights in other parts of the Software beyond those this license already grants.",
			},
			{
				todo: "Confirm these terms match the project's contribution policy. The repository has no CONTRIBUTING file yet.",
			},
		],
	},
	{
		id: "no-commercial-redistribution",
		title: "No commercial redistribution",
		body: [
			{
				p: "You may not Distribute the Software, or a Modified Version, for a Commercial purpose. This includes publishing it in a paid app store listing, bundling it with a paid product or service, or offering it behind a paywall or subscription.",
			},
		],
	},
	{
		id: "no-resale",
		title: "No resale as a standalone application",
		body: [
			{
				p: "You may not sell, license, rent or otherwise charge for the Software or a Modified Version as a standalone application, whether as source code or as a compiled binary.",
			},
		],
	},
	{
		id: "no-rebranding",
		title: "No rebranding as a competing product",
		body: [
			{
				p: "You may not rename or rebrand the Software or a Modified Version and offer it to others as your own screen recording or video editing product, whether or not you charge for it.",
			},
		],
	},
	{
		id: "ownership",
		title: "Ownership and attribution",
		body: [
			{
				p: "The Licensor keeps all copyright and other rights in the Software that this license does not expressly grant. This license does not grant any right to use the Slice name, icon or other marks, except to accurately say where the Software comes from.",
			},
			{
				p: "You must keep this license and the copyright notice with every copy of the Software and every Modified Version.",
			},
			{
				p: "Some files in the Software are under their own licenses, such as the 3D device models, which are licensed under CC BY 4.0. Those licenses continue to apply to those files.",
			},
		],
	},
	{
		id: "commercial-permission",
		title: "Commercial permission",
		body: [
			{
				p: "If you want to use the Software in a way this license does not allow, including commercial redistribution, ask the Licensor. Permission is only valid if it is given in writing, and only for what it expressly covers.",
			},
			{
				todo: "Add the contact address for permission requests.",
			},
		],
	},
	{
		id: "no-warranty",
		title: "No warranty",
		body: [
			{
				p: "THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE LICENSOR OR CONTRIBUTORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.",
			},
		],
	},
	{
		id: "termination",
		title: "Violations and termination",
		body: [
			{
				p: "If you break any term of this license, your rights under it end automatically. You must then stop using and distributing the Software and any Modified Version.",
			},
			{
				todo: "Decide whether rights can be reinstated (for example, if a violation is fixed within 30 days of notice) and state it here.",
			},
		],
	},
];

export type Question = { q: string; a: string };

export const FAQ: Question[] = [
	{
		q: "Can I use Slice for personal use?",
		a: "Yes. You can download, install and run Slice for free on any device you own or control, and the videos you make with it are yours (section 3).",
	},
	{
		q: "Can I modify the source code?",
		a: "Yes, for your own use. You can clone the repository, change the code, build it and run your version yourself (sections 4 and 5).",
	},
	{
		q: "Can I submit pull requests?",
		a: "Yes. Contributions are welcome through the official repository. You keep the copyright in what you contribute and grant the Licensor a license to use it in Slice (section 6).",
	},
	{
		q: "Can I redistribute a modified version?",
		a: "Not commercially. Commercial distribution of Slice or a modified version needs written permission (sections 7 and 11). Whether non-commercial sharing is allowed hasn't been decided in this draft yet.",
	},
	{
		q: "Can I sell an application built from Slice?",
		a: "No. You can't sell Slice or a modified version as a standalone application, or rebrand it as your own product (sections 8 and 9), unless the Licensor gives you written permission.",
	},
	{
		q: "How do I get permission for commercial redistribution?",
		a: "Ask the Licensor. Permission only counts if it's given in writing, and only covers what it says (section 11).",
	},
	{
		q: "What happens if someone violates the license?",
		a: "Their rights under the license end automatically, and they must stop using and distributing Slice and any modified version (section 13).",
	},
];

export function licenseText() {
	const header = [license.name, license.version && `Version ${license.version}`, license.copyright].filter(Boolean);
	const clauses = CLAUSES.map((clause, i) => {
		const body = clause.body.flatMap((block) => {
			if ("p" in block) return [block.p];
			if ("list" in block) return [block.list.map((item) => `- ${item}`).join("\n")];
			return [];
		});
		return [`${i + 1}. ${clause.title}`, ...body].join("\n\n");
	});
	return [header.join("\n"), ...clauses].join("\n\n\n");
}
