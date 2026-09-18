# Migrer une instance Zammad existante vers cette version

La reprise se fait par **sauvegarde / restauration**, et non par un import :
tout est repris — tickets, articles, pièces jointes, utilisateurs,
organisations, groupes, rôles, macros, déclencheurs, SLAs, base de
connaissances, historique, réglages.

## Avant de commencer

**Vérifier les versions.** Les migrations de schéma ne savent que monter :

```bash
# sur l'instance SOURCE
zammad run rails r 'puts Zammad::Version.get'   # paquet Debian/RPM
docker compose exec zammad-railsserver cat VERSION   # source dockerisée
```

La version de la source doit être **inférieure ou égale** à celle d'ici
(`cat VERSION` → `7.2.x`). Si la source est plus récente, mettez d'abord ce
fork à niveau (`git merge upstream/stable`, puis `make build`).

**Prévoir une interruption.** La restauration efface le schéma de la base cible
(`DROP SCHEMA PUBLIC CASCADE`). Ce n'est pas une fusion : tout ce que contient
l'instance cible est perdu.

## 1. Sauvegarder la source

Instance dockerisée :

```bash
docker compose run --rm -e BACKUP_ONCE=true zammad-backup
docker compose cp zammad-backup:/var/tmp/zammad ./sauvegarde-source
```

Instance installée par paquet :

```bash
/opt/zammad/contrib/backup/zammad_backup.sh
# produit /var/tmp/zammad_backup/<horodatage>_zammad_{db.psql,files.tar}.gz
```

Vous devez obtenir deux fichiers :

| Fichier | Contenu |
|---|---|
| `<horodatage>_zammad_db.psql.gz` | base PostgreSQL complète |
| `<horodatage>_zammad_files.tar.gz` | pièces jointes de `/opt/zammad/storage` |

## 2. Déposer la sauvegarde côté cible

```bash
make up                       # la pile doit tourner
docker compose stop zammad-backup

docker compose run --rm -v "$PWD/sauvegarde-source:/host:ro" \
  --entrypoint bash zammad-backup -c '
    mkdir -p /var/tmp/zammad/restore &&
    cp /host/*_zammad_db.psql.gz /host/*_zammad_files.tar.gz /var/tmp/zammad/restore/'
```

Les autres conteneurs se mettent d'eux-mêmes en attente pendant l'opération :
`bin/docker-entrypoint` bloque tant que `/var/tmp/zammad/restore` n'est pas vide
(fonction `check_no_restore_running`).

## 3. Restaurer

```bash
docker compose up -d zammad-backup
docker compose logs -f zammad-backup      # jusqu'à « restore finished »
```

Le script vide le schéma, injecte le dump, puis désarchive le stockage.

## 4. Migrer le schéma et réindexer

```bash
docker compose up -d --force-recreate zammad-init
docker compose logs -f zammad-init        # exécute db:migrate
docker compose exec zammad-railsserver bundle exec rake zammad:searchindex:rebuild
```

## 5. Réappliquer la configuration Odice — **indispensable**

La restauration a remplacé la base, donc **aussi les réglages de marque** :
nom du produit, logo, langue et traductions Odice sont revenus à ceux de
l'instance source.

```bash
make provision      # rejoue odice:provision en forçant
```

Cette étape réapplique le nom du produit, l'organisation, le logo, la langue
française et les libellés traduits.

## 6. Vérifier

```bash
docker compose exec zammad-railsserver bundle exec rails r '
  puts "tickets       : #{Ticket.count}"
  puts "utilisateurs  : #{User.count}"
  puts "organisations : #{Organization.count}"
  puts "groupes       : #{Group.count}"
  puts "pièces jointes: #{Store.count}"
  puts "produit       : #{Setting.get("product_name")}"
  puts "langue        : #{Setting.get("locale_default")}"'
```

