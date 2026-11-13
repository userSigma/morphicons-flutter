/* Extracts the studio's icon sets from the @iconify-json/* packages installed
   as devDeps of the LIBRARY repo (../node_modules: the same real upstream data
   the regions playground and bench:wide use; never hand-copied).

   One module per library and style (lib/icon-sets/<lib>-<style>.ts), so the
   studio downloads a set only when someone selects it. Each entry keeps the
   Iconify body verbatim plus its grid: thumbnails render the body as is, the
   stage feeds `<svg viewBox>body</svg>` to svgToIcon (which fits any grid to
   24 and reads stroke vs fill from the markup).

   Selection: a canon of the most used UI concepts (navigation, actions,
   media, communication, files, devices, commerce…), each with synonyms; per
   library a naming rule turns a synonym into its outline or fill name, and
   the first one that exists wins. A concept a library doesn't draw is simply
   absent from that set.

   Regenerate (from website/):  bun scripts/extract-studio-sets.mjs */

import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const ICONIFY = "../node_modules/@iconify-json";

/* [label, ...synonyms]. The label is what the search matches (with the
   library's own name), so it is the universal word. */
const CONCEPTS = [
  ["menu", "menu", "bars-3", "menu-2", "hamburger-menu", "list"],
  ["x", "x", "x-mark", "close", "xmark", "x-lg"],
  ["check", "check", "checkmark", "check-lg", "done"],
  ["plus", "plus", "add", "plus-lg"],
  ["minus", "minus", "remove", "subtract", "dash-lg", "dash"],
  ["arrow-right", "arrow-right", "arrow-forward", "arrow-right-line"],
  ["arrow-left", "arrow-left", "arrow-back"],
  ["arrow-up", "arrow-up", "arrow-upward"],
  ["arrow-down", "arrow-down", "arrow-downward"],
  ["chevron-right", "chevron-right", "nav-arrow-right", "caret-right", "right", "arrow-right-s"],
  ["chevron-left", "chevron-left", "nav-arrow-left", "caret-left", "left", "arrow-left-s"],
  ["chevron-up", "chevron-up", "nav-arrow-up", "caret-up", "up", "arrow-up-s"],
  ["chevron-down", "chevron-down", "nav-arrow-down", "caret-down", "down", "arrow-down-s", "expand-more"],
  ["home", "home", "house", "home-simple", "house-door"],
  ["search", "search", "magnifying-glass", "magnify", "zoom"],
  ["settings", "settings", "cog-6-tooth", "gear", "cog", "settings-3", "settings-4"],
  ["user", "user", "person", "account", "account-circle"],
  ["users", "users", "user-group", "people", "group", "account-group", "team"],
  ["bell", "bell", "notifications", "notification"],
  ["heart", "heart", "favorite"],
  ["star", "star", "grade"],
  ["bookmark", "bookmark", "bookmark-simple"],
  ["trash", "trash", "trash-2", "delete", "trash-can", "bin", "delete-bin", "trash3"],
  ["edit", "pencil", "edit", "pencil-square", "edit-pencil", "pen", "pencil-simple"],
  ["copy", "copy", "document-duplicate", "content-copy", "file-copy", "clipboard"],
  ["download", "download", "arrow-down-tray", "download-simple", "file-download"],
  ["upload", "upload", "arrow-up-tray", "upload-simple", "file-upload"],
  ["share", "share", "share-2", "share-android", "share-network", "share-variant"],
  ["link", "link", "link-simple", "link-45deg"],
  ["external-link", "external-link", "arrow-top-right-on-square", "open-in-new", "open-new-window", "box-arrow-up-right", "external-link-line"],
  ["filter", "filter", "funnel", "filter-list", "filter-alt", "filter-3"],
  ["sort", "sort", "arrows-up-down", "sort-ascending", "sort-up", "arrow-up-down"],
  ["refresh", "refresh", "refresh-cw", "arrow-path", "arrow-clockwise", "autorenew", "arrows-clockwise", "repeat"],
  ["more", "ellipsis", "ellipsis-horizontal", "more-horiz", "dots", "dots-three", "more", "three-dots", "more-horizontal"],
  ["more-vertical", "ellipsis-vertical", "more-vert", "dots-vertical", "dots-three-vertical", "three-dots-vertical", "more-2", "more-vertical"],
  ["eye", "eye", "visibility", "eye-empty"],
  ["eye-off", "eye-off", "eye-slash", "visibility-off", "eye-closed"],
  ["lock", "lock", "lock-closed", "lock-simple", "lock-2"],
  ["unlock", "lock-open", "unlock", "lock-simple-open", "lock-unlock", "lock-open-variant"],
  ["key", "key", "vpn-key"],
  ["shield", "shield", "shield-check", "security", "shield-checkmark"],
  ["login", "log-in", "login", "arrow-right-on-rectangle", "sign-in", "box-arrow-in-right"],
  ["logout", "log-out", "logout", "arrow-left-on-rectangle", "sign-out", "box-arrow-right"],
  ["mail", "mail", "envelope", "email", "envelope-simple"],
  ["send", "send", "paper-airplane", "send-diagonal", "paper-plane-tilt", "send-plane", "paper-plane-right"],
  ["chat", "message-circle", "chat-bubble-oval-left", "chat", "chat-circle", "chat-bubble", "message", "chat-1", "chat-3"],
  ["phone", "phone", "call", "telephone"],
  ["video", "video", "video-camera", "videocam", "camera-video", "film"],
  ["camera", "camera", "photo-camera"],
  ["image", "image", "photo", "media-image", "picture", "image-2"],
  ["mic", "mic", "microphone"],
  ["play", "play", "player-play", "play-arrow", "play-solid", "play-fill"],
  ["pause", "pause", "player-pause"],
  ["stop", "square", "stop", "player-stop"],
  ["skip-forward", "skip-forward", "forward", "player-skip-forward", "skip-next", "fast-forward"],
  ["skip-back", "skip-back", "backward", "player-skip-back", "skip-previous", "rewind"],
  ["volume", "volume-2", "volume", "speaker-wave", "volume-up", "sound-high", "speaker-high", "volume-high"],
  ["volume-x", "volume-x", "speaker-x-mark", "volume-off", "sound-off", "speaker-x", "volume-mute"],
  ["music", "music", "musical-note", "music-note", "music-double-note", "music-2"],
  ["headphones", "headphones", "headset"],
  ["calendar", "calendar", "calendar-days", "calendar-today", "calendar-blank", "calendar-3"],
  ["clock", "clock", "schedule", "time"],
  ["alarm", "alarm", "alarm-clock"],
  ["timer", "timer", "hourglass"],
  ["map-pin", "map-pin", "location-on", "pin", "map-marker", "geo-alt", "map-pin-2"],
  ["map", "map", "map-2"],
  ["globe", "globe", "globe-alt", "public", "language", "earth", "global"],
  ["compass", "compass", "explore"],
  ["navigation", "navigation", "navigation-2", "near-me", "navigation-arrow", "send-diagonal"],
  ["flag", "flag", "flag-2", "flag-banner"],
  ["sun", "sun", "light-mode", "sunny", "brightness-high"],
  ["moon", "moon", "dark-mode", "half-moon", "moon-clear"],
  ["cloud", "cloud"],
  ["umbrella", "umbrella"],
  ["snowflake", "snowflake", "ac-unit", "snow"],
  ["bolt", "zap", "bolt", "flash", "lightning", "flash-on", "lightning-charge"],
  ["fire", "flame", "fire", "local-fire-department", "fire-extinguisher"],
  ["droplet", "droplet", "drop", "water-drop", "droplet-half", "water"],
  ["leaf", "leaf", "eco", "plant", "seedling"],
  ["tree", "tree", "tree-pine", "park", "pine-tree"],
  ["wifi", "wifi", "wifi-high"],
  ["bluetooth", "bluetooth"],
  ["battery", "battery", "battery-full", "battery-high", "battery-4", "battery-100"],
  ["plug", "plug", "power-plug", "electrical-services", "plug-2"],
  ["power", "power", "power-settings-new", "power-off", "shut-down"],
  ["monitor", "monitor", "computer-desktop", "desktop", "laptop", "display", "computer"],
  ["smartphone", "smartphone", "device-phone-mobile", "phone-android", "device-mobile", "phone-iphone", "cellphone", "phone-portrait"],
  ["tablet", "tablet", "device-tablet", "tablet-android", "tablet-portrait"],
  ["printer", "printer", "print"],
  ["keyboard", "keyboard"],
  ["mouse", "mouse", "computer-mouse"],
  ["server", "server", "dns", "storage"],
  ["database", "database"],
  ["cpu", "cpu", "cpu-chip", "memory", "chip", "developer-board"],
  ["terminal", "terminal", "command-line", "terminal-window", "terminal-box", "console"],
  ["code", "code", "code-bracket", "code-brackets", "code-slash", "code-simple", "data-object"],
  ["git-branch", "git-branch", "source-branch", "fork", "git-fork", "call-split"],
  ["bug", "bug", "bug-ant", "bug-report", "bug-beetle"],
  ["file", "file", "document", "file-text", "description", "page", "file-earmark", "document-text"],
  ["folder", "folder", "folder-simple", "folder-2"],
  ["folder-open", "folder-open", "folder-simple-open"],
  ["archive", "archive", "archive-box", "inventory-2", "box"],
  ["clipboard", "clipboard", "clipboard-document", "content-paste", "assignment"],
  ["paperclip", "paperclip", "paper-clip", "attachment", "attach-file"],
  ["save", "save", "floppy-disk", "device-floppy", "floppy", "content-save"],
  ["inbox", "inbox", "inbox-stack", "inbox-simple"],
  ["tag", "tag", "label", "price-tag", "sell", "tag-simple"],
  ["cart", "shopping-cart", "cart", "shopping-cart-simple", "cart-2"],
  ["bag", "shopping-bag", "bag", "local-mall", "handbag", "shopping-bag-3"],
  ["credit-card", "credit-card", "credit-card-2", "payments", "bank-card"],
  ["wallet", "wallet", "account-balance-wallet"],
  ["gift", "gift", "redeem", "card-giftcard"],
  ["truck", "truck", "local-shipping", "delivery-truck"],
  ["package", "package", "box", "cube", "inventory-2", "archive-box"],
  ["store", "store", "storefront", "building-storefront", "shop", "store-2"],
  ["receipt", "receipt", "receipt-percent", "receipt-long"],
  ["chart", "chart-bar", "bar-chart", "chart-bar-square", "bar-chart-2", "chart", "leaderboard", "stats", "graph"],
  ["trending-up", "trending-up", "arrow-trending-up", "chart-line-up", "graph-up", "stock"],
  ["activity", "activity", "pulse", "monitor-heart", "heart-rate", "heartbeat"],
  ["layers", "layers", "square-3-stack-3d", "stack", "stack-2", "layers-2"],
  ["grid", "layout-grid", "grid", "squares-2x2", "view-grid", "dashboard", "grid-four", "grid-3x3-gap", "apps"],
  ["list", "list", "list-bullet", "format-list-bulleted", "list-dashes", "list-check", "list-ul"],
  ["layout", "layout", "layout-dashboard", "dashboard", "squares-plus", "view-quilt", "layout-2"],
  ["sliders", "sliders-horizontal", "adjustments-horizontal", "sliders", "tune", "faders", "settings-adjust", "equalizer"],
  ["info", "info", "information-circle", "info-circle", "information"],
  ["help", "circle-help", "question-mark-circle", "help", "question", "help-circle", "question-circle"],
  ["alert", "circle-alert", "exclamation-circle", "error", "alert-circle", "warning-circle", "exclamation-circle-fill"],
  ["warning", "triangle-alert", "exclamation-triangle", "warning", "alert-triangle", "alert"],
  ["check-circle", "circle-check", "check-circle", "check-badge", "checkmark-circle", "check-circle-fill"],
  ["x-circle", "circle-x", "x-circle", "cancel", "xmark-circle", "close-circle"],
  ["thumbs-up", "thumbs-up", "hand-thumb-up", "thumb-up", "like"],
  ["thumbs-down", "thumbs-down", "hand-thumb-down", "thumb-down", "dislike"],
  ["smile", "smile", "face-smile", "mood-smile", "emoji-emotions", "emoji", "emoji-smile", "sentiment-satisfied"],
  ["award", "award", "trophy", "medal", "military-tech", "emoji-events"],
  ["crown", "crown", "crown-simple"],
  ["sparkles", "sparkles", "sparkle", "auto-awesome", "stars", "magic-wand"],
  ["rocket", "rocket", "rocket-launch", "rocket-2"],
  ["lightbulb", "lightbulb", "light-bulb", "light-bulb-on", "lightbulb-on", "lamp"],
  ["palette", "palette", "color-palette", "swatch", "palette-2"],
  ["brush", "brush", "paint-brush", "paintbrush", "paint"],
  ["scissors", "scissors", "content-cut", "cut"],
  ["wrench", "wrench", "build", "tool", "tools", "hammer"],
  ["puzzle", "puzzle", "puzzle-piece", "extension"],
  ["book", "book", "book-open", "menu-book", "book-2", "book-open-variant"],
  ["graduation", "graduation-cap", "academic-cap", "school", "student"],
  ["briefcase", "briefcase", "work", "case", "suitcase"],
  ["building", "building", "building-office", "apartment", "domain", "buildings", "office-building"],
  ["car", "car", "directions-car", "car-side", "car-front"],
  ["plane", "plane", "airplane", "flight", "airplane-tilt"],
  ["coffee", "coffee", "local-cafe", "cafe", "cup-hot", "coffee-to-go"],
  ["pizza", "pizza", "local-pizza"],
  ["anchor", "anchor"],
  ["feather", "feather", "pen-nib"],
  ["diamond", "diamond", "gem"],
  ["circle", "circle"],
  ["square", "square"],
  ["triangle", "triangle"],
  ["hexagon", "hexagon"],
  ["ghost", "ghost"],
  ["cat", "cat", "pets", "paw", "paw-print"],
  ["dog", "dog"],
  ["fish", "fish", "set-meal"],
  ["skull", "skull", "skull-outline"],
  ["robot", "robot", "smart-toy", "robot-2"],
  ["planet", "planet", "globe-hemisphere-west", "public"],
  ["film", "film", "movie", "film-strip", "movie-2"],
  ["gamepad", "gamepad", "gamepad-2", "sports-esports", "game-controller", "controller", "puzzle-piece"],
  ["qr-code", "qr-code", "qr-code-2", "qrcode", "qr-code-line"],
  ["fingerprint", "fingerprint"],
  ["at", "at", "at-sign", "at-symbol", "alternate-email"],
  ["hash", "hash", "hashtag", "tag", "number"],
  ["zoom-in", "zoom-in", "magnifying-glass-plus", "magnify-plus"],
  ["maximize", "maximize", "maximize-2", "arrows-pointing-out", "fullscreen", "arrows-out", "expand"],
  ["minimize", "minimize", "minimize-2", "arrows-pointing-in", "fullscreen-exit", "arrows-in", "collapse"],
  ["undo", "undo", "undo-2", "arrow-uturn-left", "arrow-counter-clockwise", "arrow-go-back", "reply"],
  ["redo", "redo", "redo-2", "arrow-uturn-right", "arrow-clockwise", "arrow-go-forward"],
  ["shuffle", "shuffle", "arrows-shuffle", "shuffle-variant"],
  ["repeat", "repeat", "arrows-repeat", "repeat-2"],
];

