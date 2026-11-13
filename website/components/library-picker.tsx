"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { SET_SIZES } from "@/lib/icon-sets/sizes";
import { LIBRARY_LOGOS } from "@/lib/library-logos";
import { LIBRARIES, type Style, setKey } from "@/lib/studio-icons";

/* Combobox for the studio's library: a trigger with the current library's
   mark, and a popover with a filter field over the list (WAI-ARIA combobox +
   listbox: arrows move, Enter picks, Escape closes). "all" mixes every
   library that draws the current style. */

export function LibraryLogo({ lib, size = 16 }: { lib: string; size?: number }) {
  const logo = LIBRARY_LOGOS[lib];
  if (!logo) {
    // "All": a 2×2 grid, the same weight as the marks.
    return (
      <svg viewBox="0 0 24 24" width={size} height={size} fill="currentColor" aria-hidden="true">
        <rect x="3" y="3" width="8" height="8" rx="2" />
        <rect x="13" y="3" width="8" height="8" rx="2" />
        <rect x="3" y="13" width="8" height="8" rx="2" />
        <rect x="13" y="13" width="8" height="8" rx="2" />
      </svg>
    );
  }
  return (
    <svg
      viewBox={logo[0]}
      width={size}
      height={size}
      aria-hidden="true"
      // biome-ignore lint/security/noDangerouslySetInnerHtml: vendored marks (lib/library-logos.ts)
      dangerouslySetInnerHTML={{ __html: logo[1] }}
    />
  );
}

interface Option {
  id: string;
  label: string;
  count: number;
  disabled: boolean;
}

export function LibraryPicker({
  value,
  style,
  onChange,
}: {
  value: string;
  style: Style;
  onChange: (lib: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [active, setActive] = useState(0);
  const root = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const listId = useId();

  const options = useMemo<Option[]>(() => {
    const libs = LIBRARIES.map((l) => ({
      id: l.id,
      label: l.label,
      count: SET_SIZES[setKey(l.id, style)] ?? 0,
      disabled: !l.styles.includes(style),
    }));
    const all = libs.filter((l) => !l.disabled).reduce((n, l) => n + l.count, 0);
    return [{ id: "all", label: "All libraries", count: all, disabled: false }, ...libs];
  }, [style]);

  const query = q.trim().toLowerCase();
  const shown = options.filter((o) => !query || o.label.toLowerCase().includes(query));
  const current = options.find((o) => o.id === value) ?? options[0];

  useEffect(() => {
    if (!open) return;
    const close = (e: PointerEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);

  const show = () => {
    setQ("");
    setActive(Math.max(0, options.findIndex((o) => o.id === value)));
    setOpen(true);
    requestAnimationFrame(() => input.current?.focus());
  };

  const choose = (o: Option | undefined) => {
    if (!o || o.disabled) return;
    onChange(o.id);
    setOpen(false);
  };

  const step = (dir: 1 | -1) => {
    if (!shown.length) return;
    let i = active;
    for (let n = 0; n < shown.length; n++) {
      i = (i + dir + shown.length) % shown.length;
      if (!shown[i].disabled) break;
    }
    setActive(i);
    document.getElementById(`${listId}-${i}`)?.scrollIntoView({ block: "nearest" });
  };

  return (
    <div ref={root} className="relative">
      <button
        type="button"
        onClick={() => (open ? setOpen(false) : show())}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`Icon library: ${current.label}`}
        className="flex h-9 w-56 items-center gap-2 rounded-md border border-hairline bg-canvas px-2.5 text-[13px] text-ink transition-colors hover:bg-canvas-soft-2"
      >
        <span className="text-ink">
          <LibraryLogo lib={current.id} />
        </span>
        <span className="min-w-0 flex-1 truncate text-left">{current.label}</span>
        <span className="font-mono text-[11px] text-mute">{current.count}</span>
        <svg
          viewBox="0 0 24 24"
          width={14}
          height={14}
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
          className="text-mute"
        >
          <path d="m7 15 5 5 5-5M7 9l5-5 5 5" />
        </svg>
      </button>

      {open && (
        <div className="absolute left-0 top-10 z-20 w-64 overflow-hidden rounded-lg border border-hairline bg-canvas shadow-card-lg">
          <div className="border-b border-hairline p-1.5">
            <input
              ref={input}
              role="combobox"
              aria-expanded="true"
              aria-controls={listId}
              aria-activedescendant={shown[active] ? `${listId}-${active}` : undefined}
              aria-label="Filter libraries"
              placeholder="Find a library"
              value={q}
              onChange={(e) => {
                setQ(e.target.value);
                setActive(0);
              }}
              onKeyDown={(e) => {
                if (e.key === "ArrowDown") {
                  e.preventDefault();
                  step(1);
                } else if (e.key === "ArrowUp") {
                  e.preventDefault();
                  step(-1);
                } else if (e.key === "Enter") {
                  e.preventDefault();
                  choose(shown[active]);
                } else if (e.key === "Escape") {
                  setOpen(false);
                }
              }}
              className="h-8 w-full rounded-md bg-canvas-soft px-2.5 text-[13px] text-ink outline-none placeholder:text-mute"
            />
          </div>
          <ul id={listId} role="listbox" aria-label="Icon libraries" className="max-h-72 overflow-y-auto p-1">
            {shown.map((o, i) => (
              <li
                key={o.id}
                id={`${listId}-${i}`}
                role="option"
                aria-selected={o.id === value}
                aria-disabled={o.disabled}
                onPointerEnter={() => !o.disabled && setActive(i)}
                onClick={() => choose(o)}
                onKeyDown={() => {}}
                className={`flex h-9 items-center gap-2.5 rounded-md px-2 text-[13px] ${
                  o.disabled
                    ? "cursor-not-allowed text-mute opacity-50"
                    : i === active
                      ? "cursor-pointer bg-canvas-soft-2 text-ink"
                      : "cursor-pointer text-body"
                }`}
              >
                <LibraryLogo lib={o.id} />
                <span className="min-w-0 flex-1 truncate">{o.label}</span>
                <span className="font-mono text-[11px] text-mute">
                  {o.disabled ? "outline only" : o.count}
                </span>
                <svg
                  viewBox="0 0 24 24"
                  width={14}
                  height={14}
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                  className={o.id === value ? "text-ink" : "invisible"}
                >
                  <path d="M20 6 9 17l-5-5" />
                </svg>
              </li>
            ))}
            {shown.length === 0 && (
              <li className="px-2 py-3 text-center text-[13px] text-mute">No library matches.</li>
            )}
          </ul>
        </div>
      )}
    </div>
  );
}
