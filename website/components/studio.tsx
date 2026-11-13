"use client";

import { Pause, Play } from "lucide";
import { buildPlan, resampleIcon, SPRING_PRESETS, type Sampled, type SpringPreset } from "morphicons";
import { canonicalD, createMorph, type Morph, type MorphOptions, restAttrs } from "morphicons/dom";
import { MorphIcon } from "morphicons/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { LibraryPicker } from "@/components/library-picker";
import {
  byId,
  DEFAULT_SEQ,
  type IconEntry,
  iconOf,
  isFilled,
  LIBRARIES,
  libraryById,
  loadedSet,
  loadSet,
  type Style,
  setKey,
} from "@/lib/studio-icons";

/* Pause between autoplayed morphs at 1×: long enough to read each icon at
   rest before the next one takes off. */
const AUTOPLAY_MS = 2400;

const SPRINGS = ["smooth", "snappy", "bouncy"] as const;
const STROKES = [1, 1.5, 2, 2.5] as const;
const SPEEDS = [0.25, 0.5, 1, 2] as const;
const STYLES: { v: Style; label: string }[] = [
  { v: "outline", label: "Outline" },
  { v: "fill", label: "Fill" },
];

/* Time scaled by s: stiffness × s², damping × s keeps the damping ratio, so
   the motion is the same curve played faster or slower. */
function springAt(preset: SpringPreset, speed: number): MorphOptions {
  const { k, c } = SPRING_PRESETS[preset];
  return { stiffness: k * speed * speed, damping: c * speed };
}

const sampleCache = new Map<string, Sampled[]>();
function samplesOf(e: IconEntry): Sampled[] {
  let s = sampleCache.get(e.id);
  if (!s) {
    s = resampleIcon(iconOf(e));
    sampleCache.set(e.id, s);
  }
  return s;
}

const fmtDeg = (rad: number): string => `${Math.round((rad * 180) / Math.PI)}°`;
const libName = (e: IconEntry): string => libraryById.get(e.lib)?.label ?? e.lib;

/* Similarity readout of the rest-to-rest plan for the pair, like the
   playground: the math is the product, so the page shows it. Filled pairs
   fly as regions (lazy chunk), so they get a plain description instead. */
function useReadout(prevId: string | null, curId: string) {
  return useMemo(() => {
    if (!prevId || prevId === curId) return null;
    const a = byId.get(prevId);
    const b = byId.get(curId);
    if (!a || !b) return null;
    const pair = `${a.label} → ${b.label}`;
    if (isFilled(iconOf(a)) || isFilled(iconOf(b))) {
      return {
        pair,
        stats: `${libName(a)} → ${libName(b)}`,
        verdict: "filled surface, region morph",
      };
    }
    const plan = buildPlan(samplesOf(a), samplesOf(b));
    const items = plan.items;
    const maxRes = Math.max(...items.map((it) => it.res));
    const maxTh = Math.max(...items.map((it) => Math.abs(it.theta)));
    const shown = items.slice(0, 4);
    const more = items.length > 4 ? ` +${items.length - 4}` : "";
    let verdict: string;
    if (maxRes < 0.03 && maxTh > 0.09) verdict = "pure rotation, emergent";
    else if (maxRes < 0.03) verdict = "pure similarity";
    else if (maxRes < 0.3) verdict = "rotation + residual";
    else verdict = "coordinate morph, aligned frame";
    if (samplesOf(a).length !== samplesOf(b).length) verdict += " · cell division";
    return {
      pair,
      stats: `θ [${shown.map((it) => fmtDeg(it.theta)).join(" ")}${more}]  res ${maxRes.toFixed(3)}`,
      verdict,
    };
  }, [prevId, curId]);
}

/* Grid and chip thumbnails: the upstream body as is, on its own grid. */
function Thumb({ entry, size }: { entry: IconEntry; size: number }) {
  return (
    <svg
      viewBox={entry.viewBox}
      width={size}
      height={size}
      aria-hidden="true"
      // biome-ignore lint/security/noDangerouslySetInnerHtml: vendored Iconify bodies (lib/icon-sets)
      dangerouslySetInnerHTML={{ __html: entry.body }}
    />
  );
}

