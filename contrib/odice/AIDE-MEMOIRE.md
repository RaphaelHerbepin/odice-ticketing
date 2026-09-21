# Aide-mémoire — exploitation Odice

Toutes les commandes se lancent **depuis `/opt/odice-ticketing`** sur le VPS.

`ZDC` désigne l'installation Zammad à piloter. `make` importe les variables
d'environnement : **exportez-la une fois, et toutes les commandes en héritent.**

```bash
cd /opt/odice-ticketing
export ZDC=/opt/zammad-docker-compose
```

Pour ne plus jamais y penser, ajoutez cette ligne à `~/.bashrc`. En cas de
doute, `make help` affiche en tête la pile réellement visée — sans `ZDC`, ce
serait la pile de ce dépôt, qui n'est pas celle en service.

| | |
|---|---|
| Dépôt Odice | `/opt/odice-ticketing` (branche `odice/main`) |
| Installation Zammad | `/opt/zammad-docker-compose` |
| Sauvegardes de bascule | `/opt/odice-rollback` |
| Image Odice | `ghcr.io/raphaelherbepin/odice-ticketing` |
| Image historique | `ghcr.io/zammad/zammad:7.1.3-0000` |

---

## Au quotidien

```bash
make which-version              # quelle version tourne, et quelle build
make ps                         # état des conteneurs
make logs S=zammad-railsserver  # journaux applicatifs
make logs S=zammad-init         # migrations et démarrage
make console                    # console Rails
make backup                     # sauvegarde immédiate (voir plus bas)
make restart                    # redémarre les services applicatifs
```

---

## Basculer d'une version à l'autre

### Passer à Odice

```bash
make use-odice
```

Sauvegarde la base, épingle la version en service comme cible de retour,
bascule l'image, joue les migrations, applique le branding. **5 à 10 minutes.**

### Revenir à la version historique

```bash
make use-legacy-dry-run   # ce que ça coûterait, sans rien changer
make use-legacy     # pour de vrai
```

Restaure la base d'avant migration puis redémarre l'ancienne image. **Environ
5 minutes.** Ce qui a été créé depuis la bascule est listé avant d'agir, puis
perdu — d'où la fenêtre de décision conseillée de **48 heures**.

---

## Publier une nouvelle version d'Odice

Depuis votre poste :

```bash
git add -A && git commit -m "…" && git push origin odice/main
gh run list --repo RaphaelHerbepin/odice-ticketing     # attendre le ✓ (6-7 min)
git rev-parse --short=8 origin/odice/main             # donne le <sha8>
```

Le tag publié est `7.2.x-<sha8>`. Puis sur le VPS :

```bash
cd /opt/odice-ticketing && git pull
sed -i 's|^ODICE_IMAGE_TAG=.*|ODICE_IMAGE_TAG=7.2.x-<sha8>|' $ZDC/.env
sed -i 's|^VERSION=.*|VERSION=7.2.x-<sha8>|' $ZDC/.env
make backup
make up
```

Préférez toujours le tag horodaté à `odice-main`, qui change à chaque push. Il
correspond exactement à ce qu'affiche Administration → Version.

---

## Sauvegardes

| Quoi | Où | Quand |
|---|---|---|
| Quotidienne | volume `zammad-backup` | automatique, `BACKUP_TIME` |
| Avant bascule | `/opt/odice-rollback/*_pre-odice.psql.gz` | `make use-odice` |
| Avant retour | `/opt/odice-rollback/*_odice-avant-retour.psql.gz` | `make use-legacy` |

**Sauvegardez `/opt/odice-rollback` ailleurs** : sans lui, plus de retour arrière.

`make backup` s'appuie sur `BACKUP_ONCE`, que les images plus anciennes ne
connaissent pas forcément. En cas de doute, le dump direct marche toujours :