/* Library → per-style naming rule (synonym → candidate names) + metadata.
   Iconify keeps each set's upstream license: MIT, ISC, Apache-2.0. */
const LIBS = {
  lucide: { label: "Lucide", outline: (n) => [n], fill: null },
  heroicons: { label: "Heroicons", outline: (n) => [n], fill: (n) => [`${n}-solid`] },
  tabler: { label: "Tabler", outline: (n) => [n], fill: (n) => [`${n}-filled`] },
  iconoir: { label: "Iconoir", outline: (n) => [n], fill: (n) => [`${n}-solid`] },
  ph: { label: "Phosphor", outline: (n) => [n], fill: (n) => [`${n}-fill`] },
  "material-symbols": {
    label: "Material Symbols",
    outline: (n) => [`${n}-outline`, `${n}-outline-rounded`, n],
    fill: (n) => [n, `${n}-rounded`],
  },
  ri: { label: "Remix Icon", outline: (n) => [`${n}-line`], fill: (n) => [`${n}-fill`] },
  mdi: { label: "Material Design Icons", outline: (n) => [`${n}-outline`], fill: (n) => [n] },
  bi: { label: "Bootstrap Icons", outline: (n) => [n], fill: (n) => [`${n}-fill`] },
  mingcute: { label: "MingCute", outline: (n) => [`${n}-line`], fill: (n) => [`${n}-fill`] },
};

