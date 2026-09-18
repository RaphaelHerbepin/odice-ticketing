#!/usr/bin/env bash
# Odice — génération des dérivés de marque depuis les PNG sources.
#
# Les sources sont sur un canevas surdimensionné (3508x2481 pour les logos,
# 2017x1650 pour les pictogrammes) : l'artwork est entouré de marges
# transparentes variables et n'est jamais carré. Tout passe donc par
# `-trim +repage` puis un recadrage centré. `sips` ne sait pas détourer :
# ImageMagick est requis.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SRC="logos"
OUT="out"
CHARCOAL="#414042"
mkdir -p "$OUT"

magick() { command magick "$@"; }

# ---------- Détourage des sources ----------
magick "$SRC/picto-color.png"             -trim +repage "$OUT/.picto-color.png"
magick "$SRC/picto-white.png"             -trim +repage "$OUT/.picto-white.png"
magick "$SRC/logo-odice-horizontal.png"   -trim +repage "$OUT/.logo-h.png"
magick "$SRC/logo-odice-white-horizontal.png" -trim +repage "$OUT/.logo-h-white.png"

# Pictogramme carré avec 10 % de marge : base de toutes les icônes d'application.
magick "$OUT/.picto-color.png" -resize 819x819 \
  -background none -gravity center -extent 1024x1024 "$OUT/.picto-square.png"

# ---------- favicon multi-tailles ----------
magick "$OUT/.picto-square.png" \
  \( -clone 0 -resize 16x16 \) \( -clone 0 -resize 32x32 \) \
  \( -clone 0 -resize 48x48 \) \( -clone 0 -resize 64x64 \) \
  -delete 0 -background none "$OUT/favicon.ico"

# ---------- apple-touch-icon ----------
# iOS ignore la transparence et compose sur du noir : on aplatit sur blanc.
magick "$OUT/.picto-color.png" -resize 140x140 \
  -background white -gravity center -extent 180x180 -alpha remove -alpha off \
  "$OUT/apple-touch-icon.png"

# ---------- icônes PWA ----------
# La zone de sécurité d'une icône « maskable » est un cercle de 80 % : on place
# le pictogramme à 60 % pour qu'aucun découpage ne l'ampute.
for s in 192 512; do
  magick "$OUT/.picto-color.png" -resize $((s*80/100))x$((s*80/100)) \
    -background none -gravity center -extent ${s}x${s} "$OUT/app-icon-${s}.png"
  magick "$OUT/.picto-white.png" -resize $((s*60/100))x$((s*60/100)) \
    -background "$CHARCOAL" -gravity center -extent ${s}x${s} -alpha remove \
    "$OUT/app-icon-${s}-maskable.png"
done

# ---------- logo produit ----------
# ProductLogo.store redimensionne à 200x100 : fournir une image déjà à cette
# échelle évite un rééchantillonnage flou.
magick "$OUT/.logo-h.png"       -resize 200x100 "$OUT/logo-product.png"
magick "$OUT/.logo-h-white.png" -resize 200x100 "$OUT/logo-product-white.png"

# Repli servi par ProductLogo.sendable_asset, qui impose le type image/svg+xml :
# on encapsule le PNG dans un SVG plutôt que de vectoriser.
W=$(command magick identify -format '%w' "$OUT/logo-product.png")
H=$(command magick identify -format '%h' "$OUT/logo-product.png")
B64=$(base64 < "$OUT/logo-product.png" | tr -d '\n')
cat > "$OUT/logo.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 $W $H" width="$W" height="$H"><title>Odice</title><image width="$W" height="$H" xlink:href="data:image/png;base64,$B64"/></svg>
SVG

# ---------- logo pour les e-mails ----------
magick "$OUT/.logo-h.png" -resize 400x -background white -alpha remove -alpha off \
  "$OUT/email-logo.png"

rm -f "$OUT"/.*.png
echo "Généré dans $(pwd)/$OUT :"
ls -1 "$OUT"
