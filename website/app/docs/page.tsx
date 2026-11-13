import type { Metadata } from "next";
import type { ReactNode } from "react";
import { GITHUB_URL, SiteFooter, SiteHeader } from "@/components/site-chrome";
import { SnippetBlock } from "@/components/snippet-block";

export const metadata: Metadata = {
  title: "Docs",
  description:
    "How to use morphicons: install, the three modes, every framework binding, filled icons, adapters, icon libraries and how the math works.",
  alternates: { canonical: "/docs" },
};

/* One page of docs, written for the site. The README stays short on purpose
   and remains the source of truth for the API surface; this page is the
   longer read. Keep the two in agreement when either changes. */

const SECTIONS: { id: string; label: string }[] = [
  { id: "install", label: "Install" },
  { id: "usage", label: "Usage" },
  { id: "frameworks", label: "Frameworks" },
  { id: "vanilla", label: "Without a framework" },
  { id: "fill", label: "Filled icons" },
  { id: "libraries", label: "Icon libraries" },
  { id: "adapters", label: "Format adapters" },
  { id: "reduced-motion", label: "Reduced motion" },
  { id: "how-it-works", label: "How it works" },
  { id: "size", label: "Size" },
  { id: "credits", label: "Credits" },
];

function Code({ children }: { children: ReactNode }) {
  return (
    <code className="rounded bg-canvas-soft-2 px-1.5 py-0.5 font-mono text-[13px] text-ink">
      {children}
    </code>
  );
}

function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} className="scroll-mt-8 border-t border-hairline pt-10">
      <h2 className="text-2xl font-semibold tracking-[-0.03em] text-ink">
        <a href={`#${id}`} className="hover:underline hover:decoration-hairline">
          {title}
        </a>
      </h2>
      <div className="mt-5 flex flex-col gap-5 text-[15px] leading-7 text-body">{children}</div>
    </section>
  );
}

function H3({ children }: { children: ReactNode }) {
  return <h3 className="mt-3 text-[17px] font-medium text-ink">{children}</h3>;
}