/* The studio's default sequence (set key:label). These few entries are also
   written to lib/icon-sets/defaults.ts, bundled statically: the sequence
   autoplays on load and its first icon is server-rendered, before any set
   chunk arrives. */
const DEFAULTS = [
  "lucide-outline:moon",
  "lucide-outline:sun",
  "tabler-outline:play",
  "heroicons-fill:stop",
  "bi-outline:copy",
  "ph-fill:check-circle",
  "heroicons-fill:thumbs-up",
  "heroicons-outline:upload",
  "heroicons-outline:download",
  "heroicons-outline:lock",
  "heroicons-outline:shield",
];
const defaults = {};

const loadSet = (prefix) => {
  const json = JSON.parse(readFileSync(`${ICONIFY}/${prefix}/icons.json`, "utf8"));
  const info = JSON.parse(readFileSync(`${ICONIFY}/${prefix}/info.json`, "utf8"));
  /* Resolve one name (aliases included) to [body, width, height]. Aliases
     with transforms (rotate/flip) are skipped: they'd need a wrapper. */
  const resolve = (name) => {
    const ic = json.icons[name];
    if (ic) return [ic.body, ic.width ?? json.width ?? 16, ic.height ?? json.height ?? 16];
    const al = json.aliases?.[name];
    if (!al || al.rotate || al.hFlip || al.vFlip) return null;
    const r = resolve(al.parent);
    return r && [r[0], al.width ?? r[1], al.height ?? r[2]];
  };
  return { resolve, version: info.version, license: info.license?.spdx ?? "?" };
};