Puis, dans l'interface : ouvrir un ticket ancien et vérifier qu'une pièce
jointe se télécharge (contrôle réel du stockage), et lancer une recherche
(contrôle de l'index).

## Points de vigilance

- **L'URL change.** Si la source répondait sur un autre domaine, corrigez
  `fqdn` et `http_type` (variables `ZAMMAD_FQDN` / `ZAMMAD_HTTP_TYPE`, puis
  `make provision`), sinon les liens des e-mails sortants pointeront vers
  l'ancienne adresse.
- **Les canaux e-mail redeviennent actifs** avec les identifiants de la source.
  Avant la première mise en service, désactivez-les si vous ne voulez pas que
  la nouvelle instance se mette à relever les boîtes de production :
  `Channel.where(area: 'Email::Account').each { |c| c.update!(active: false) }`.
- **Les mots de passe sont conservés** (empreintes reprises telles quelles).
- **Les sessions sont invalidées** : tout le monde devra se reconnecter.
- **Le compte administrateur créé ici** (`admin@odice.fr`) disparaît, remplacé
  par les comptes de la source.
- **Version de PostgreSQL** : le dump est restauré dans `postgres:17.5`. Un dump
  produit par un PostgreSQL plus récent que 17 peut être refusé ; dans ce cas,
  régénérez-le avec `pg_dump` de la version cible.

---

## Cas concret : la source est une instance Docker sur un VPS

C'est la configuration d'Odice : Zammad tourne en Docker sur un VPS Debian. La
pile locale de ce dépôt sait déjà restaurer — il suffit de lui présenter les
archives sous les bons noms, ce dont s'occupe `vps-pull.sh`.

### 1. Inspecter avant d'extraire

```bash
make remote-inspect HOST=root@vps.odice.fr REMOTE=/opt/zammad-docker-compose
```

Cette commande n'écrit rien. Si vous ne connaissez pas le chemin de la pile
distante : `ssh root@vps.odice.fr 'docker compose ls'`.

Trois informations à lire dans la sortie :

- **la version de Zammad** de la source. Elle doit être identique à celle de
  cette image, ou inférieure **sur la même branche majeure** — Zammad n'autorise
  pas de saut de majeure, donc depuis une 6.x il faut d'abord monter le serveur
  en 7.0 ;
- **`storage_provider`** : `DB` signifie que les pièces jointes sont dans la
  base, et le dump suffit (`--no-files`). `File` signifie qu'elles sont sur le
  disque et qu'il faut aussi l'archive de fichiers ;
- **la volumétrie**, pour estimer la durée du transfert.

### 2. Extraire

```bash
make remote-pull HOST=root@vps.odice.fr REMOTE=/opt/zammad-docker-compose
# → tmp/import/<horodatage>_zammad_db.psql.gz
#   tmp/import/<horodatage>_zammad_files.tar.gz
```

Le script produit son propre `pg_dump` plutôt que d'appeler le service de
sauvegarde du serveur : il fonctionne donc quelle que soit l'ancienneté du
`docker-compose.yml` d'en face, ne perturbe pas le cycle de sauvegarde en place,
et n'écrit rien sur le serveur — tout est streamé par SSH vers votre poste. La
production continue de tourner pendant l'opération.

Deux détails qui font la différence entre un export exploitable et un export qui
échoue à la restauration, parfois plusieurs minutes après :

- `docker compose exec` est appelé avec **`-T`**. Sans lui, Docker alloue un
  pseudo-terminal qui réécrit les fins de ligne et corrompt le flux gzip : on
  récupère une archive qui ne se décompresse qu'à moitié, sans erreur visible au
  transfert. Le script vérifie d'ailleurs chaque archive avec `gzip -t` ;
- le dump est produit avec `--no-owner --no-privileges`. Sans cela il porte des
  `ALTER … OWNER TO` et des `GRANT` visant le rôle PostgreSQL du serveur ; s'il
  diffère de celui de la pile locale, la restauration — qui tourne avec
  `ON_ERROR_STOP=1` — s'arrête dessus.

### 3. Vérifier localement

```bash
make restore-local
```

Le script demande confirmation, car il **détruit la base locale**
(`DROP SCHEMA PUBLIC CASCADE`), puis :

1. dépose les archives dans `/var/tmp/zammad/restore` ;
2. laisse `zammad-backup` restaurer — `zammad-init` attend d'ailleurs de lui-même
   la fin de l'opération (`check_no_restore_running`) avant de jouer les
   migrations qui hissent le schéma restauré à la version de cette image ;
3. réapplique la configuration Odice (`odice:provision --force`), **écrasée par
   la restauration** puisque le branding vit dans la table `settings` ;
4. neutralise la copie (`odice:sandbox`).

#### Pourquoi la neutralisation n'est pas optionnelle

Une base de production restaurée reste une instance complète : elle porte les
identifiants IMAP des boîtes support, les déclencheurs qui répondent aux clients
et les automatisations planifiées. Démarrée telle quelle sur un poste, la copie
relève les **mêmes** boîtes que la production — en y marquant les messages comme
lus — et peut écrire à de vrais clients.

`odice:sandbox` coupe les canaux, les déclencheurs, les automatisations et les
intégrations, ramène le FQDN sur `localhost` et suffixe le nom du produit par
« — COPIE ». Aucune donnée métier n'est touchée : seul l'attribut `active` de
quelques objets de configuration bascule. Pour passer outre — jamais sur un poste
connecté au réseau de production :

```bash
contrib/odice/restore-local.sh --from tmp/import --keep-channels
```

#### Ce qu'il faut regarder ensuite

Sur `http://localhost:8080`, avec un compte agent de la production :

- le nombre de tickets et la cohérence des vues d'ensemble ;
- l'ouverture d'un ticket ancien **avec pièces jointes** (c'est le contrôle qui
  valide l'archive de fichiers) ;
- les utilisateurs, organisations et groupes ;
- les champs personnalisés créés par vos paramétrages (Object Manager) ;
- la recherche, qui exige une réindexation Elasticsearch — l'entrypoint la lance
  automatiquement quand l'index n'existe pas encore, sinon :
  `docker compose exec zammad-railsserver bundle exec rake zammad:searchindex:rebuild`.

### 4. Et pour la mise en production

> **La mise en production a son propre document : [BASCULE.md](BASCULE.md).**
> Il décrit la pile de validation, la bascule, le retour arrière en 2 à 3
> minutes, et l'interdit à connaître : ne jamais faire pointer l'image
> historique sur une base migrée par Odice.

Une fois la vérification concluante, la bascule du VPS vers le frontend Odice est
franchement simple, puisque la source est déjà une pile Docker : il s'agit de
remplacer l'image `zammad/zammad` par l'image Odice dans le `docker-compose.yml`
du serveur, avec le `docker-compose.yml` de ce dépôt comme référence. La base
reste en place — aucune migration de données n'est nécessaire. Seul
`rake odice:provision` doit être joué une fois pour appliquer le branding.
