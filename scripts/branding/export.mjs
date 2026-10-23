// Generates every Waffle icon, splash image and piece of store artwork from one
// geometry, so the per-size PNGs are always reproducible (docs/branding.md).
//
//   cd scripts/branding && npm ci && node export.mjs
//
// Text in the artwork is converted to outlines with opentype.js, so the SVG
// masters in docs/branding/ need no font to render. Generating them does: Inter
// (OFL-1.1, https://rsms.me/inter/) is read from BRAND_FONT_DIR, by default
// /usr/share/fonts/opentype/inter. PNGs are rasterised by Chromium through
// playwright-core; set CHROME_PATH if it cannot find a browser on its own.
//
// Never hand-edit an output: change the geometry or palette here and re-run.
// The in-app mark (lib/theme/waffle_mark.dart) draws the same grid; keep
// MARK_HEIGHTS in step with kWaffleMarkHeights there.

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import opentype from 'opentype.js';
import { chromium } from 'playwright-core';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const FONT_DIR = process.env.BRAND_FONT_DIR ?? '/usr/share/fonts/opentype/inter';

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/** Palette. Mirrored by BrandColors in lib/theme/brand_theme.dart. */
export const COLORS = {
  nightRaised: '#2B2340', // icon background, top
  nightDeep: '#15111D', // icon background, bottom; dark surfaces
  night: '#1E1829', // ink on light backgrounds
  grid: '#3A3052', // unlit waffle cells
  honeyLight: '#FFD480', // lit bars, top
  honey: '#F7A23B', // glow, dark-theme primary
  honeyDeep: '#F39231', // lit bars, bottom
  cream: '#FFF8EF', // light surfaces, wordmark on dark
  mist: '#CBC1D6', // secondary text on dark
  dusk: '#8F849E', // tertiary text on dark
};

/**
 * The mark: a 5×5 waffle whose columns light up to these heights, centred
 * vertically, so the lit "syrup" reads as a voice waveform.
 */
export const MARK_HEIGHTS = [3, 5, 3, 1, 3];
const ROWS = 5;
const CELL = 100;
const GAP = 26;
const CELL_RADIUS = 22;
/** Width and height of the mark in its own units. */
const MARK_SIZE = MARK_HEIGHTS.length * CELL + (MARK_HEIGHTS.length - 1) * GAP; // 604

/** Mark size as a share of a full-bleed icon. */
const MARK_IN_ICON = MARK_SIZE / 1024;

let uid = 0;
const nextId = (name) => `${name}${++uid}`;

/**
 * The mark at (x, y), [size] wide.
 *
 * `variant`: 'glow' (honey bars with a soft glow over dim cells), 'flat'
 * (honey bars, no glow) or 'mono' (white bars, translucent cells: Android's
 * themed icon only uses alpha).
 */
function mark(x, y, size, { variant = 'glow', grid = COLORS.grid } = {}) {
  const s = size / MARK_SIZE;
  const honey = nextId('honey');
  const glow = nextId('glow');
  let cells = '';
  let bars = '';
  MARK_HEIGHTS.forEach((height, col) => {
    const cx = col * (CELL + GAP);
    const top = Math.round((ROWS - height) / 2);
    for (let row = 0; row < ROWS; row++) {
      if (row >= top && row < top + height) continue;
      cells += `<rect x="${cx}" y="${row * (CELL + GAP)}" width="${CELL}" height="${CELL}" rx="${CELL_RADIUS}"/>`;
    }
    const barHeight = height * CELL + (height - 1) * GAP;
    bars += `<rect x="${cx}" y="${top * (CELL + GAP)}" width="${CELL}" height="${barHeight}" rx="${CELL / 2}"/>`;
  });
  const transform = `translate(${fmt(x)} ${fmt(y)}) scale(${fmt(s)})`;
  if (variant === 'mono') {
    return `<g transform="${transform}"><g fill="#fff" fill-opacity="0.38">${cells}</g><g fill="#fff">${bars}</g></g>`;
  }
  const defs = `<defs>
    <linearGradient id="${honey}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="${MARK_SIZE}">
      <stop offset="0" stop-color="${COLORS.honeyLight}"/><stop offset="1" stop-color="${COLORS.honeyDeep}"/>
    </linearGradient>
    <filter id="${glow}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="34"/></filter>
  </defs>`;
  const halo = variant === 'glow'
    ? `<g fill="${COLORS.honey}" opacity="0.55" filter="url(#${glow})">${bars}</g>`
    : '';
  return `<g transform="${transform}">${defs}<g fill="${grid}">${cells}</g>${halo}<g fill="url(#${honey})">${bars}</g></g>`;
}

