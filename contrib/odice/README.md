# Personnalisation Odice

Ce dossier regroupe les outils de la distribution Odice de Zammad : jeu
d'icônes, assets de marque, construction de l'image et provisionnement.

## Principe

Tout ce qui est propre à Odice vit dans des **fichiers nouveaux**. Les fichiers
Zammad ne sont modifiés que là où il n'existe aucun point d'extension, afin que
`git merge upstream/stable` reste simple.

Zammad fournit trois mécanismes exploités ici :

| Mécanisme | Usage | Empreinte amont |
|---|---|---|
| `app/frontend/apps/{desktop,mobile}/styles/custom/*.css` | Toute la couleur, la typographie et la refonte visuelle, via le marqueur `data-zammad-target` | aucune |
| `app/assets/stylesheets/custom/*.css` | Même chose pour le frontend CoffeeScript | aucune |
| `app/frontend/addons/odice/odice.weave.mjs` | Changements de structure du DOM (réécriture du source en mémoire) | aucune |
| `initializer/assets/*.svg` | Jeu d'icônes, à noms de fichiers constants | fichiers d'assets |

## Thème

Les fichiers CSS sont chargés **non-layerés et après** les styles de
l'application : ils l'emportent sur toute règle Tailwind sans `!important`.
L'ordre est celui du tri des noms, d'où les préfixes numériques.

**Règle absolue : on redéfinit les valeurs des jetons, jamais leurs noms.**
`initializeGlobalComponentStyles.ts` code en dur des chaînes de classes
(`bg-red-500`, `bg-neutral-500`…) ; renommer l'échelle casserait badges,
alertes et avatars sans erreur visible.

Vérifier le thème : `make lint-odice`.

## Icônes

```bash
node contrib/odice/icons/migrate-icons.mjs --app=all           # essai à blanc
node contrib/odice/icons/migrate-icons.mjs --app=all --write   # écriture
```

Le script écrit le SVG Lucide **sous le nom de fichier Zammad**, ce qui évite
toute modification de code. Il refuse un nom Lucide inexistant plutôt que de
deviner. `keep.mjs` liste les icônes à ne jamais toucher (logos de marques,
attribution Zammad). Pour dessiner une icône à la main, la déposer dans
`icons/overrides/<app>/<nom>.svg` : elle prime sur la table.

Deux contraintes imposées par `app/frontend/build/iconsPlugin.mjs`, respectées
par le script :

1. pas de `width`/`height` sur la racine, sinon SVGO supprime le `viewBox` —
   or `svgToSymbol()` ne conserve que lui, et sans lui l'icône perd sa mise à
   l'échelle ;
2. les attributs de trait vont sur un `<g>` interne, car `svgToSymbol()` jette
   tous les attributs racine. Sur le `<g>`, `fill="none"` l'emporte sur la
   valeur héritée de la classe `fill-current` posée par `CommonIcon.vue`.

L'épaisseur de trait est posée en CSS (`styles/custom/20-odice-icons.css`) et
non dans les fichiers : elle est héritée, et compensée par palier de taille.

## Assets de marque

```bash
./contrib/odice/brand/build-brand-assets.sh
```

Régénère favicon, icônes PWA (dont les variantes _maskable_), logo produit et
logo d'e-mail depuis les PNG de `brand/logos/`. Les sources sont sur un canevas
surdimensionné avec des marges transparentes : le script détoure puis recadre.

Le **logo produit** n'est pas servi depuis l'image : il est stocké en base par
`rake odice:provision` (`Service::SystemAssets::ProductLogo`).
`public/assets/images/logo.svg` n'en est que le repli.

## Construction et déploiement

```bash
make dev-up                     # services de développement
source docker/dev/env.sh
bin/setup --skip-server && bin/dev

make build                      # image (COMMIT_SHA fourni automatiquement)
cp .env.example .env            # puis renseigner
make up                         # production
make provision                  # réapplique la configuration Odice
make backup                     # sauvegarde immédiate
```

Le tag de l'image (`odice-ticketing:7.2.x-<sha8>`) correspond exactement à la
version affichée dans Administration → Version.

## Déployer sur une instance native existante

```bash
./contrib/odice/deploy-to-native.sh utilisateur@serveur --dry-run   # essai
./contrib/odice/deploy-to-native.sh utilisateur@serveur
```

