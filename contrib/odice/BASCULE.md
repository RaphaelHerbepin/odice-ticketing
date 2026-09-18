# Mettre le frontend Odice en production, avec retour arrière

Ce document décrit la mise en production sur le VPS et la procédure de retour
arrière. Pour importer les données d'une instance existante vers un poste de
développement, voir [MIGRATION.md](MIGRATION.md).

## L'interdit, avant tout le reste

**Ne jamais faire pointer l'image historique sur la base migrée par Odice.**

Le VPS est 25 migrations en retard sur l'image Odice. Aucune n'est destructive —
ni `drop_table`, ni `remove_column`, ni `rename_column` — mais deux **ajoutent
des contraintes**, ce qui est tout aussi incompatible à rebours :

- `20260724130000_refactor_recent_views_upsert` pose un index **unique** sur
  `recent_views`. Le code de la version historique y fait un `RecentView.create!`
  sans protection, là où la version actuelle utilise `create_or_find_by` :
  l'ancienne image lèverait `RecordNotUnique` **à la deuxième ouverture d'un même
  ticket par un même agent**, soit une erreur 500 sur le geste le plus courant de
  l'application ;
- `20260707120000_add_edited_at_to_knowledge_base_answer_translations` passe
  `edited_at` en **NOT NULL** sans valeur par défaut ; l'ancien code ne renseigne
  pas cette colonne, toute création de traduction échouerait.

C'est pour cette raison que les deux piles ont **chacune leur base**, et que le
retour arrière consiste à rallumer une base restée intacte plutôt qu'à changer un
tag d'image.

## L'architecture en une image

```text
                ┌──────── Caddy (TLS, profil « front ») ────────┐
                │                                                │
 support.odice.fr ▼                       nouveau.odice.fr      ▼
   pile HISTORIQUE (zammad/zammad)          pile ODICE (image custom)
   base intacte = le filet de sécurité      base = copie restaurée, migrée
```

Un seul Caddy détient les ports 80/443 — celui de la pile Odice, dès la phase de
validation. Basculer revient alors à changer `ODICE_PROD_UPSTREAM` dans `.env` et
à recréer ce conteneur : environ cinq secondes, réversible à l'identique.

## Préparation

### 1. Publier l'image

`contrib/odice/build.sh` refuse `--push` depuis un arbre de travail modifié — le
tag mentirait sur le contenu. Il faut donc commiter et pousser d'abord. La
construction se fait en CI : `assets:precompile` lance rolldown, un binaire natif
Rust, dont l'émulation QEMU sur un Mac prend 30 à 60 minutes et plante.

```bash
git push origin odice/main       # déclenche .github/workflows/odice-image.yaml
```

Le workflow publie `ghcr.io/<compte>/odice-ticketing:7.2.x-<sha8>` et
`:odice-main`. Préférez le tag horodaté pour une validation reproductible.

### 2. Relever l'état du VPS

```bash
ss -tlnp | grep -E ':(80|443)'            # qui détient les ports aujourd'hui
free -h && df -h                          # deux piles, dont deux Elasticsearch
(cd /opt/zammad-docker-compose && docker compose config | grep image:)
docker network inspect <réseau-legacy> | grep Subnet
```

**Si l'image historique est sur un tag mouvant (`:latest`), épinglez-la
maintenant** — sinon la cible de votre retour arrière peut changer sous vos pieds :

```bash
docker images --digests | grep zammad
# puis dans le compose historique : image: zammad/zammad@sha256:<digest>
docker tag <image-id> zammad-legacy:rollback
```

## Phase de validation (entièrement réversible)

### 3. Démarrer la pile Odice

```bash
cp .env.staging.example .env.staging && $EDITOR .env.staging
make staging-up
```

Base séparée, sous-réseau `172.29.0.0/16` — le `172.28.0.0/16` de la pile de
production est figé et Docker refuse deux réseaux qui se chevauchent. Le nginx
est publié sur `127.0.0.1:8081` seulement.

### 4. Donner les ports 80/443 au Caddy Odice

C'est l'étape qui rend la bascule finale triviale — et si Caddy se comportait
mal, on s'en aperçoit **pendant que la pile historique sert encore**.