/** The night background gradient, as a <defs> block plus its fill reference. */
function nightFill() {
  const id = nextId('night');
  return {
    defs: `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${COLORS.nightRaised}"/><stop offset="1" stop-color="${COLORS.nightDeep}"/>
    </linearGradient></defs>`,
    fill: `url(#${id})`,
  };
}

const svg = (w, h, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">\n${body}\n</svg>\n`;

const fmt = (n) => Number(n.toFixed(3)).toString();

/** Full-bleed square: iOS, maskable PWA, Play Store, apple-touch-icon. */
function iconFullBleed() {
  const bg = nightFill();
  const m = 1024 * MARK_IN_ICON;
  return svg(1024, 1024, `${bg.defs}<rect width="1024" height="1024" fill="${bg.fill}"/>${mark((1024 - m) / 2, (1024 - m) / 2, m)}`);
}

/**
 * Rounded tile with transparent corners: legacy Android launcher, PWA "any"
 * icons, favicon, splash images. [inset] is the margin around the tile.
 */
function iconRounded({ inset = 40, radius = 0.225, shadow = false } = {}) {
  const bg = nightFill();
  const side = 1024 - inset * 2;
  const m = side * MARK_IN_ICON;
  const sh = nextId('shadow');
  const shadowDefs = shadow
    ? `<defs><filter id="${sh}" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity="0.3"/></filter></defs>`
    : '';
  return svg(1024, 1024, `${bg.defs}${shadowDefs}
  <rect x="${inset}" y="${inset}" width="${side}" height="${side}" rx="${fmt(side * radius)}" fill="${bg.fill}"${shadow ? ` filter="url(#${sh})"` : ''}/>
  ${mark(inset + (side - m) / 2, inset + (side - m) / 2, m)}`);
}

/**
 * macOS: Apple's template puts an 824 px body with a soft shadow inside the
 * 1024 canvas, and the rounded rect is part of the artwork.
 */
const iconMacOS = () => iconRounded({ inset: 100, radius: 0.2245, shadow: true });

/**
 * Android adaptive icon layers: a 108 dp canvas whose middle 72 dp is visible.
 * The mark keeps the proportion it has in the full-bleed icon (59% of the
 * visible area), well inside the 66 dp safe circle.
 */
function adaptiveLayer(variant) {
  const m = 1024 * (72 / 108) * MARK_IN_ICON;
  return svg(1024, 1024, mark((1024 - m) / 2, (1024 - m) / 2, m, { variant }));
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

const fonts = {};
function font(file) {
  if (!fonts[file]) {
    const path = join(FONT_DIR, file);
    try {
      const buf = readFileSync(path);
      fonts[file] = opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
    } catch (e) {
      throw new Error(`Cannot read ${path} (${e.code ?? e.message}). Install Inter (https://rsms.me/inter/) or set BRAND_FONT_DIR.`);
    }
  }
  return fonts[file];
}

/**
 * [text] as outlined path data with its baseline at (x, y). `tracking` is in
 * ems; `anchor` is 'start', 'middle' or 'end'. Returns the path and its width.
 */
function textPath(text, { file, size, x = 0, y = 0, tracking = 0, anchor = 'start' }) {
  const f = font(file);
  const scale = size / f.unitsPerEm;
  const glyphs = f.stringToGlyphs(text);
  const advances = glyphs.map((g, i) => {
    const kern = i + 1 < glyphs.length ? f.getKerningValue(g, glyphs[i + 1]) : 0;
    return (g.advanceWidth + kern) * scale + (i + 1 < glyphs.length ? tracking * size : 0);
  });
  const width = advances.reduce((a, b) => a + b, 0);
  let pen = anchor === 'middle' ? x - width / 2 : anchor === 'end' ? x - width : x;
  let d = '';
  glyphs.forEach((g, i) => {
    d += g.getPath(pen, y, size).toPathData(2);
    pen += advances[i];
  });
  return { d, width };
}

const WORDMARK = { file: 'InterDisplay-ExtraBold.otf', tracking: -0.035 };
const BODY = { file: 'InterDisplay-Medium.otf', tracking: -0.005 };
const SMALL = { file: 'Inter-SemiBold.otf', tracking: 0.06 };

/** The wordmark is always lowercase "waffle"; prose and UI say "Waffle". */
function wordmarkPath(x, y, size, anchor = 'start') {
  return textPath('waffle', { ...WORDMARK, size, x, y, anchor });
}

/** Tile + wordmark lockup, centred on (cx, cy). Returns markup and width. */
function lockup(cx, cy, height, { onDark = true } = {}) {
  const fontSize = height * 0.86;
  const gap = height * 0.32;
  const word = wordmarkPath(0, 0, fontSize);
  const width = height + gap + word.width;
  const x0 = cx - width / 2;
  const bg = nightFill();
  const tile = `<rect x="${fmt(x0)}" y="${fmt(cy - height / 2)}" width="${fmt(height)}" height="${fmt(height)}" rx="${fmt(height * 0.225)}" fill="${bg.fill}"/>`
    + mark(x0 + height * (1 - MARK_IN_ICON) / 2, cy - height / 2 + height * (1 - MARK_IN_ICON) / 2, height * MARK_IN_ICON);
  // Optically centre lowercase text on the tile: baseline sits ~0.36 em
  // below the centre for Inter's x-height and ascenders.
  const text = wordmarkPath(x0 + height + gap, cy + fontSize * 0.36, fontSize);
  const ink = onDark ? COLORS.cream : COLORS.night;
  return { markup: `${bg.defs}${tile}<path d="${text.d}" fill="${ink}"/>`, width };
}

// ---------------------------------------------------------------------------
// Artwork
// ---------------------------------------------------------------------------

/** A faint waffle texture plus a honey glow, the background of all artwork. */
function backdrop(w, h, glowX, glowY, glowR) {
  const bg = nightFill();
  const pat = nextId('waffle');
  const glow = nextId('halo');
  return `${bg.defs}<defs>
    <pattern id="${pat}" width="64" height="64" patternUnits="userSpaceOnUse">
      <rect x="6" y="6" width="52" height="52" rx="12" fill="${COLORS.grid}" fill-opacity="0.32"/>
    </pattern>
    <radialGradient id="${glow}" cx="${glowX}" cy="${glowY}" r="${glowR}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${COLORS.honey}" stop-opacity="0.30"/><stop offset="1" stop-color="${COLORS.honey}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="${bg.fill}"/>
  <rect width="${w}" height="${h}" fill="url(#${pat})"/>
  <rect width="${w}" height="${h}" fill="url(#${glow})"/>`;
}

function centredText(text, style, cx, y, size, fill) {
  return `<path d="${textPath(text, { ...style, size, x: cx, y, anchor: 'middle' }).d}" fill="${fill}"/>`;
}

const TAGLINE = 'Reads aloud. Stays on your device.';
const FACTS = 'KOKORO 82M  ·  KITTEN TTS  ·  NO SERVER, NO ACCOUNT';

/** GitHub social preview (Settings → Social preview), 1280×640. */
function socialPreview() {
  const w = 1280;
  const h = 640;
  const lock = lockup(w / 2, 262, 150);
  return svg(w, h, `${backdrop(w, h, w / 2, 262, 520)}${lock.markup}
  ${centredText(TAGLINE, BODY, w / 2, 420, 46, COLORS.mist)}
  ${centredText(FACTS, SMALL, w / 2, 505, 20, COLORS.dusk)}`);
}

/** Google Play feature graphic, 1024×500 (content kept clear of the edges). */
function featureGraphic() {
  const w = 1024;
  const h = 500;
  const lock = lockup(w / 2, 205, 128);
  return svg(w, h, `${backdrop(w, h, w / 2, 205, 440)}${lock.markup}
  ${centredText(TAGLINE, BODY, w / 2, 340, 38, COLORS.mist)}`);
}

/** README banner, 1280×400 (rendered at 2× for high-density screens). */
function readmeHeader() {
  const w = 1280;
  const h = 400;
  const lock = lockup(w / 2, 168, 120);
  return svg(w, h, `<defs><clipPath id="banner"><rect width="${w}" height="${h}" rx="28"/></clipPath></defs>
  <g clip-path="url(#banner)">${backdrop(w, h, w / 2, 168, 460)}${lock.markup}
  ${centredText(TAGLINE, BODY, w / 2, 300, 38, COLORS.mist)}</g>`);
}

/** Wordmark alone, for places that already show the icon. */
function wordmark(onDark) {
  const size = 200;
  const word = wordmarkPath(0, 0, size);
  const w = Math.ceil(word.width) + 8;
  const h = 250;
  const path = wordmarkPath(4, 190, size).d;
  return svg(w, h, `<path d="${path}" fill="${onDark ? COLORS.cream : COLORS.night}"/>`);
}

function lockupFile(onDark) {
  const height = 200;
  const probe = lockup(0, 0, height, { onDark });
  const w = Math.ceil(probe.width) + 16;
  const h = height + 16;
  return svg(w, h, lockup(w / 2, h / 2, height, { onDark }).markup);
}

// ---------------------------------------------------------------------------
// Rasterising
// ---------------------------------------------------------------------------

const out = (p) => join(ROOT, p);

function write(path, contents) {
  mkdirSync(dirname(out(path)), { recursive: true });
  writeFileSync(out(path), contents);
}

let browser;
let page;

/**
 * Renders [svgText] to a [w]×[h] PNG at [path]. `opaque` drops the alpha
 * channel, which iOS requires of the 1024 App Store icon.
 */
async function png(svgText, path, w, h = w, { opaque = false } = {}) {
  await page.setViewportSize({ width: w, height: h });
  const sized = svgText.replace(/<svg ([^>]*?)width="[^"]*" height="[^"]*"/, `<svg $1width="${w}" height="${h}"`);
  await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${sized}</body></html>`);
  mkdirSync(dirname(out(path)), { recursive: true });
  const buffer = await page.screenshot({ omitBackground: !opaque, clip: { x: 0, y: 0, width: w, height: h }, scale: 'css' });
  writeFileSync(out(path), buffer);
  if (opaque) stripAlpha(out(path));
}

/** Like [png], at twice the pixel density, for artwork shown in documents. */
async function pngAt2x(svgText, path, w, h) {
  const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: w, height: h } });
  const p = await context.newPage();
  await p.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${svgText}</body></html>`);
  mkdirSync(dirname(out(path)), { recursive: true });
  writeFileSync(out(path), await p.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } }));
  await context.close();
}