```bash
docker compose --project-directory $ZDC exec -T zammad-postgresql \
  pg_dump --no-owner --no-privileges -U zammad -d zammad_production \
  | gzip > /opt/odice-rollback/$(date +%Y%m%d%H%M%S)_manuel.psql.gz
```

Restaurer une sauvegarde précise :

```bash
contrib/odice/switch/use-legacy.sh --dump /opt/odice-rollback/<fichier>.psql.gz
```

---

## Copier la production sur un poste de développement

```bash
contrib/odice/vps-pull.sh --host raphael@srv1943441 --path /opt/zammad-docker-compose --inspect
contrib/odice/vps-pull.sh --host raphael@srv1943441 --path /opt/zammad-docker-compose
contrib/odice/restore-local.sh --from tmp/import
```

La copie est **neutralisée** (`odice:sandbox`) : canaux, déclencheurs et
automatisations désactivés, connexion par mot de passe activée. Sans cela, elle
relèverait les mêmes boîtes que la production et pourrait écrire à de vrais
clients. Ajoutez `ODICE_SANDBOX_PASSWORD=…` dans le `.env` local pour fixer le
mot de passe administrateur.

---

## Réparer

**Le logo ou le nom du produit a disparu** — ils vivent dans la table
`settings`, qu'une restauration écrase :

```bash
make provision
```

**La recherche ne renvoie rien** :

```bash
docker compose --project-directory $ZDC exec zammad-railsserver \
  bundle exec rake zammad:searchindex:rebuild
```

**Se connecter sans le SSO** (accès de secours) :

```bash
make console
# puis dans la console :
Setting.set('user_show_password_login', true)
User.find_by(login: 'r.herbepin@odice.cc').update!(password: '…', login_failed: 0)
```

**Le site répond `ERR_SSL_UNRECOGNIZED_NAME_ALERT`** — nginx-proxy ne génère
plus de vhost pour le domaine. Il découvre les sites par la variable
`VIRTUAL_HOST` des conteneurs qui partagent un réseau avec lui :

```bash
docker inspect zammad-docker-compose-zammad-nginx-1 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E 'VIRTUAL|LETSENCRYPT'
docker inspect nginx-proxy \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}'
```

Si `VIRTUAL_HOST` a disparu, reconstituez-le à partir de
[zdc/docker-compose.nginx-proxy.yml.example](zdc/docker-compose.nginx-proxy.yml.example),
puis `make up`. L'application, elle, n'est pas en cause : seule l'exposition
publique l'est, et aucun retour arrière n'est nécessaire.

**Voir ce qui bloque au démarrage** — `zammad-init` joue les migrations, tous
les autres l'attendent :

```bash
make logs S=zammad-init
```

---

## À ne jamais faire

**`docker compose down --remove-orphans` dans `/opt/zammad-docker-compose`.**
Ce serveur fait tourner `nginx-proxy` et `acme-companion`, que Compose signale
comme orphelins de ce projet. Cette option les supprimerait — avec le TLS et le
renouvellement des certificats de **tous** vos sites.

**Démarrer l'image historique sur une base migrée par Odice.** Deux migrations
ajoutent des contraintes que son code ne respecte pas : index unique sur
`recent_views` (erreur 500 à la deuxième ouverture d'un même ticket) et
`edited_at` en NOT NULL. L'application paraît fonctionner, puis casse à l'usage.
C'est pourquoi `use-legacy` restaure toujours la base, et refuse d'agir sans
sauvegarde.

**Changer `VERSION` ou `IMAGE_REPO` à la main pour basculer.** Vous sauteriez la
sauvegarde qui rend le retour possible.

**Laisser `ODICE_LEGACY_IMAGE_TAG` vide ou sur un tag mouvant.** C'est la cible
du retour arrière : elle ne doit pas changer sous vos pieds.

---

Détail des procédures : [BASCULE.md](BASCULE.md) · Migration de données :
[MIGRATION.md](MIGRATION.md) · Personnalisation : [README.md](README.md)
