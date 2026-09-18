// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Filet de non-régression du jeu d'icônes Odice (migré vers Lucide).
 *
 * Ces contrôles portent sur les FICHIERS, pas sur le rendu : ils attrapent les
 * deux pièges du pipeline d'icônes, qui ne produisent aucune erreur au build et
 * ne se voient qu'à l'œil sur l'interface.
 */

const APPS = ['desktop', 'mobile'] as const

// Résolu depuis ce fichier, et non depuis process.cwd() : Vitest est lancé
// depuis la racine du dépôt alors que sa racine de projet est app/frontend.
const FRONTEND_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..')
const assetsDir = (app: string) => join(FRONTEND_ROOT, `apps/${app}/initializer/assets`)

const svgFiles = (app: string) =>
  readdirSync(assetsDir(app))
    .filter((file) => file.endsWith('.svg'))
    .map((file) => [file, readFileSync(join(assetsDir(app), file), 'utf8')] as const)

describe.each(APPS)('jeu d’icônes %s', (app) => {
  it('déclare un viewBox sur chaque icône', () => {
    // svgToSymbol() ne conserve que le viewBox : sans lui le <symbol> perd
    // toute mise à l'échelle. SVGO le supprime dès que width et height sont
    // présents sur la racine, d'où ce contrôle.
    const missing = svgFiles(app)
      .filter(([, content]) => !content.includes('viewBox='))
      .map(([file]) => file)

    expect(missing).toEqual([])
  })

  it('n’écrit pas width/height sur la racine des icônes en trait', () => {
    const offenders = svgFiles(app)
      .filter(([, content]) => content.includes('stroke="currentColor"'))
      .filter(([, content]) => /<svg\b[^>]*\s(width|height)=/.test(content))
      .map(([file]) => file)

    expect(offenders).toEqual([])
  })

  it('neutralise le remplissage sur les icônes en trait', () => {
    // CommonIcon.vue applique `fill-current` au <svg> externe. Sans un
    // `fill` explicite porté par l'élément, les tracés Lucide héritent de
    // `fill: currentColor` et l'icône s'affiche en aplat plein.
    const offenders = svgFiles(app)
      .filter(([, content]) => content.includes('stroke="currentColor"'))
      .filter(([, content]) => !content.includes('fill='))
      .map(([file]) => file)

    expect(offenders).toEqual([])
  })
})

describe('alias d’icônes', () => {
  it.each([
    ['desktop', 'apps/desktop/initializer/desktopIconsAliasesMap.ts'],
    ['mobile', 'apps/mobile/initializer/mobileIconsAliasesMap.ts'],
  ])('%s : chaque alias pointe vers une icône existante', (app, mapPath) => {
    const source = readFileSync(join(FRONTEND_ROOT, mapPath), 'utf8')
    const names = new Set(svgFiles(app).map(([file]) => file.slice(0, -4)))

    const broken = [...source.matchAll(/['"]?([\w-]+)['"]?\s*:\s*'([\w-]+)'/g)]
      .filter(([, , target]) => !names.has(target))
      .map(([, alias, target]) => `${alias} -> ${target}`)

    expect(broken).toEqual([])
  })
})
