# Basculer entre la version historique et la version Odice

Ce document décrit l'exploitation courante sur `support.odice.info`. Pour
importer les données d'une instance vers un poste de développement, voir
[MIGRATION.md](MIGRATION.md).

## Le principe

Une seule pile Docker, un seul domaine, **une seule base de données**. Les deux
versions ne tournent jamais en même temps : basculer revient à changer le tag de
l'image et à redémarrer.

```text
              support.odice.info
                      │
                   Caddy (TLS)
                      │
                 zammad-nginx
                      │
        ┌─────────────┴─────────────┐
        │   UNE seule à la fois     │
        │                           │
   zammad/zammad:<tag>     ghcr.io/…/odice-ticketing:<tag>
        └─────────────┬─────────────┘
                      │
     PostgreSQL · Redis · Elasticsearch · memcached
              (volumes communs, jamais détruits)
```

Deux commandes suffisent. `ZDC=` désigne votre installation
zammad-docker-compose ; omettez-le si vous utilisez la pile de ce dépôt.

```bash
make use-odice     ZDC=/opt/zammad-docker-compose   # version Odice en service
make use-legacy    ZDC=/opt/zammad-docker-compose   # retour à l'historique
make which-version ZDC=/opt/zammad-docker-compose   # ce qui tourne
```

Les scripts reconnaissent seuls la pile visée — `IMAGE_REPO`/`VERSION` pour
zammad-docker-compose, `ODICE_IMAGE_REPO`/`ODICE_IMAGE_TAG` pour celle-ci — et
lisent les identifiants PostgreSQL au bon endroit dans chaque cas.

## Ce que ces commandes font de plus qu'un `down` / `up`

**C'est la partie à ne pas court-circuiter.** Les deux versions partagent la
même base, et l'image Odice applique 25 migrations que la version historique
n'a pas. Aucune n'est destructive — ni `drop_table`, ni `remove_column` — mais
deux **ajoutent des contraintes**, ce qui est tout aussi incompatible à rebours :

| Migration | Ce qu'elle ajoute | Ce que fait le code historique dessus |
|---|---|---|
| `20260724130000_refactor_recent_views_upsert` | index **UNIQUE** sur `recent_views` | `RecentView.create!` sans protection → `RecordNotUnique` **à la deuxième ouverture d'un même ticket par un agent**, soit une erreur 500 sur le geste le plus courant |
| `20260707120000_add_edited_at_to_kb_answer_translations` | `edited_at` en **NOT NULL** | ne renseigne pas la colonne → toute création de traduction échoue |

Autrement dit : **démarrer l'image historique sur une base migrée donne une
application qui paraît fonctionner, puis casse à l'usage.** C'est un piège
silencieux, et c'est la raison d'être de ces scripts.

Ils gèrent donc trois choses :

1. `use-odice.sh` **sauvegarde la base avant** de laisser les migrations
   s'appliquer, dans `ODICE_ROLLBACK_DIR` ;
2. il **épingle le tag de l'image en service** dans `.env`
   (`ODICE_LEGACY_IMAGE_TAG`), pour que la cible du retour ne change pas ;
3. `use-legacy.sh` **restaure cette sauvegarde** avant de redémarrer l'ancienne
   image, ce qui remet le schéma dans l'état qu'elle sait servir.

## Vous utilisez zammad-docker-compose — c'est le cas le plus simple

Le compose officiel déclare `image: ${IMAGE_REPO:-ghcr.io/zammad/zammad}:${VERSION}`.
**Changer ces deux variables suffit à basculer**, sur exactement les mêmes
volumes : aucune donnée n'est déplacée, la base est rigoureusement la même. Vous
gardez votre installation, votre `docker-compose.yml` reste à jour par
`git pull`, et les scripts la détectent d'eux-mêmes.

### 1. Publier l'image

La construction se fait en CI : `assets:precompile` lance rolldown, un binaire
natif Rust, dont l'émulation QEMU sur un Mac prend 30 à 60 minutes et plante.

```bash
git push origin odice/main        # déclenche .github/workflows/odice-image.yaml
gh run list --repo <compte>/odice-ticketing
```

Notez le tag publié — préférez l'horodaté `7.2.x-<sha8>` au tag de branche : il
correspond exactement à ce qu'affiche Administration → Version.

Si le paquet GHCR est privé, authentifiez le serveur une fois :

```bash
echo <token> | docker login ghcr.io -u <compte> --password-stdin
```

### 2. Installer le complément Odice sur le serveur

```bash
git clone git@github.com:<compte>/odice-ticketing.git /opt/odice
cd /opt/odice && git checkout odice/main
make install-zdc ZDC=/opt/zammad-docker-compose
```

Cela dépose deux choses, sans toucher à votre `docker-compose.yml` :

- `docker-compose.override.yml` — Compose le charge automatiquement. Il ajoute
  les variables `ODICE_*` à l'environnement des conteneurs. Sans lui,
  `rake odice:provision` ne les verrait pas et le branding ne s'appliquerait
  pas : le compose officiel énumère explicitement les variables qu'il transmet ;
- les lignes de configuration Odice à la fin de votre `.env`.