```bash
cp .env.example .env && $EDITOR .env
#   ODICE_SITE_ADDRESS=https://support.odice.fr
#   ODICE_PROD_UPSTREAM=host.docker.internal:8080   ← la pile historique
#   ODICE_STAGING_SITE_ADDRESS=nouveau.odice.fr
#   ODICE_STAGING_UPSTREAM=host.docker.internal:8081
cp docker/caddy/conf.d/10-staging.caddy{.example,}

# Libérer 80/443 côté historique, puis :
make front-reload
```

Vérifiez **immédiatement** que `https://support.odice.fr` répond toujours, que le
temps réel fonctionne et qu'un ticket s'envoie. En cas de doute, remettez
l'ancien terminateur : la pile Odice n'est pas en cause.

### 5. Charger une copie des données

```bash
contrib/odice/vps-pull.sh --local --path /opt/zammad-docker-compose
make staging-restore
```

La copie est **neutralisée** par `odice:sandbox` : canaux, déclencheurs,
automatisations et intégrations désactivés. Sans cela, elle relèverait les mêmes
boîtes que la production et pourrait écrire à de vrais clients.

### 6. Faire valider par les agents

Connexion, ouverture d'un ticket ancien **avec pièce jointe**, création d'un
ticket en vérifiant que les champs conditionnels apparaissent selon le service et
le type de demande — c'est le test qui valide les 53 Core Workflows —, et la page
Statistiques.

**Le SSO sur le domaine de validation.** `config/initializers/omniauth.rb`
construit `OmniAuth.config.full_host` à partir du `fqdn` en base ; chaque pile
ayant la sienne, la redirection part bien vers le bon domaine. Reste qu'Azure AD
refusera une URI de rappel non enregistrée. Deux options :

- pendant la validation fonctionnelle, la copie est en mode bac à sable :
  connexion par mot de passe, mot de passe admin dans `ODICE_SANDBOX_PASSWORD` ;
- la veille de la bascule, ajoutez
  `https://nouveau.odice.fr/auth/microsoft_office365/callback` dans l'inscription
  d'application Azure (l'ajout est additif, n'affecte pas la production, et se
  retire après) et réactivez le SSO sur la copie pour valider le parcours réel.

### 7. Répéter le retour arrière à blanc

```bash
make rollback-dry-run
```

Ne modifie rien, mais vérifie que la pile historique est joignable et affiche ce
que coûterait un retour arrière.

## Bascule

```bash
make cutover
```

Le script demande confirmation, puis : arrêt de la pile historique — **sa base
est gelée ici, c'est le point de restauration** —, export, restauration dans
Odice sans neutralisation, application de la configuration Odice avec le domaine
canonique, réindexation, bascule de l'amont Caddy, et horodatage du point de
non-retour dans `.odice-cutover-state`.

Coupure attendue : **5 à 10 minutes**. Aucun courriel entrant perdu, il n'y a pas
de canal IMAP.

Si la pile Odice ne répond pas après la restauration, le script s'arrête **avant**
de commuter le domaine et vous indique la commande de retour arrière.

## Retour arrière

```bash
make rollback
```

| Étape | Temps |
|---|---|
| Redémarrage de la pile historique (base intacte) | 10 s |
| Attente de sa disponibilité | 30 à 60 s |
| Bascule de l'amont Caddy | 5 s |
| Contrôle | 1 min |
| **Total** | **2 à 3 minutes** |

**Ce que cela coûte** : tout ce qui a été créé dans Odice depuis la bascule reste
dans la base Odice et n'apparaît pas dans la pile historique. Le script **liste
ces tickets avant de commuter**, avec leur numéro et leur titre, pour que rien ne
soit perdu par inadvertance. Rien n'est détruit : la pile Odice continue de
tourner, simplement elle n'est plus exposée.

**Fenêtre de décision : 48 heures.** Au-delà, le delta devient trop coûteux à
ressaisir : on ne revient plus en arrière, on corrige en avant avec une nouvelle
image.

## Après

Quelques jours de fonctionnement serein, puis :

```bash
make backup                                   # et copiez le dump hors du VPS
rm docker/caddy/conf.d/10-staging.caddy       # retirer le domaine de validation
make front-reload
(cd /opt/zammad-docker-compose && docker compose down)
```

Retirez aussi l'URI de rappel de validation dans Azure AD. Conservez la base
historique — un volume Docker de quelques mégaoctets — jusqu'à ce que vous soyez
certain de ne plus en avoir besoin.