Une installation par paquet ne peut pas recompiler le frontend Vue :
`script/build/cleanup.sh` retire `node_modules` du paquet, et le serveur n'a ni
Node ni pnpm. Le script construit donc localement l'image Docker de ce dépôt —
qui produit la même arborescence `/opt/zammad` — et transfère les fichiers déjà
compilés (`public/assets`, environ 49 Mo) ainsi que le code serveur ajouté.

Les paramétrages de l'instance vivent en base de données : ils ne sont pas
touchés. En revanche **chaque mise à jour du paquet Zammad écrase
`/opt/zammad`** et impose de relancer le script. Pour éviter cette reprise à
chaque montée de version, voir les deux autres voies ci-dessous.

## Reprise d'une instance existante

Voir [MIGRATION.md](MIGRATION.md) : sauvegarde / restauration complète, avec
le point à ne pas oublier — la restauration écrase la base, donc le branding
Odice, et impose de rejouer `make provision`.

### Exploitation

**[AIDE-MEMOIRE.md](AIDE-MEMOIRE.md) — toutes les commandes sur une page.**
C'est le document à ouvrir en premier au quotidien.

### Basculer entre les deux versions

Une seule pile, un seul domaine, une seule base. Voir [BASCULE.md](BASCULE.md).

```bash
make which-version        # ce qui tourne actuellement
make use-odice            # met la version Odice en service
make use-legacy-dry-run   # ce que coûterait le retour, sans rien changer
make use-legacy           # revient à la version historique
```

`use-odice.sh` sauvegarde la base avant de laisser les migrations s'appliquer,
et `use-legacy.sh` restaure cette sauvegarde. Ce n'est pas une précaution de
confort : deux migrations Odice ajoutent des contraintes que le code historique
ne respecte pas — un index unique sur `recent_views` et `edited_at` en NOT NULL.
Sur une base migrée, l'ancienne image rend une erreur 500 à la deuxième
ouverture d'un même ticket.

### Source : instance Docker sur un serveur distant

```bash
make remote-inspect HOST=root@vps.odice.fr   # n'écrit rien : version, storage_provider, volumétrie
make remote-pull    HOST=root@vps.odice.fr   # → tmp/import/*.gz
make restore-local                           # charge la copie dans la pile locale
```

`REMOTE=` indique le répertoire du `docker-compose.yml` distant
(`/opt/zammad-docker-compose` par défaut).

`vps-pull.sh` produit son propre `pg_dump --no-owner --no-privileges` plutôt que
d'appeler le service de sauvegarde du serveur : il fonctionne quel que soit l'âge
du compose d'en face, n'écrit rien sur le serveur et ne perturbe pas le cycle de
sauvegarde en place. Le `-T` de `docker compose exec` n'est pas négociable — sans
lui, le pseudo-terminal corrompt le flux gzip.

`restore-local.sh` détruit la base locale, restaure, rejoue `odice:provision`,
puis lance `odice:sandbox`.

### `odice:sandbox` — neutraliser une copie de production

Une base restaurée porte les identifiants IMAP des boîtes support, les
déclencheurs qui répondent aux clients et les automatisations planifiées : la
copie relèverait les mêmes boîtes que la production et pourrait écrire à de
vrais clients. La tâche désactive canaux, déclencheurs, automatisations et
intégrations, ramène le FQDN sur `localhost` et suffixe le nom du produit par
« — COPIE ». Aucune donnée métier n'est touchée. Elle exige
`ODICE_SANDBOX_CONFIRM=1`, pour qu'un lancement distrait ne puisse pas
interrompre la production.

## Polices

Fundamental Brigade (OFL + GPL avec exception de police, Peter Wiegel) pour les
titres, Inter (SIL OFL 1.1) pour le corps. Toutes deux redistribuables.

Gilroy et Brandon Grotesque, prescrites par la charte 2020, ne sont pas
fournies et sont sous licence commerciale. Pour basculer : déposer les `woff2`
dans `public/assets/fonts/odice/`, ajouter les `@font-face` dans
`styles/custom/10-odice-type.css` et les placer en tête de `--font-sans` /
`--font-display`.

Ne jamais reverser dans le dépôt les polices système présentes dans le dossier
source (`SFNS`, `Monaco`, `Geneva`) : elles appartiennent à Apple et ne sont pas
redistribuables. Academy Engraved LET est également propriétaire.