Relisez ensuite `/opt/zammad-docker-compose/.env` et ajustez `ODICE_IMAGE_TAG`,
`ODICE_ROLLBACK_DIR` et les valeurs de marque.

Créez le répertoire de sauvegarde **au bon propriétaire** — c'est là que sera
écrit le dump d'avant migration, celui qui rend le retour arrière possible :

```bash
sudo mkdir -p /opt/odice-rollback && sudo chown "$USER" /opt/odice-rollback
```

> **Si votre serveur fait tourner nginx-proxy, Traefik ou un autre reverse
> proxy partagé**, `docker compose` les signale comme « orphan containers » de
> ce projet. C'est sans gravité — mais ne lancez **jamais**
> `docker compose down --remove-orphans` dans ce répertoire : vous supprimeriez
> le reverse proxy et le renouvellement des certificats de tout le serveur. Les
> scripts de bascule ne passent pas cette option.

### 3. Sauvegarder, puis basculer

```bash
cd /opt/zammad-docker-compose && docker compose exec -T zammad-backup \
  /opt/zammad/contrib/docker/backup.sh   # ou attendez la sauvegarde nocturne

cd /opt/odice
make use-odice ZDC=/opt/zammad-docker-compose
```

Le script relève l'image en service et l'épingle comme cible de retour, demande
confirmation, sauvegarde la base, bascule `IMAGE_REPO` et `VERSION`, redémarre,
applique `odice:provision`, puis attend que l'application réponde. Coupure
attendue : **5 à 10 minutes**.

Vérifiez à tout moment ce qui tourne :

```bash
make which-version ZDC=/opt/zammad-docker-compose
```

## Si vous utilisez la pile de ce dépôt

Le fonctionnement est identique, sans `ZDC=`. Les variables d'image s'appellent
alors `ODICE_IMAGE_REPO` et `ODICE_IMAGE_TAG`, et le service `odice-provision`
joue le provisioning automatiquement via le profil `odice`.

```bash
cp .env.example .env && $EDITOR .env
make up            # démarre avec l'image indiquée
make use-odice     # bascule
```

## Revenir en arrière

```bash
make use-legacy-dry-run ZDC=/opt/zammad-docker-compose   # sans rien changer
make use-legacy         ZDC=/opt/zammad-docker-compose   # pour de vrai
```

(sans `ZDC=` si vous utilisez la pile de ce dépôt)

Environ **5 minutes** : sauvegarde de l'état Odice, restauration du schéma
d'avant migration, redémarrage avec l'image historique.

**Ce que cela coûte** : tout ce qui a été créé depuis la bascule. Le script les
**liste avant d'agir** — numéro et titre de chaque ticket — pour que rien ne soit
perdu par inadvertance. Rien n'est détruit pour autant : l'état Odice est
sauvegardé dans `ODICE_ROLLBACK_DIR` avant d'être écrasé.

**Fenêtre de décision conseillée : 48 heures.** Au-delà, le delta devient trop
coûteux à ressaisir ; on ne revient plus en arrière, on corrige en avant avec
une nouvelle image :

```bash
make use-odice --tag 7.2.x-<nouveau-sha8>
```

## Mettre à jour la version Odice

Sans retour arrière, donc sans perte :

```bash
git -C /opt/odice pull
$EDITOR .env                 # ODICE_IMAGE_TAG=7.2.x-<nouveau-sha8>
make up
```

Les migrations éventuelles s'appliquent au démarrage de `zammad-init`. Prenez
une sauvegarde d'abord : `make backup`.

## Dépannage

**`COMPOSE_PROFILES` dans `.env`** est renseigné par les scripts de bascule :
`odice` quand la version Odice est en service, vide sinon. C'est ce qui permet
à `make up` et `make restart` de rester corrects sans y penser. Si vous le videz
à la main alors qu'Odice tourne, `odice-provision` ne sera plus joué — sans
conséquence immédiate, la tâche étant idempotente et déjà appliquée.

**Savoir ce qui tourne :**

```bash
make which-version
make logs S=zammad-railsserver
```

**La pile ne démarre pas après une bascule.** Regardez `zammad-init` en premier :
c'est lui qui joue les migrations, et les autres conteneurs l'attendent
(`check_zammad_ready`).

```bash
make logs S=zammad-init
```

**Les sauvegardes d'avant bascule** sont dans `ODICE_ROLLBACK_DIR`
(`/opt/odice/rollback` par défaut), nommées `<horodatage>_pre-odice.psql.gz` et
`<horodatage>_odice-avant-retour.psql.gz`. Elles sont hors des volumes Docker :
**sauvegardez ce répertoire ailleurs**, c'est lui qui rend le retour possible.

**Restaurer une sauvegarde précise :**

```bash
contrib/odice/switch/use-legacy.sh --dump /opt/odice/rollback/<fichier>.psql.gz
```

**Le branding a disparu après une restauration.** Normal : `product_logo`,
`product_name` et `locale_default` vivent dans la table `settings`, qu'une
restauration écrase. Rejouez :

```bash
make provision
```

**Sauvegardes quotidiennes.** Le service `zammad-backup` tourne en continu et
écrit dans le volume `zammad-backup` à l'heure fixée par `BACKUP_TIME`. Elles
sont distinctes des sauvegardes de bascule ; les deux sont utiles.