rmSync("lib/icon-sets", { recursive: true, force: true });
mkdirSync("lib/icon-sets", { recursive: true });

const report = [];
const sizes = {};
for (const [prefix, lib] of Object.entries(LIBS)) {
  const set = loadSet(prefix);
  for (const style of ["outline", "fill"]) {
    const rule = lib[style];
    if (!rule) continue;
    const used = new Set(); // one upstream icon appears once per set
    const rows = [];
    for (const [label, ...syn] of CONCEPTS) {
      if (rows.some((r) => r[0] === label)) continue; // duplicate concept label
      let hit = null;
      for (const s of syn) {
        for (const name of rule(s)) {
          if (used.has(name)) continue;
          const r = set.resolve(name);
          if (r) {
            hit = [name, ...r];
            break;
          }
        }
        if (hit) break;
      }
      if (!hit) continue;
      used.add(hit[0]);
      rows.push([label, ...hit]);
    }
    const key = `${prefix}-${style}`;
    for (const [label, name, b, w, h] of rows)
      if (DEFAULTS.includes(`${key}:${label}`)) defaults[`${key}:${label}`] = [name, w, h, b];
    const body = rows
      .map(([label, name, b, w, h]) => `  ${JSON.stringify(label)}: [${JSON.stringify(name)}, ${w}, ${h}, ${JSON.stringify(b)}],`)
      .join("\n");
    writeFileSync(
      `lib/icon-sets/${key}.ts`,
      `/* GENERATED by scripts/extract-studio-sets.mjs. Do not edit by hand.
   ${lib.label} v${set.version} (${style}), ${set.license}, via @iconify-json/${prefix}. */

import type { SetData } from "../studio-icons";

const data: SetData = {
${body}
};
export default data;
`,
    );
    sizes[key] = rows.length;
    report.push(`${key.padEnd(26)} ${rows.length}`);
  }
}
writeFileSync(
  "lib/icon-sets/sizes.ts",
  `/* GENERATED by scripts/extract-studio-sets.mjs. Icons per set, for the
   library picker (known before a set is downloaded). */

export const SET_SIZES: Record<string, number> = ${JSON.stringify(sizes, null, 2)};
`,
);
const missingDefaults = DEFAULTS.filter((id) => !defaults[id]);
if (missingDefaults.length) {
  console.error("Defaults not in any set:", missingDefaults.join(", "));
  process.exit(1);
}
writeFileSync(
  "lib/icon-sets/defaults.ts",
  `/* GENERATED by scripts/extract-studio-sets.mjs. The studio's default
   sequence, in order (set key:label → entry), bundled statically. */

export const DEFAULT_ENTRIES: [string, readonly [string, number, number, string]][] = [
${DEFAULTS.map((id) => `  [${JSON.stringify(id)}, ${JSON.stringify(defaults[id])}],`).join("\n")}
];
`,
);
console.log(report.join("\n"));
