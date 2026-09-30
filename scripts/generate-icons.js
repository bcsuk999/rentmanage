'use strict';

/**
 * Generates the PWA icon set (no image libraries required).
 * Run with: node scripts/generate-icons.js
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT_DIR = path.join(__dirname, '..', 'src', 'public', 'icons');

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeAndData = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData), 0);
  return Buffer.concat([length, typeAndData, crc]);
}

/** Encode RGBA pixel data as a PNG buffer. */
function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // colour type RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const inside = {
  roundRect(x, y, w, h, r) {
    return inside.roundRectAt(x, y, 0, 0, w, h, r);
  },
  roundRectAt(x, y, x0, y0, w, h, r) {
    const lx = x - x0;
    const ly = y - y0;
    if (lx < 0 || ly < 0 || lx > w || ly > h) return false;
    const cx = Math.min(Math.max(lx, r), w - r);
    const cy = Math.min(Math.max(ly, r), h - r);
    return (lx - cx) ** 2 + (ly - cy) ** 2 <= r * r;
  },
  rect(x, y, w, h) {
    return x >= 0 && y >= 0 && x <= w && y <= h;
  },
  triangle(px, py, ax, ay, bx, by, cx, cy) {
    const d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    const d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    const d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  },
};

/**
 * Draws a roof + door mark on a rounded tile.
 * `padding` shrinks the artwork (used for the maskable safe zone).
 */
function drawIcon(size, { padding = 0.16, background = [16, 24, 40, 255], mark = [255, 255, 255, 255] } = {}) {
  const rgba = Buffer.alloc(size * size * 4);
  const S = size;
  const pad = S * padding;
  const artW = S - pad * 2;
  const artH = S - pad * 2;
  const roofTop = pad + artH * 0.08;
  const roofBottom = pad + artH * 0.46;
  const bodyTop = roofBottom - artH * 0.04;
  const bodyBottom = pad + artH * 0.92;
  const doorLeft = pad + artW * 0.38;
  const doorRight = pad + artW * 0.62;
  const doorTop = bodyTop + artH * 0.26;
  const radius = S * 0.22;
  const samples = 4;
  const stats = { roof: 0, body: 0, door: 0, window: 0, bg: 0 };

  for (let y = 0; y < S; y += 1) {
    for (let x = 0; x < S; x += 1) {
      let bgHits = 0;
      let roofHits = 0;
      let bodyHits = 0;
      let doorHits = 0;
      let windowHits = 0;
      for (let sy = 0; sy < samples; sy += 1) {
        for (let sx = 0; sx < samples; sx += 1) {
          const px = x + (sx + 0.5) / samples;
          const py = y + (sy + 0.5) / samples;
          if (!inside.roundRect(px, py, S, S, radius)) continue;
          bgHits += 1;
          const inRoof = inside.triangle(
            px, py,
            pad + artW * 0.5, roofTop,
            pad + artW * 0.06, roofBottom,
            pad + artW * 0.94, roofBottom
          );
          const inBody =
            inside.roundRectAt(
              px, py,
              pad + artW * 0.14, bodyTop,
              artW * 0.72, bodyBottom - bodyTop,
              artW * 0.05
            );
          const inDoor = inside.rect(px - doorLeft, py - doorTop, doorRight - doorLeft, bodyBottom - doorTop);
          const inWindow = inside.rect(
            px - (pad + artW * 0.6),
            py - (bodyTop + artH * 0.05),
            artW * 0.12,
            artH * 0.12
          );
          if (inRoof) roofHits += 1;
          else if (inBody) bodyHits += 1;
          if (inBody && inDoor) doorHits += 1;
          if (inBody && inWindow) windowHits += 1;
        }
      }
      const total = samples * samples;
      const i = (y * S + x) * 4;
      if (bgHits === 0) continue;
      stats.bg += 1;
      stats.roof += roofHits > 0 ? 1 : 0;
      stats.body += bodyHits > 0 ? 1 : 0;
      stats.door += doorHits > 0 ? 1 : 0;
      stats.window += windowHits > 0 ? 1 : 0;
      const bgAlpha = bgHits / total;
      let r = background[0];
      let g = background[1];
      let b = background[2];
      const overlay = roofHits + bodyHits;
      if (overlay > 0) {
        const alpha = Math.min(1, overlay / total);
        r = Math.round(r * (1 - alpha) + mark[0] * alpha);
        g = Math.round(g * (1 - alpha) + mark[1] * alpha);
        b = Math.round(b * (1 - alpha) + mark[2] * alpha);
      }
      if (doorHits > 0) {
        const alpha = Math.min(1, doorHits / total);
        r = Math.round(r * (1 - alpha) + background[0] * alpha);
        g = Math.round(g * (1 - alpha) + background[1] * alpha);
        b = Math.round(b * (1 - alpha) + background[2] * alpha);
      }
      if (windowHits > 0) {
        const alpha = Math.min(1, windowHits / total);
        r = Math.round(r * (1 - alpha) + [255, 190, 60][0] * alpha);
        g = Math.round(g * (1 - alpha) + [255, 190, 60][1] * alpha);
        b = Math.round(b * (1 - alpha) + [255, 190, 60][2] * alpha);
      }
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = Math.round(255 * bgAlpha);
    }
  }
  const pct = (n) => `${Math.round((n / (S * S)) * 100)}%`;
  console.log(
    `  coverage: bg ${pct(stats.bg)} roof ${pct(stats.roof)} body ${pct(stats.body)} door ${pct(stats.door)} window ${pct(stats.window)}`
  );
  return encodePng(S, S, rgba);
}

fs.mkdirSync(OUT_DIR, { recursive: true });

const targets = [
  { file: 'icon-192.png', size: 192, opts: {} },
  { file: 'icon-512.png', size: 512, opts: {} },
  { file: 'maskable-512.png', size: 512, opts: { padding: 0.28 } },
  { file: 'apple-touch-icon.png', size: 180, opts: { padding: 0.12, background: [16, 24, 40, 255] } },
];

for (const target of targets) {
  fs.writeFileSync(path.join(OUT_DIR, target.file), drawIcon(target.size, target.opts));
  console.log(`wrote ${target.file} (${target.size}x${target.size})`);
}
