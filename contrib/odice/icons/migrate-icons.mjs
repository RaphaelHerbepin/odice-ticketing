// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// Odice — migration du jeu d'icônes Zammad vers Lucide.
//
//   node contrib/odice/icons/migrate-icons.mjs --app=desktop           (essai à blanc)
//   node contrib/odice/icons/migrate-icons.mjs --app=all --write
//
// Le remplacement ne demande aucun changement de code : `initializeDesktopIcons.ts`
// charge `./assets/*.svg` par un glob et le nom d'icône est le nom de fichier.
// Il suffit donc d'écrire le SVG Lucide SOUS LE NOM DE FICHIER ZAMMAD.
//
// Deux invariants imposés par le pipeline de build (app/frontend/build/iconsPlugin.mjs) :
//
//   1. AUCUN width/height sur la racine <svg>. SVGO (`preset-default`) supprime
//      le viewBox dès que width et height sont présents et concordants ; or
//      `svgToSymbol()` ne conserve QUE le viewBox. Sans lui, le <symbol> perd
//      toute mise à l'échelle.
//
//   2. Les attributs de trait vont sur un <g> INTERNE, jamais sur la racine :
//      `svgToSymbol()` jette tous les attributs racine sauf viewBox. Sur le <g>,
//      `fill="none"` est un attribut de présentation porté par l'élément, il
//      l'emporte donc sur la valeur HÉRITÉE de la classe `fill-current` que
//      CommonIcon.vue pose sur le <svg> externe. Sans cela, chaque icône Lucide
//      s'afficherait en aplat noir.

import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import KEEP from './keep.mjs'
import MAP_DESKTOP from './map.desktop.mjs'
import MAP_MOBILE from './map.mobile.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../../..')

const APPS = {
  desktop: {
    assets: join(ROOT, 'app/frontend/apps/desktop/initializer/assets'),
    map: MAP_DESKTOP,
    overrides: join(HERE, 'overrides/desktop'),
  },
  mobile: {
    assets: join(ROOT, 'app/frontend/apps/mobile/initializer/assets'),
    map: MAP_MOBILE,
    overrides: join(HERE, 'overrides/mobile'),
  },
}

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v = true] = a.replace(/^--/, '').split('=')
    return [k, v]
  }),
)
const WRITE = Boolean(args.write)

const require_ = createRequire(import.meta.url)
let LUCIDE_DIR
try {
  LUCIDE_DIR = join(dirname(require_.resolve('lucide-static/package.json')), 'icons')
} catch {
  console.error('lucide-static introuvable. Lancez : pnpm add -D lucide-static')
  process.exit(1)
}
const LUCIDE = new Set(
  readdirSync(LUCIDE_DIR)
    .filter((f) => f.endsWith('.svg'))
    .map((f) => f.slice(0, -4)),
)

/** Transforme un SVG Lucide en source acceptable par `zammad-plugin-svgo`. */
const normalizeLucide = (svg, { filled = false, mirrored = false } = {}) => {
  const open = svg.match(/<svg\b[^>]*>/)
  if (!open) throw new Error('racine <svg> absente')
  const viewBox = (open[0].match(/viewBox="([^"]*)"/) || [])[1] || '0 0 24 24'
  const inner = svg
    .slice(open.index + open[0].length)
    .replace(/<\/svg>\s*$/, '')
    .trim()

  const attrs = [
    `fill="${filled ? 'currentColor' : 'none'}"`,
    'stroke="currentColor"',
    'stroke-linecap="round"',
    'stroke-linejoin="round"',
    mirrored ? 'transform="scale(-1 1) translate(-24 0)"' : null,
  ]
    .filter(Boolean)
    .join(' ')

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">\n<g ${attrs}>\n${inner}\n</g>\n</svg>\n`
}

/** Un SVG dessiné à la main passe la même hygiène : pas de width/height racine. */
const normalizeOverride = (svg) =>
  svg.replace(/<svg\b[^>]*>/, (tag) => tag.replace(/\s(width|height)="[^"]*"/g, ''))

const run = (appName) => {
  const { assets, map, overrides } = APPS[appName]
  const names = readdirSync(assets)
    .filter((f) => f.endsWith('.svg'))
    .map((f) => f.slice(0, -4))
    .sort()

  const report = { kept: [], overridden: [], mapped: [], unmapped: [], badLucide: [] }

  for (const name of names) {
    if (KEEP.has(name)) {
      report.kept.push(name)
      continue
    }

    const overridePath = join(overrides, `${name}.svg`)
    if (existsSync(overridePath)) {
      if (WRITE)
        writeFileSync(join(assets, `${name}.svg`), normalizeOverride(readFileSync(overridePath, 'utf8')))
      report.overridden.push(name)
      continue
    }

    // Correspondance implicite : si le nom Zammad existe tel quel chez Lucide,
    // inutile de le répéter dans la table.
    const entry = map[name] ?? (LUCIDE.has(name) ? name : undefined)
    if (!entry) {
      report.unmapped.push(name)
      continue
    }
    const { icon, filled, mirrored } = typeof entry === 'string' ? { icon: entry } : entry

    if (!LUCIDE.has(icon)) {
      report.badLucide.push(`${name} -> ${icon}`)
      continue
    }

    const src = readFileSync(join(LUCIDE_DIR, `${icon}.svg`), 'utf8')
    if (WRITE) writeFileSync(join(assets, `${name}.svg`), normalizeLucide(src, { filled, mirrored }))
    report.mapped.push(`${name} -> ${icon}`)
  }

  console.log(`\n=== ${appName} : ${names.length} icônes ===`)
  console.log(`  migrées vers Lucide : ${report.mapped.length}`)
  console.log(`  remplacées par un override : ${report.overridden.length}`)
  console.log(`  conservées (marques) : ${report.kept.length}`)
  if (report.badLucide.length) {
    console.log(`\n  !! NOMS LUCIDE INEXISTANTS (${report.badLucide.length}) :`)
    report.badLucide.forEach((l) => console.log(`     ${l}`))
  }
  if (report.unmapped.length) {
    console.log(`\n  !! NON MAPPÉES — à traiter à la main (${report.unmapped.length}) :`)
    report.unmapped.forEach((l) => console.log(`     ${l}`))
  }
  if (!WRITE) console.log('\n  (essai à blanc — relancer avec --write pour écrire)')

  return report.badLucide.length
}

const target = args.app || 'all'
const failures = (target === 'all' ? ['desktop', 'mobile'] : [target]).reduce((acc, a) => acc + run(a), 0)
process.exit(failures ? 1 : 0)