/** Rewrites a PNG as 8-bit RGB. ImageMagick is the only extra tool needed. */
function stripAlpha(file) {
  execFileSync('convert', [file, '-background', COLORS.nightDeep, '-alpha', 'remove', '-alpha', 'off', '-define', 'png:color-type=2', file]);
}

/** Every size an Xcode asset catalogue lists, rendered from [svgText]. */
async function appiconset(dir, svgText, opts) {
  const contents = JSON.parse(readFileSync(out(join(dir, 'Contents.json')), 'utf8'));
  const done = new Set();
  for (const image of contents.images) {
    if (!image.filename || done.has(image.filename)) continue;
    done.add(image.filename);
    const px = Math.round(parseFloat(image.size) * parseInt(image.scale, 10));
    await png(svgText, join(dir, image.filename), px, px, opts);
  }
}

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function main() {
  // Masters: committed so the exports are reproducible and reviewable.
  const masters = {
    'icon.svg': iconFullBleed(),
    'icon-rounded.svg': iconRounded(),
    'icon-macos.svg': iconMacOS(),
    'adaptive-foreground.svg': adaptiveLayer('glow'),
    'adaptive-monochrome.svg': adaptiveLayer('mono'),
    'mark.svg': svg(MARK_SIZE, MARK_SIZE, mark(0, 0, MARK_SIZE, { variant: 'flat' })),
    'wordmark-on-dark.svg': wordmark(true),
    'wordmark-on-light.svg': wordmark(false),
    'lockup-on-dark.svg': lockupFile(true),
    'lockup-on-light.svg': lockupFile(false),
    'social-preview.svg': socialPreview(),
    'feature-graphic.svg': featureGraphic(),
    'readme-header.svg': readmeHeader(),
  };
  for (const [name, text] of Object.entries(masters)) write(`docs/branding/${name}`, text);

  browser = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  page = await browser.newPage();

  // Store and social artwork.
  await png(masters['icon.svg'], 'docs/branding/store/app-store-icon-1024.png', 1024, 1024, { opaque: true });
  await png(masters['icon.svg'], 'docs/branding/store/play-icon-512.png', 512);
  await png(masters['feature-graphic.svg'], 'docs/branding/store/play-feature-graphic-1024x500.png', 1024, 500, { opaque: true });
  await png(masters['social-preview.svg'], 'docs/branding/social-preview-1280x640.png', 1280, 640, { opaque: true });
  await pngAt2x(masters['readme-header.svg'], 'docs/branding/readme-header.png', 1280, 400);
  await pngAt2x(masters['lockup-on-dark.svg'], 'docs/branding/lockup-on-dark.png', ...svgSize(masters['lockup-on-dark.svg']));
  await pngAt2x(masters['lockup-on-light.svg'], 'docs/branding/lockup-on-light.png', ...svgSize(masters['lockup-on-light.svg']));

  // Android: legacy bitmap, adaptive layers, splash image.
  const res = 'android/app/src/main/res';
  for (const [bucket, d] of Object.entries(DENSITIES)) {
    await png(masters['icon-rounded.svg'], `${res}/mipmap-${bucket}/ic_launcher.png`, 48 * d);
    await png(masters['adaptive-foreground.svg'], `${res}/mipmap-${bucket}/ic_launcher_foreground.png`, 108 * d);
    await png(masters['adaptive-monochrome.svg'], `${res}/mipmap-${bucket}/ic_launcher_monochrome.png`, 108 * d);
    await png(masters['icon-rounded.svg'], `${res}/drawable-${bucket}/splash_icon.png`, 112 * d);
  }

  // iOS: icons (no alpha anywhere: the system masks them) and launch image.
  await appiconset('ios/Runner/Assets.xcassets/AppIcon.appiconset', masters['icon.svg'], { opaque: true });
  const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  const iosTile = iconRounded({ inset: 0, radius: 0.2237 });
  for (const [suffix, scale] of [['', 1], ['@2x', 2], ['@3x', 3]]) {
    await png(iosTile, `${launch}/LaunchImage${suffix}.png`, 112 * scale);
  }

  // macOS: the rounded rect and shadow are part of the artwork.
  await appiconset('macos/Runner/Assets.xcassets/AppIcon.appiconset', masters['icon-macos.svg']);

  // Web: "any" icons are the rounded tile; maskable ones are full bleed with the
  // mark inside the central 80%.
  await png(masters['icon-rounded.svg'], 'web/icons/Icon-192.png', 192);
  await png(masters['icon-rounded.svg'], 'web/icons/Icon-512.png', 512);
  await png(masters['icon.svg'], 'web/icons/Icon-maskable-192.png', 192, 192, { opaque: true });
  await png(masters['icon.svg'], 'web/icons/Icon-maskable-512.png', 512, 512, { opaque: true });
  await png(masters['icon.svg'], 'web/icons/apple-touch-icon.png', 180, 180, { opaque: true });
  await png(masters['icon-rounded.svg'], 'web/favicon.png', 32);
  write('web/favicon.svg', masters['icon-rounded.svg']);

  await browser.close();
}

function svgSize(text) {
  const m = text.match(/width="(\d+)" height="(\d+)"/);
  return [Number(m[1]), Number(m[2])];
}

await main();