function Table({ head, rows }: { head: [string, string]; rows: [ReactNode, ReactNode][] }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-hairline">
      <table className="w-full text-left text-sm">
        <thead className="bg-canvas-soft text-ink">
          <tr>
            <th className="px-4 py-2.5 font-medium">{head[0]}</th>
            <th className="px-4 py-2.5 font-medium">{head[1]}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([a, b], i) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: static rows
            <tr key={i} className="border-t border-hairline align-top">
              <td className="px-4 py-2.5 whitespace-nowrap">{a}</td>
              <td className="px-4 py-2.5">{b}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const QUICK = `import { MorphIcon } from "morphicons/react";
import { Menu, X } from "lucide"; // icon data, not components

<button onClick={() => setOpen((o) => !o)} aria-expanded={open}>
  <MorphIcon icon={open ? X : Menu} />
</button>`;

const MODES = `// 1. Uncontrolled: change the prop and it animates
<MorphIcon icon={open ? X : Menu} />

// 2. Controlled: you drive the progress (gestures, scroll), no spring
<MorphIcon from={Menu} to={X} progress={0.4} />

// 3. Imperative: sequences
const ref = useRef<MorphHandle>(null);
<MorphIcon ref={ref} icon={Menu} />
ref.current?.morphTo(Check); // animates
ref.current?.set(X);         // jumps, no animation`;

const VUE = `<script setup lang="ts">
import { ref } from "vue";
import { MorphIcon, type MorphHandle } from "morphicons/vue";
import { Menu, X } from "lucide";

const open = ref(false);
const morph = ref<MorphHandle | null>(null); // morph.value?.morphTo(X)
</script>

<template>
  <MorphIcon :icon="open ? X : Menu" />
  <MorphIcon ref="morph" :icon="Menu" />
</template>`;

const SVELTE = `<script lang="ts">
  import { MorphIcon, type MorphHandle } from "morphicons/svelte";
  import { Menu, X } from "lucide";

  let open = $state(false);
  let morph = $state<MorphHandle>(); // morph?.morphTo(X)
</script>

<MorphIcon icon={open ? X : Menu} />
<MorphIcon bind:this={morph} icon={Menu} />`;

const RN = `import { MorphIcon } from "morphicons/react-native";
import { Menu, X } from "lucide";

<MorphIcon icon={open ? X : Menu} color="#111" />`;

const ASTRO = `---
import MorphIcon from "morphicons/astro";
import { Menu } from "lucide";
---

<MorphIcon icon={Menu} label="Menu" id="menu-icon" />

<script>
  import { X } from "lucide";
  import type { MorphIconElement } from "morphicons/element";

  const el = document.querySelector<MorphIconElement>("#menu-icon")!;
  el.morphTo(X);
</script>`;

const ELEMENT = `<script type="module">
  import { defineMorphIcon } from "morphicons/element";
  defineMorphIcon(); // idempotent; a custom tag: defineMorphIcon("my-icon")
</script>

<!-- attributes take d strings, properties take any icon -->
<morph-icon icon="M4 6h16M4 12h16M4 18h16" label="Menu"></morph-icon>`;

const VANILLA = `import { createMorph } from "morphicons/dom";

const m = createMorph(pathEl, Menu); // an SVG <path>
m.morphTo(X, "snappy");              // a preset or { stiffness, damping }
m.set(Check);                        // jump, no animation
m.seek(X, 0.4);                      // frozen at t: scrubbing, gestures
m.progress = 0.4;                    // seek on the active target
m.reducedMotion = "user";            // live policy
m.destroy();`;

const CORE = `import { allocOutputs, buildPlan, interpPolar, resampleIcon, serialize } from "morphicons";

const plan = buildPlan(resampleIcon(Menu), resampleIcon(X)); // cache it
const out = allocOutputs(plan);
interpPolar(plan, 0.5, out);                                 // t in [0, 1]
const d = serialize(out, plan.items.map((it) => it.closed));`;

const REGION = `import { setRegionLoader } from "morphicons/dom";
import * as region from "morphicons/region";

setRegionLoader(async () => region); // bundle the fill code, no network`;

const FIT = `import { fitIcon } from "morphicons";
import { svgToIcon } from "morphicons/adapters";

const search = fitIcon(carbonSearch, 32);  // a 32×32 path onto the 24 grid
const star = svgToIcon(markup);            // reads the viewBox and the fill`;

const MASK = `import { maskTarget, svgToIcon } from "morphicons/adapters";
import { createMorph } from "morphicons/dom";

const MENU = svgToIcon(menuBody); // parse once, at module scope
const X = svgToIcon(xBody);

const target = maskTarget(span);  // <span class="i-lucide-menu size-5">
const m = createMorph(target, MENU);
m.morphTo(X);
// on unmount: m.destroy(); target.dispose();`;

const CANVAS = `import { canvasTarget } from "morphicons/adapters";
import { createMorph } from "morphicons/dom";

const m = createMorph(canvasTarget(canvas, { color: "#e8eaed" }), PLAY);
m.morphTo(PAUSE);`;

const PIPELINE = `icon A ─┐
        ├→ normalize → resample → match → align → plan → interpolate(t) → d
icon B ─┘                                        (cached per pair)`;

const PROCRUSTES = `θ* = atan2(Σ aₓbᵧ − aᵧbₓ,  Σ aₓbₓ + aᵧbᵧ)
σ* = [cos θ*·(Σ aₓbₓ + aᵧbᵧ) + sin θ*·(Σ aₓbᵧ − aᵧbₓ)] / Σ‖aᵢ‖²`;

const POLAR = `P(t) = c(t) + σ*ᵗ · R(t·θ*) · [(1−t)·aᵢ + t·b̃ᵢ]

c(t)   translation, a plain lerp
t·θ*   angle, linear (θ* already takes the short way)
σ*ᵗ    scale, log-linear
b̃ᵢ     B brought into A's frame`;

export default function Docs() {
  return (
    <div className="flex flex-1 flex-col">
      <SiteHeader />

      <div className="mx-auto grid w-full max-w-[1100px] flex-1 grid-cols-[minmax(0,1fr)] gap-12 px-6 pb-24 pt-16 lg:grid-cols-[180px_minmax(0,1fr)]">
        <aside className="max-lg:hidden">
          <nav aria-label="On this page" className="sticky top-8">
            <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-mute">
              On this page
            </p>
            <ul className="mt-4 flex flex-col gap-2 text-sm">
              {SECTIONS.map((s) => (
                <li key={s.id}>
                  <a href={`#${s.id}`} className="text-body transition-colors hover:text-ink">
                    {s.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </aside>

        <main className="flex max-w-[720px] flex-col gap-12">
          <header>
            <h1 className="text-4xl font-semibold leading-[1.05] tracking-[-0.045em] text-ink">
              Docs
            </h1>
            <p className="mt-4 max-w-[560px] text-lg leading-7 text-body">
              Morph any SVG icon into any other, stroked or filled, with spring physics. Change
              the prop and the icon morphs: no wrappers, keys or per-pair setup.
            </p>
            <div className="mt-8">
              <SnippetBlock label="tsx" code={QUICK} />
            </div>
          </header>

          <Section id="install" title="Install">
            <SnippetBlock label="terminal" code="npm install morphicons" />
            <p>
              ESM only, zero runtime dependencies. Framework peers are optional: you only need{" "}
              <Code>react</Code> (18+), <Code>vue</Code> (3.3+), <Code>svelte</Code> (5+) or{" "}
              <Code>react-native</Code> (0.71+) with <Code>react-native-svg</Code> (14+) for the
              entry you import. The element and Astro entries need none.
            </p>
            <Table
              head={["entry", "what it gives you"]}
              rows={[
                [<Code key="r">morphicons/react</Code>, "<MorphIcon>, also vue, svelte and react-native"],
                [<Code key="a">morphicons/astro</Code>, "an Astro component that renders on the server"],
                [<Code key="e">morphicons/element</Code>, "the <morph-icon> custom element, for plain HTML"],
                [<Code key="d">morphicons/dom</Code>, "createMorph(), no framework"],
                [<Code key="ad">morphicons/adapters</Code>, "svgToIcon, maskTarget, canvasTarget"],
                [<Code key="rg">morphicons/region</Code>, "the fill code, normally loaded on demand"],
                [<Code key="c">morphicons</Code>, "the pure core, no DOM"],
              ]}
            />
            <H3>Icons are data</H3>
            <p>
              morphicons takes icon <em>data</em>: an <Code>IconNode</Code> (Lucide&rsquo;s
              format, <Code>[tag, attrs][]</Code>) or a raw <Code>d</Code> string. For Lucide,
              import from <Code>lucide</Code>, not <Code>lucide-react</Code>: the framework
              packages export components, which <Code>MorphIcon</Code> can&rsquo;t read. If your
              app already uses them for static icons, keep them; both tree-shake, so you only pay
              for what you import. Keep their versions aligned.
            </p>
          </Section>

          <Section id="usage" title="Usage">
            <p>Three modes, the same in every binding:</p>
            <SnippetBlock label="tsx" code={MODES} />
            <Table
              head={["prop", ""]}
              rows={[
                [
                  <Code key="s">size, color, strokeWidth, absoluteStrokeWidth</Code>,
                  "as in lucide-react; other <svg> attributes pass through",
                ],
                [
                  <Code key="sp">spring</Code>,
                  <>
                    <Code>&quot;snappy&quot;</Code> (default), <Code>&quot;smooth&quot;</Code>,{" "}
                    <Code>&quot;bouncy&quot;</Code> or <Code>{"{ stiffness, damping }"}</Code>
                  </>,
                ],
                [
                  <Code key="rm">reducedMotion</Code>,
                  <>
                    <Code>&quot;never&quot;</Code> (default), <Code>&quot;user&quot;</Code> or{" "}
                    <Code>&quot;always&quot;</Code>, see <a className="underline" href="#reduced-motion">Reduced motion</a>
                  </>,
                ],
                [
                  <Code key="l">label</Code>,
                  <>
                    accessible name: <Code>role=&quot;img&quot;</Code> plus a <Code>&lt;title&gt;</Code>.
                    Without it the icon is <Code>aria-hidden</Code>
                  </>,
                ],
              ]}
            />
            <p>
              SSR renders the final SVG, computed once on the server, so nothing flashes or shifts
              on hydration. A <Code>morphTo</Code> mid-flight starts from the shape on screen and
              keeps the spring&rsquo;s velocity: clicking fast never jumps. Every icon on the page
              shares one <Code>requestAnimationFrame</Code>.
            </p>
            <H3>Lifecycle</H3>
            <ul className="flex list-disc flex-col gap-2 pl-5">
              <li>
                Mounting without an icon is fine (data that loads later). The first icon appears
                without animating, and a <Code>morphTo</Code> before it acts as <Code>set</Code>.
              </li>
              <li>
                While <Code>from</Code> and <Code>to</Code> are both set, they win over{" "}
                <Code>icon</Code>. Drop the pair and <Code>icon</Code> takes over, animated.
              </li>
              <li>Leaving controlled mode and coming back renders like a fresh mount.</li>
            </ul>
          </Section>

          <Section id="frameworks" title="Frameworks">
            <p>
              Five bindings with the same props, modes and lifecycle. React is above; the others
              look like this.
            </p>
            <H3>Vue 3</H3>
            <SnippetBlock label="vue" code={VUE} />
            <p>A plain render function, no SFC compiler involved. Works with Nuxt SSR.</p>
            <H3>Svelte 5</H3>
            <SnippetBlock label="svelte" code={SVELTE} />
            <p>
              Ships as <Code>.svelte</Code> source that your bundler compiles. Works with SvelteKit
              SSR. Attributes are typed through <Code>svelte/elements</Code>.
            </p>
            <H3>React Native</H3>
            <SnippetBlock label="tsx" code={RN} />
            <p>
              The React API over <Code>react-native-svg</Code>, on the same driver as the web.
              Needs Metro with package <Code>exports</Code>, the default since React Native 0.79.
              With <Code>label</Code> it sets <Code>aria-label</Code>.
            </p>
            <H3>Astro</H3>
            <SnippetBlock label="astro" code={ASTRO} />
            <p>
              The server renders the SVG and the browser upgrades it to a{" "}
              <Code>&lt;morph-icon&gt;</Code>, with no framework runtime. Control it from a script
              through the element: <Code>el.icon = X</Code> animates,{" "}
              <Code>el.morphTo</Code> and <Code>el.set</Code> work like a ref, and{" "}
              <Code>from</Code>, <Code>to</Code> and <Code>progress</Code> scrub.
            </p>
            <H3>Plain HTML</H3>
            <SnippetBlock label="html" code={ELEMENT} />
            <p>
              Works in HTMX, Rails or any server-rendered stack. The element is its own handle. If
              it already contains a server-rendered <Code>&lt;svg&gt;&lt;path&gt;</Code>, it
              adopts it as is.
            </p>
          </Section>

          <Section id="vanilla" title="Without a framework">
            <SnippetBlock label="ts" code={VANILLA} />
            <p>
              <Code>createMorph(el, icon, options)</Code> takes any object with{" "}
              <Code>setAttribute</Code>. Options: <Code>reducedMotion</Code> and{" "}
              <Code>strokeWidth</Code> (the width a stroked icon is outlined with when it morphs
              into a filled one, default 2). The pure core works with no DOM at all:
            </p>
            <SnippetBlock label="ts" code={CORE} />
          </Section>

          <Section id="fill" title="Filled icons">
            <p>
              When either icon is filled, both morph as filled shapes, so a stroked heart can
              turn into a solid one. An icon counts as filled when one of its elements has a{" "}
              <Code>fill</Code> other than <Code>none</Code>; a raw <Code>d</Code> string is
              always stroked. <Code>svgToIcon</Code> keeps the fill of the markup it reads.
            </p>
            <p>
              The code for this (5.4 KB gzip) loads the first time a filled icon shows up;
              stroke-only apps never download it. Until then a filled icon still renders filled,
              and a morph waits at most 100 ms for the chunk before flying a simpler fallback.
              To bundle it instead:
            </p>
            <SnippetBlock label="ts" code={REGION} />
            <p>
              Or call <Code>preloadRegion()</Code> from <Code>morphicons/dom</Code> to fetch it
              early. For long lists of filled icons on slow devices, run <Code>toRegion(icon)</Code>{" "}
              from <Code>morphicons/region</Code> at build time: the driver uses its output as is.
            </p>
          </Section>

          <Section id="libraries" title="Icon libraries">
            <p>
              There is no per-library setup. Any set on a 24×24 grid works as is: Lucide, Tabler,
              Heroicons, Iconoir, Phosphor, Material Symbols, Remix Icon, MingCute and the{" "}
              <a className="underline" href="https://www.shadcn.io/icons" target="_blank" rel="noopener noreferrer">
                shadcn registry
              </a>
              . Both icons of a morph must share a grid, so mixing libraries is fine.
            </p>
            <p>
              For other grids (Heroicons mini on 20, Bootstrap on 16, Carbon on 32), re-grid once,
              at module scope:
            </p>
            <SnippetBlock label="ts" code={FIT} />
            <p>
              <Code>fitIcon</Code> returns a <Code>d</Code> string, which is a stroked icon. For
              filled icons on another grid, use <Code>svgToIcon</Code>: it reads the{" "}
              <Code>viewBox</Code> and keeps the paint. Supported elements are{" "}
              <Code>path</Code>, <Code>line</Code>, <Code>circle</Code>, <Code>ellipse</Code>,{" "}
              <Code>rect</Code>, <Code>polyline</Code> and <Code>polygon</Code>.
            </p>
          </Section>

          <Section id="adapters" title="Format adapters">
            <p>
              <Code>morphicons/adapters</Code> converts other formats in and out. Each adapter
              tree-shakes on its own, so you pay for the one you import.
            </p>
            <ul className="flex list-disc flex-col gap-2 pl-5">
              <li>
                <Code>svgToIcon(markup)</Code>: SVG markup to an icon. An Iconify body, a full{" "}
                <Code>&lt;svg&gt;</Code> or a pasted <Code>&lt;path&gt;</Code>. Transforms are
                baked in, <Code>&lt;defs&gt;</Code> and masks are dropped.
              </li>
              <li>
                <Code>maskTarget(el)</Code>: morphs CSS-mask icons in place (UnoCSS{" "}
                <Code>presetIcons</Code>, Tailwind icon plugins), keeping your classes.
              </li>
              <li>
                <Code>canvasTarget(canvas)</Code>: draws the morph into a canvas, an{" "}
                <Code>OffscreenCanvas</Code> or a 2D context. For WebGL textures, video, workers or
                an animated favicon.
              </li>
            </ul>
            <SnippetBlock label="ts" code={MASK} />
            <SnippetBlock label="ts" code={CANVAS} />
            <p>
              <Code>maskTarget</Code> and <Code>canvasTarget</Code> draw strokes only for now. A
              host with its own render loop (Konva, Chart.js, a game) should give the icon a small
              canvas of its own and composite it, using the <Code>onWrite</Code> option as the
              repaint signal. See the{" "}
              <a className="underline" href="/showcase/mask">
                mask
              </a>{" "}
              and{" "}
              <a className="underline" href="/showcase/canvas">
                canvas
              </a>{" "}
              demos.
            </p>
          </Section>

          <Section id="reduced-motion" title="Reduced motion">
            <p>
              Icon morphs are short, small transitions, so they play by default even with the
              OS reduce-motion setting on. The policy is explicit:
            </p>
            <ul className="flex list-disc flex-col gap-2 pl-5">
              <li>
                <Code>&quot;never&quot;</Code> (default): always animate.
              </li>
              <li>
                <Code>&quot;user&quot;</Code>: follow the OS setting; while it is on, every{" "}
                <Code>morphTo</Code> jumps. React Native reads <Code>AccessibilityInfo</Code>.
              </li>
              <li>
                <Code>&quot;always&quot;</Code>: never animate (tests, screenshots).
              </li>
            </ul>
            <p>
              Apps that must follow the user&rsquo;s preference should pass{" "}
              <Code>reducedMotion=&quot;user&quot;</Code> everywhere.
            </p>
          </Section>

          <Section id="how-it-works" title="How it works">
            <p>
              The core is pure functions: icon data in, <Code>d</Code> strings out. Planning a pair
              takes well under a millisecond and is cached; each frame allocates only the{" "}
              <Code>d</Code> string.
            </p>
            <SnippetBlock label="pipeline" code={PIPELINE} />
            <ol className="flex list-decimal flex-col gap-3 pl-5">
              <li>
                <strong className="font-medium text-ink">Normalize.</strong> Every SVG shape becomes
                cubic Béziers: lines, quadratics, circles and arcs.
              </li>
              <li>
                <strong className="font-medium text-ink">Resample.</strong> Each subpath becomes 64
                points evenly spaced by arc length, so point <em>i</em> of A maps to point{" "}
                <em>i</em> of B. Corners are exact sample points, so they stay sharp at rest.
              </li>
              <li>
                <strong className="font-medium text-ink">Match.</strong> Both directions are tried
                and, for closed paths, every starting point. Subpaths pair by position and length;
                when the counts differ, the extra pieces split off the nearest one instead of
                appearing from nothing.
              </li>
              <li>
                <strong className="font-medium text-ink">Align.</strong> The rotation θ and scale σ
                that best map A onto B have a closed form in 2D (Procrustes):
              </li>
            </ol>
            <SnippetBlock label="procrustes" code={PROCRUSTES} />
            <p>
              The error left over says how different the shapes are. Near zero means B is A
              rotated, so arrow-right to arrow-down turns 90° without anyone declaring it. Among
              equal fits the shortest turn wins (<Code>error + 0.05·|θ|/π</Code>), which is why a
              hamburger folds into an X at 45° and never at 135°. When the whole icon is one
              rotated shape, all its parts turn together, as a rigid block.
            </p>
            <ol start={5} className="flex list-decimal flex-col gap-3 pl-5">
              <li>
                <strong className="font-medium text-ink">Interpolate.</strong> Rotation, scale and
                shape are interpolated separately, so a rotation never collapses through the
                middle the way a plain coordinate blend does:
              </li>
            </ol>
            <SnippetBlock label="interpolate" code={POLAR} />
            <ol start={6} className="flex list-decimal flex-col gap-3 pl-5">
              <li>
                <strong className="font-medium text-ink">Spring.</strong>{" "}
                <Code>ẍ = k·(1 − x) − c·ẋ</Code> drives <em>t</em>. Past 1 the formula extrapolates,
                so the overshoot rotates and scales a little too. On settle the driver writes the
                target&rsquo;s exact <Code>d</Code>.
              </li>
            </ol>
            <Table
              head={["preset", "feel"]}
              rows={[
                [<Code key="sm">smooth</Code>, "k 170, c 26: no overshoot"],
                [<Code key="sn">snappy</Code>, "k 420, c 30: fast, a slight overshoot (default)"],
                [<Code key="b">bouncy</Code>, "k 300, c 14: playful"],
              ]}
            />
            <p>
              A filled icon has no line to follow, so when either side is filled both are reduced
              to their visible surface (a distance field traced into closed contours, holes wound
              the other way) and go through the same steps. The full write-up, with the decisions
              behind it, is in{" "}
              <a
                className="underline"
                href={`${GITHUB_URL}/blob/main/docs/how-it-works.md`}
                target="_blank"
                rel="noopener noreferrer"
              >
                docs/how-it-works.md
              </a>{" "}
              and the{" "}
              <a
                className="underline"
                href={`${GITHUB_URL}/tree/main/docs/adr`}
                target="_blank"
                rel="noopener noreferrer"
              >
                ADRs
              </a>
              .
            </p>
          </Section>

          <Section id="size" title="Size">
            <p>gzip, with gates enforced in CI so it can&rsquo;t grow unnoticed.</p>
            <Table
              head={["entry", "gzip"]}
              rows={[
                [<Code key="c">morphicons</Code>, "6.7 KB"],
                [<Code key="d">morphicons/dom</Code>, "9.3 KB"],
                [<Code key="r">react</Code>, "10.2 KB"],
                [<Code key="v">vue</Code>, "10.3 KB"],
                [<Code key="s">svelte</Code>, "9.9 KB"],
                [<Code key="e">element</Code>, "11.1 KB"],
                [<Code key="rn">react-native</Code>, "15.9 KB (Metro inlines the fill code)"],
                [<Code key="f">fill code</Code>, "+5.4 KB, on first use"],
                [<Code key="a">adapters</Code>, "0.5 to 4.3 KB each"],
              ]}
            />
          </Section>

          <Section id="credits" title="Credits">
            <p>
              The icons in the playground belong to their authors: Lucide (ISC), Heroicons, Tabler,
              Phosphor, Iconoir and Bootstrap Icons (MIT), Material Symbols, Material Design Icons,
              Remix Icon and MingCute (Apache 2.0). morphicons is MIT, made by{" "}
              <a className="underline" href="https://guillermolg.com" target="_blank" rel="noopener noreferrer">
                guillermolg.com
              </a>
              .
            </p>
          </Section>
        </main>
      </div>

      <SiteFooter />
    </div>
  );
}
