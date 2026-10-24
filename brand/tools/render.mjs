// Rasterises the generated SVGs with Chromium (Playwright). Run after gen.py, from the repo root:
//   NODE_PATH=$(npm root -g) node brand/tools/render.mjs
import { createRequire } from 'node:module'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

// Playwright is resolved like a CommonJS require, so a global install (NODE_PATH) works too.
const { chromium } = createRequire(import.meta.url)('playwright')
const BRAND = join(dirname(fileURLToPath(import.meta.url)), '..')
const jobs = [
  // [source svg, output png, width, height, transparent]
  ['app-icon/flat/AppIcon-default.svg', 'ios/AppIcon.appiconset/AppIcon-1024.png', 1024, 1024, false],
  ['app-icon/flat/AppIcon-dark.svg', 'ios/AppIcon.appiconset/AppIcon-1024-dark.png', 1024, 1024, true],
  ['app-icon/flat/AppIcon-tinted.svg', 'ios/AppIcon.appiconset/AppIcon-1024-tinted.png', 1024, 1024, false],
  ['logo/mark.svg', 'logo/png/mark-512.png', 512, 512, true],
  ['logo/lockup-on-dark.svg', 'logo/png/lockup-on-dark.png', null, 248, true],
  ['splash/closed.svg', 'splash/png/closed.png', 393 * 3, 852 * 3, false],
  ['splash/flat.svg', 'splash/png/flat.png', 1024 * 2, 820 * 2, false],
  ['splash/book.svg', 'splash/png/book.png', 1024 * 2, 820 * 2, false],
  ['splash/tabletop.svg', 'splash/png/tabletop.png', 820 * 2, 1024 * 2, false],
  ['cover/bug-rest.svg', 'cover/png/bug-rest@3x.png', null, 120, true],
  ['cover/bug-open.svg', 'cover/png/bug-open@3x.png', null, 120, true],
]

const browser = await chromium.launch()
const page = await browser.newPage()
for (const [src, out, w, h, transparent] of jobs) {
  const svg = readFileSync(join(BRAND, src), 'utf8')
  const [, sw, sh] = svg.match(/width="([\d.]+)" height="([\d.]+)"/)
  const W = w ?? Math.round((h / sh) * sw)
  await page.setViewportSize({ width: W, height: h })
  await page.setContent(`<html><body style="margin:0;background:transparent">
    <img src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" width="${W}" height="${h}" style="display:block"></body></html>`)
  await page.waitForFunction(() => document.images[0].complete)
  mkdirSync(dirname(join(BRAND, out)), { recursive: true })
  await page.screenshot({ path: join(BRAND, out), omitBackground: transparent })
  console.log(out)
}
await browser.close()