function Segmented<T extends string | number>({
  options,
  value,
  onChange,
  label,
  size = "sm",
}: {
  options: readonly { v: T; label: string }[] | readonly T[];
  value: T;
  onChange: (v: T) => void;
  label: string;
  size?: "sm" | "md";
}) {
  const opts = options.map((o) =>
    typeof o === "object" ? o : { v: o, label: String(o) },
  ) as { v: T; label: string }[];
  return (
    <div className="flex items-center gap-2.5">
      {size === "sm" && <span className="font-mono text-[11px] text-mute">{label}</span>}
      <div
        role="group"
        aria-label={label}
        className="flex overflow-hidden rounded-md border border-hairline bg-canvas"
      >
        {opts.map((o) => (
          <button
            key={String(o.v)}
            type="button"
            aria-pressed={value === o.v}
            onClick={() => onChange(o.v)}
            className={`${size === "md" ? "h-9 px-3" : "h-7 px-2.5"} text-[13px] transition-colors ${
              value === o.v
                ? "bg-ink text-canvas"
                : "text-body hover:bg-canvas-soft-2 hover:text-ink"
            }`}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

export function Studio() {
  const [seq, setSeq] = useState<string[]>(DEFAULT_SEQ);
  const [curId, setCurId] = useState(DEFAULT_SEQ[0]);
  const [prevId, setPrevId] = useState<string | null>(null);
  const [lib, setLib] = useState("lucide");
  const [style, setStyle] = useState<Style>("outline");
  const [q, setQ] = useState("");
  const [spring, setSpring] = useState<SpringPreset>("snappy");
  const [speed, setSpeed] = useState<number>(1);
  const [strokeWidth, setStrokeWidth] = useState<number>(2);
  const [playing, setPlaying] = useState(true);
  const [t, setT] = useState(1);
  const [, setLoads] = useState(0); // bumped when a set arrives

  const cur = byId.get(curId) ?? (byId.get(DEFAULT_SEQ[0]) as IconEntry);
  const readout = useReadout(prevId, curId);
  const motion = springAt(spring, speed);

  /* The libraries on screen for the current style, and their set keys. */
  const keys = useMemo(
    () =>
      (lib === "all" ? LIBRARIES.map((l) => l.id) : [lib])
        .filter((id) => libraryById.get(id)?.styles.includes(style))
        .map((id) => setKey(id, style)),
    [lib, style],
  );

  useEffect(() => {
    let live = true;
    for (const k of keys) {
      if (!loadedSet(k)) loadSet(k).then(() => live && setLoads((n) => n + 1));
    }
    return () => {
      live = false;
    };
  }, [keys]);

  /* The stage consumes the vanilla driver directly: morphTo for taps and
     autoplay, set + seek for the scrubber (the same primitives the generated
     vanilla snippet uses). React renders the initial d once; from then on the
     driver owns the attribute. */
  const pathRef = useRef<SVGPathElement>(null);
  const morphRef = useRef<Morph | null>(null);
  const scrubbing = useRef(false);
  const chipsRef = useRef<HTMLDivElement>(null);

  /* Keep the active chip in view inside the sideways-scrolling set row
     (scrolls the row only, never the page). */
  useEffect(() => {
    const row = chipsRef.current;
    // The chip's wrapper span: its offsetParent is the (relative) row itself.
    const chip = row?.querySelector<HTMLElement>('[aria-current="true"]')?.parentElement;
    if (!row || !chip) return;
    const left = chip.offsetLeft;
    if (left < row.scrollLeft || left + chip.offsetWidth > row.scrollLeft + row.clientWidth)
      row.scrollTo({ left: left - row.clientWidth / 2 + chip.offsetWidth / 2, behavior: "smooth" });
  }, [curId]);
  const [initial] = useState(() => {
    const icon = iconOf(cur);
    return { icon, d: canonicalD(icon), attrs: restAttrs(icon) };
  });

  useEffect(() => {
    const el = pathRef.current;
    if (!el) return;
    const m = createMorph(el, initial.icon);
    morphRef.current = m;
    return () => {
      m.destroy();
      morphRef.current = null;
    };
  }, [initial]);

  const goTo = (id: string) => {
    if (id === curId) return;
    const e = byId.get(id);
    if (!e) return;
    setPrevId(curId);
    setCurId(id);
    setT(1);
    scrubbing.current = false;
    morphRef.current?.morphTo(iconOf(e), motion);
  };

  const advance = () => {
    if (seq.length < 2) return;
    const i = seq.indexOf(curId);
    goTo(seq[(i + 1 + seq.length) % seq.length]);
  };

  // Re-armed on every tick (curId changes), so it behaves as a delay chain.
  // The pause between morphs follows the speed, so slow motion has time to land.
  useEffect(() => {
    if (!playing || seq.length < 2) return;
    const timer = setInterval(() => {
      const i = seq.indexOf(curId);
      const next = byId.get(seq[(i + 1 + seq.length) % seq.length]);
      if (!next) return;
      setPrevId(curId);
      setCurId(next.id);
      setT(1);
      scrubbing.current = false;
      morphRef.current?.morphTo(iconOf(next), springAt(spring, speed));
    }, AUTOPLAY_MS / speed);
    return () => clearInterval(timer);
  }, [playing, seq, curId, spring, speed]);

  /* Scrub: freeze the prev → cur pair at t. On the first input the driver is
     re-based on prev (playground pattern); a later tap takes off from the
     frozen shape with velocity intact. */
  const scrub = (v: number) => {
    setT(v);
    if (!prevId) return;
    const a = byId.get(prevId);
    const b = byId.get(curId);
    const m = morphRef.current;
    if (!a || !b || !m) return;
    setPlaying(false);
    if (!scrubbing.current) {
      m.set(iconOf(a));
      scrubbing.current = true;
    }
    m.seek(iconOf(b), v);
  };

  const pick = (id: string) => {
    if (!seq.includes(id)) setSeq((s) => [...s, id]);
    goTo(id);
  };

  const remove = (id: string) => {
    if (seq.length <= 1) return;
    const next = seq.filter((x) => x !== id);
    setSeq(next);
    if (id === curId) goTo(next[Math.min(seq.indexOf(id), next.length - 1)]);
  };

  const changeStyle = (s: Style) => {
    setStyle(s);
    if (lib !== "all" && !libraryById.get(lib)?.styles.includes(s)) setLib("all");
  };

  const sets = keys.map((k) => loadedSet(k));
  const loading = sets.some((s) => !s);
  const query = q.trim().toLowerCase();
  const shown = sets
    .flatMap((s) => s ?? [])
    .filter((e) => !query || e.label.includes(query) || e.name.includes(query));

  const entries = seq
    .map((id) => byId.get(id))
    .filter((e): e is IconEntry => e !== undefined);

  return (
    <section aria-label="Morph studio" className="mx-auto w-full max-w-[1200px] px-6">
      <div className="overflow-visible rounded-xl border border-hairline bg-canvas shadow-card-lg">
        {/* Motion and drawing: every knob drives the stage. */}
        <div className="flex flex-wrap items-center gap-x-8 gap-y-3 rounded-t-xl border-b border-hairline bg-canvas-soft px-6 py-3">
          <Segmented
            label="spring"
            options={SPRINGS.map((s) => ({ v: s, label: s }))}
            value={spring}
            onChange={setSpring}
          />
          <Segmented
            label="speed"
            options={SPEEDS.map((s) => ({ v: s, label: `${s}×` }))}
            value={speed}
            onChange={setSpeed}
          />
          <Segmented label="stroke" options={STROKES} value={strokeWidth} onChange={setStrokeWidth} />
        </div>

        <div className="grid grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          {/* Stage: the morph itself, over the page's single mesh gradient. */}
          <div className="relative flex flex-col items-center justify-center gap-6 border-b border-hairline p-8 lg:border-b-0 lg:border-r">
            <div aria-hidden="true" className="mesh pointer-events-none absolute inset-10" />
            <button
              type="button"
              onClick={() => advance()}
              aria-label="Morph to the next icon in your set"
              title="Morph to the next icon"
              className="relative rounded-xl p-4 text-ink transition-transform active:scale-[0.97]"
            >
              <svg
                viewBox="0 0 24 24"
                width={144}
                height={144}
                fill="none"
                stroke="currentColor"
                strokeWidth={strokeWidth}
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path ref={pathRef} d={initial.d} {...initial.attrs} suppressHydrationWarning />
              </svg>
            </button>
            <div className="relative flex min-h-12 flex-col items-center gap-0.5 text-center font-mono text-[11px] leading-4">
              {readout ? (
                <>
                  <span className="text-body">{readout.pair}</span>
                  <span className="text-mute">{readout.stats}</span>
                  <span className="text-mute">{readout.verdict}</span>
                </>
              ) : (
                <span className="text-mute">pick icons to morph between them</span>
              )}
            </div>
            {/* Timeline: play/pause the sequence, or drive the active pair by hand. */}
            <div className="relative flex w-full max-w-80 items-center gap-3">
              <button
                type="button"
                onClick={() => setPlaying((p) => !p)}
                disabled={seq.length < 2}
                aria-pressed={playing}
                aria-label={playing ? "Pause the sequence" : "Play the sequence"}
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-hairline bg-canvas text-body shadow-card transition-colors hover:bg-canvas-soft-2 hover:text-ink disabled:opacity-40"
              >
                <MorphIcon icon={playing ? Pause : Play} size={14} strokeWidth={2} />
              </button>
              <input
                type="range"
                min={0}
                max={1}
                step={0.001}
                value={t}
                disabled={!prevId}
                onChange={(e) => scrub(Number(e.target.value))}
                aria-label="Scrub the morph between the previous and current icon"
                className="scrub w-full"
              />
              <span className="w-12 shrink-0 text-right font-mono text-[11px] text-mute">
                t={t.toFixed(2)}
              </span>
            </div>
            {/* The set: tap to morph, x to drop. One row of fixed height that
                scrolls sideways, so a growing set never resizes the card. */}
            <div ref={chipsRef} className="icon-pane relative -mx-2 flex h-14 max-w-full items-center gap-2 overflow-x-auto px-2 [&>*:first-child]:ml-auto [&>*:last-child]:mr-auto">
              {entries.map((e) => (
                <span key={e.id} className="group relative shrink-0">
                  <button
                    type="button"
                    onClick={() => goTo(e.id)}
                    aria-label={`Morph to ${e.label} (${libName(e)})`}
                    title={`${e.name} · ${libName(e)}`}
                    aria-current={e.id === curId}
                    className={`flex h-10 w-10 items-center justify-center rounded-lg border transition-colors ${
                      e.id === curId
                        ? "border-ink text-ink"
                        : "border-hairline text-body hover:bg-canvas-soft-2 hover:text-ink"
                    }`}
                  >
                    <Thumb entry={e} size={18} />
                  </button>
                  {seq.length > 1 && (
                    <button
                      type="button"
                      onClick={() => remove(e.id)}
                      aria-label={`Remove ${e.label} from the set`}
                      className="absolute -right-1.5 -top-1.5 hidden h-4 w-4 items-center justify-center rounded-full bg-ink text-[9px] leading-none text-canvas group-focus-within:flex group-hover:flex"
                    >
                      ×
                    </button>
                  )}
                </span>
              ))}
            </div>
          </div>

          {/* Picker: library, style, search, grid. */}
          <div className="flex flex-col gap-4 p-6">
            <div className="flex flex-wrap items-center gap-3">
              <LibraryPicker value={lib} style={style} onChange={setLib} />
              <Segmented label="Icon style" size="md" options={STYLES} value={style} onChange={changeStyle} />
              <div className="relative min-w-40 flex-1">
                <svg
                  viewBox="0 0 24 24"
                  width={15}
                  height={15}
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                  className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-mute"
                >
                  <path d="m21 21-4.34-4.34" />
                  <circle cx="11" cy="11" r="8" />
                </svg>
                <input
                  type="search"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Search icons"
                  aria-label="Search icons"
                  className="h-9 w-full rounded-md border border-hairline bg-canvas pl-8 pr-3 text-sm text-ink outline-none placeholder:text-mute focus:border-ink"
                />
              </div>
            </div>
            {shown.length > 0 ? (
              <div className="icon-pane grid h-80 grid-cols-[repeat(auto-fill,minmax(2.75rem,1fr))] content-start gap-1 overflow-y-auto pr-1">
                {shown.map((e) => {
                  const added = seq.includes(e.id);
                  return (
                    <button
                      key={e.id}
                      type="button"
                      onClick={() => pick(e.id)}
                      title={`${e.name} · ${libName(e)}`}
                      aria-label={`Add ${e.label} (${libName(e)}, ${e.style})`}
                      aria-pressed={added}
                      className={`flex aspect-square items-center justify-center rounded-lg border transition-colors ${
                        added
                          ? "border-hairline bg-canvas-soft-2 text-ink"
                          : "border-transparent text-body hover:border-hairline hover:text-ink"
                      }`}
                    >
                      <Thumb entry={e} size={20} />
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="flex h-80 flex-col items-center justify-center gap-2 text-center">
                {loading ? (
                  <p className="text-sm text-mute">Loading icons…</p>
                ) : (
                  <>
                    <p className="text-sm text-body">
                      Nothing matches &ldquo;{q.trim()}&rdquo;.
                    </p>
                    <button
                      type="button"
                      onClick={() => setQ("")}
                      className="text-sm text-link hover:underline"
                    >
                      Clear the search
                    </button>
                  </>
                )}
              </div>
            )}
            <p className="text-[13px] text-mute">
              Click an icon to add it to your set. Any icon morphs into any other: across
              libraries, grids, and outline to fill.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
