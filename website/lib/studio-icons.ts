/* Icon registry for the studio: ten libraries, outline and fill, each set a
   generated module in lib/icon-sets/ (scripts/extract-studio-sets.mjs) that
   is downloaded only when selected. Lucide outline is the one bundled
   statically (the default library), plus the few entries of the default
   sequence (icon-sets/defaults.ts), so autoplay and SSR need no chunk.

   Entries keep the Iconify body verbatim: thumbnails render it as is, the
   stage converts it once with svgToIcon (any grid fits to 24, and the
   markup says whether the icon is stroked or filled). */

import type { IconInput } from "morphicons";
import { svgToIcon } from "morphicons/adapters";
import { DEFAULT_ENTRIES } from "./icon-sets/defaults";
import lucideOutline from "./icon-sets/lucide-outline";

/** label → [upstream name, width, height, Iconify body]. */
export type SetData = Record<string, readonly [string, number, number, string]>;

export type Style = "outline" | "fill";

export interface Library {
  id: string;
  label: string;
  styles: readonly Style[];
}

export const LIBRARIES: readonly Library[] = [
  { id: "lucide", label: "Lucide", styles: ["outline"] },
  { id: "heroicons", label: "Heroicons", styles: ["outline", "fill"] },
  { id: "tabler", label: "Tabler", styles: ["outline", "fill"] },
  { id: "ph", label: "Phosphor", styles: ["outline", "fill"] },
  { id: "material-symbols", label: "Material Symbols", styles: ["outline", "fill"] },
  { id: "iconoir", label: "Iconoir", styles: ["outline", "fill"] },
  { id: "ri", label: "Remix Icon", styles: ["outline", "fill"] },
  { id: "mdi", label: "Material Design Icons", styles: ["outline", "fill"] },
  { id: "bi", label: "Bootstrap Icons", styles: ["outline", "fill"] },
  { id: "mingcute", label: "MingCute", styles: ["outline", "fill"] },
];

export const libraryById = new Map(LIBRARIES.map((l) => [l.id, l]));

/* Explicit loaders so the bundler emits one chunk per set. */
const LOADERS: Record<string, () => Promise<{ default: SetData }>> = {
  "heroicons-outline": () => import("./icon-sets/heroicons-outline"),
  "heroicons-fill": () => import("./icon-sets/heroicons-fill"),
  "tabler-outline": () => import("./icon-sets/tabler-outline"),
  "tabler-fill": () => import("./icon-sets/tabler-fill"),
  "ph-outline": () => import("./icon-sets/ph-outline"),
  "ph-fill": () => import("./icon-sets/ph-fill"),
  "material-symbols-outline": () => import("./icon-sets/material-symbols-outline"),
  "material-symbols-fill": () => import("./icon-sets/material-symbols-fill"),
  "iconoir-outline": () => import("./icon-sets/iconoir-outline"),
  "iconoir-fill": () => import("./icon-sets/iconoir-fill"),
  "ri-outline": () => import("./icon-sets/ri-outline"),
  "ri-fill": () => import("./icon-sets/ri-fill"),
  "mdi-outline": () => import("./icon-sets/mdi-outline"),
  "mdi-fill": () => import("./icon-sets/mdi-fill"),
  "bi-outline": () => import("./icon-sets/bi-outline"),
  "bi-fill": () => import("./icon-sets/bi-fill"),
  "mingcute-outline": () => import("./icon-sets/mingcute-outline"),
  "mingcute-fill": () => import("./icon-sets/mingcute-fill"),
};

export interface IconEntry {
  /** `${lib}-${style}:${label}`, stable across sessions. */
  id: string;
  /** Universal, searchable name ("arrow-right"). */
  label: string;
  /** The library's own name for it ("arrow-forward"). */
  name: string;
  lib: string;
  style: Style;
  viewBox: string;
  body: string;
}

/* Every entry ever loaded, so a sequence keeps icons from sets that are no
   longer the one on screen. */
export const byId = new Map<string, IconEntry>();
const loaded = new Map<string, IconEntry[]>();

function entry(key: string, label: string, [name, w, h, body]: SetData[string]): IconEntry {
  const id = `${key}:${label}`;
  const known = byId.get(id); // a default entry keeps its identity
  if (known) return known;
  const [lib, style] = splitKey(key);
  const e: IconEntry = { id, label, name, lib, style, viewBox: `0 0 ${w} ${h}`, body };
  byId.set(id, e);
  return e;
}

function register(key: string, data: SetData): IconEntry[] {
  const list = Object.entries(data).map(([label, row]) => entry(key, label, row));
  loaded.set(key, list);
  return list;
}

const splitKey = (key: string): [string, Style] => {
  const i = key.lastIndexOf("-");
  return [key.slice(0, i), key.slice(i + 1) as Style];
};

/** The studio's default sequence, in order. */
export const DEFAULT_SEQ: string[] = DEFAULT_ENTRIES.map(([id, row]) => {
  const i = id.indexOf(":");
  return entry(id.slice(0, i), id.slice(i + 1), row).id;
});
register("lucide-outline", lucideOutline);

export const setKey = (lib: string, style: Style): string => `${lib}-${style}`;

/** The set if it is already here (synchronous: no flash on a re-select). */
export const loadedSet = (key: string): IconEntry[] | undefined => loaded.get(key);

const pending = new Map<string, Promise<IconEntry[]>>();
export function loadSet(key: string): Promise<IconEntry[]> {
  const ready = loaded.get(key);
  if (ready) return Promise.resolve(ready);
  let p = pending.get(key);
  if (!p) {
    const loader = LOADERS[key];
    if (!loader) return Promise.resolve([]);
    p = loader()
      .then((m) => register(key, m.default))
      .finally(() => pending.delete(key));
    pending.set(key, p);
  }
  return p;
}

/* Converted once per entry and kept by identity: the driver caches its plans
   per icon object, so the same pair never re-plans. */
const icons = new Map<string, IconInput>();
export function iconOf(e: IconEntry): IconInput {
  let icon = icons.get(e.id);
  if (!icon) {
    icon = svgToIcon(`<svg viewBox="${e.viewBox}">${e.body}</svg>`);
    icons.set(e.id, icon);
  }
  return icon;
}

/** True when the icon paints fill (the stage then flies regions). */
export function isFilled(icon: IconInput): boolean {
  if (typeof icon === "string") return false;
  return icon.some(([, a]) => a.fill !== undefined && String(a.fill).trim().toLowerCase() !== "none");
}
