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

Deux commandes suffisent :

```bash
make use-odice     # met la version Odice en service
make use-legacy    # revient à la version historique
make which-version # affiche ce qui tourne actuellement
```

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

## Première mise en service

### 1. Publier l'image

`contrib/odice/build.sh` refuse `--push` depuis un arbre de travail modifié — le
tag mentirait sur le contenu. La construction se fait en CI : `assets:precompile`
lance rolldown, un binaire natif Rust, dont l'émulation QEMU sur un Mac prend 30
à 60 minutes et plante.

```bash
git push origin odice/main        # déclenche .github/workflows/odice-image.yaml
gh run list --repo <compte>/odice-ticketing
```

Le workflow publie `ghcr.io/<compte>/odice-ticketing:7.2.x-<sha8>` et
`:odice-main`. **Préférez le tag horodaté** : il correspond exactement à ce
qu'affiche Administration → Version, ce qui permet de remonter d'un ticket de
support au commit.

L'image est publique ou privée selon les réglages du dépôt. Si elle est privée,
authentifiez le serveur une fois :

```bash
echo <token> | docker login ghcr.io -u <compte> --password-stdin
```

### 2. Reprendre l'installation existante dans cette pile

Si votre Zammad actuel tourne avec un autre `docker-compose.yml`, il faut
d'abord amener ses données dans les volumes de celle-ci.

```bash
git clone git@github.com:<compte>/odice-ticketing.git /opt/odice
cd /opt/odice && git checkout odice/main
cp .env.example .env && $EDITOR .env
```

Renseignez au minimum : `ODICE_SITE_ADDRESS`, `ODICE_ACME_EMAIL`,
`ZAMMAD_FQDN`, `NGINX_SERVER_NAME`, les mots de passe PostgreSQL, et
`ODICE_LEGACY_IMAGE_REPO` / `ODICE_LEGACY_IMAGE_TAG` avec **le tag exact de
votre image actuelle** :

```bash
(cd <ancien-répertoire> && docker compose config | grep image:)
```

Si ce tag est `latest`, épinglez une version précise maintenant : c'est votre
cible de retour arrière, elle ne doit pas changer sous vos pieds.

Puis, en partant de la version historique pour ne rien casser :

```bash
# Dans .env : ODICE_IMAGE_REPO / ODICE_IMAGE_TAG = l'image historique
make up

# Import des données de l'ancienne pile
contrib/odice/vps-pull.sh --local --path <ancien-répertoire>
contrib/odice/restore-local.sh --from tmp/import --keep-channels
```

`--keep-channels` est important : c'est la production, les canaux, déclencheurs
et automatisations doivent rester actifs. (Sans cette option, la restauration
appelle `odice:sandbox`, qui les désactive — c'est ce qu'on veut pour une copie
de test, jamais pour la production.)

Vérifiez que tout répond sur `support.odice.info`, puis seulement ensuite :

### 3. Basculer

```bash
make use-odice
```

Le script demande confirmation, sauvegarde la base, arrête la pile, redémarre
avec l'image Odice — les migrations s'appliquent au démarrage — puis attend que
l'application réponde. Coupure attendue : **5 à 10 minutes**.

Si la version Odice ne répond pas, le script s'arrête et affiche le chemin de la
sauvegarde ainsi que la commande de retour.

À vérifier tout de suite : connexion d'un agent, ouverture d'un ticket ancien
**avec pièce jointe**, création d'un ticket en contrôlant que les champs
conditionnels apparaissent selon le service et le type de demande — c'est le
test qui valide les 53 Core Workflows —, et le temps réel dans un second onglet.

## Revenir en arrière

```bash
make use-legacy-dry-run   # ce que ça coûterait, sans rien changer
make use-legacy           # pour de vrai
```

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
