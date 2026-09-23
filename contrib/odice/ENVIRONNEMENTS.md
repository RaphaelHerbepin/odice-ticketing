# Staging et production

Deux instances sur le même serveur, deux chaînes de déploiement distinctes, et
une page de maintenance pendant les mises en production.

| | production | staging |
|---|---|---|
| domaine | `support.odice.info` | `staging.support.odice.info` |
| pile Docker | `/opt/zammad-docker-compose` | `/opt/zammad-staging` |
| projet Compose | `zammad-docker-compose` | `zammad-staging` |
| dépôt de pilotage | `/opt/odice-ticketing` | `/opt/odice-ticketing-staging` |
| déclencheur | étiquette `v*` | push sur `odice/main` |
| clé de déploiement | `odice-ci-prod` | `odice-ci-staging` |
| données | les vraies | copie neutralisée de la production |

## Le principe

**L'environnement est une propriété de l'emplacement, jamais un argument.**

Chaque opération dangereuse lit `ODICE_ENVIRONMENT` **dans la pile qu'elle
vise**, et refuse d'agir si ce n'est pas celle attendue. Un `--dir` mal tapé ne
peut donc pas devenir une restauration sur la production. Les confirmations à
taper existent toujours, mais elles ne protègent de rien : on tape « oui » par
réflexe, surtout la dixième fois.

## Au quotidien

### Publier une version

```bash
git push origin odice/main          # → construit, contrôle, déploie sur le STAGING
```

Regarder `https://staging.support.odice.info/`. Quand c'est bon :

```bash
git tag -a v1.4.0 -m "Tableau de bord analytique"
git push origin v1.4.0              # → page de maintenance, puis PRODUCTION
```

La production ne reconstruit rien : elle met en service **exactement l'image
validée en staging**. Reconstruire depuis l'étiquette donnerait une image
différente — image de base rafraîchie, dépendances flottantes — de celle qu'on a
regardée, ce qui viderait le staging de son sens.

Une étiquette posée sur un commit absent de `odice/main` est refusée : il ne
serait jamais passé par le staging.

### Recharger le staging avec les données du jour

```bash
cd /opt/odice-ticketing-staging
make refresh-staging
```

La production continue de tourner pendant l'extraction. La copie est neutralisée
avant que quoi que ce soit ne puisse en sortir : canaux e-mail coupés,
déclencheurs et automatisations désactivés, adresse réécrite, SSO remplacé par
un mot de passe.

À faire **le soir** : la réindexation Elasticsearch monopolise le processeur et
dégraderait la production aux heures ouvrées.

### Page de maintenance, à la main

```bash
export ZDC=/opt/zammad-docker-compose
make maintenance-status            # où en est-on ?
make maintenance-on                # coupe le site, affiche la page
make maintenance-off               # rend le site
```

## Ce qu'il faut comprendre avant d'intervenir

### La page de maintenance repose sur une variable, pas sur un conteneur

nginx-proxy répartit les requêtes entre **tous** les conteneurs déclarant un même
`VIRTUAL_HOST`. Démarrer une page de maintenance à côté de l'application donnerait
une alternance aléatoire entre les deux. Et détacher l'application du réseau ne
tient pas : `docker compose up -d` la recrée au milieu du déploiement, avec son
vhost retrouvé depuis le fichier compose.

D'où l'indirection `VIRTUAL_HOST: ${ZAMMAD_VIRTUAL_HOST:-}`. La vider dans le
`.env` retire l'application des vhosts **de façon persistante aux recréations de
conteneurs** : c'est le seul état qui survive à un `up -d`.

**Conséquence à connaître** : si `ZAMMAD_VIRTUAL_HOST` est vide dans le `.env`,
le site est invisible, même après un redémarrage du serveur, et rien n'a l'air
cassé. `make maintenance-status` le signale ; `make maintenance-off` le répare.

### Un déploiement qui échoue laisse la maintenance en place

C'est voulu : rendre le domaine à une application cassée est pire qu'une page
d'attente. Le script affiche alors les deux commandes de sortie. **Personne n'est
prévenu automatiquement** — surveiller le journal du workflow, ou poser une
tâche cron sur l'ancienneté de `.odice-maintenance-state`.

### Les points d'entrée SSH vivent hors du dépôt

Le déploiement fait `git checkout --force` sur le dépôt. Bash lit un script au
fil de son exécution : réécrire sous lui le fichier qu'il interprète le fait
poursuivre sur un contenu décalé. Les points d'entrée sont donc installés dans
`/usr/local/sbin/`.

**Après toute modification de `contrib/odice/switch/ci-deploy-*.sh`** :

```bash
make install-ci-entry              # sinon le serveur exécute l'ancienne version
```

## Installation, une fois

Dans l'ordre. Les étapes 1 à 7 ne touchent pas la production.

**Elasticsearch est coupé sur le staging** : le serveur dispose de 4 Go libres
et d'aucun espace d'échange, et un second nœud en réclamerait un à deux, au
détriment direct de la production. Zammad le supporte nativement — l'entrypoint
pose `es_url` à vide et la recherche bascule sur SQL. En contrepartie, **la
recherche du staging n'est pas représentative** : pas de plein texte dans le
corps des articles, pas de pertinence. Une régression de recherche ne se verra
donc qu'en production.

```bash
# 1. Mesurer AVANT. Deux Elasticsearch, c'est la mémoire qui cède en premier.
free -g ; df -h /var/lib/docker

# 2. Marquer la production, et relever ses volumes pour comparaison ultérieure
echo 'ODICE_ENVIRONMENT=production' >> /opt/zammad-docker-compose/.env
docker volume ls | grep zammad-docker-compose

# 3. Créer l'enregistrement DNS staging.support.odice.info AVANT le premier démarrage :
#    acme-companion tente le challenge dès qu'il voit LETSENCRYPT_HOST, et un
#    échec le met en retrait exponentiel.

# 4. Relever le nom du réseau du proxy — il n'est PAS « nginx-proxy » ici :
#    le proxy fait partie du projet Compose de la production, ses volumes
#    s'appelant « zammad-docker-compose_nginx-proxy-* ».
docker inspect nginx-proxy \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}'

# 5. La pile de staging
git clone https://github.com/zammad/zammad-docker-compose.git /opt/zammad-staging
git clone git@github.com:RaphaelHerbepin/odice-ticketing.git /opt/odice-ticketing-staging
cd /opt/odice-ticketing-staging && git checkout odice/main
./contrib/odice/zdc/install.sh /opt/zammad-staging
cp contrib/odice/staging/docker-compose.staging.yml /opt/zammad-staging/docker-compose.override.yml
cat contrib/odice/staging/env.staging.example >> /opt/zammad-staging/.env
$EDITOR /opt/zammad-staging/.env   # mots de passe, et ODICE_PROXY_NETWORK si
                                   # le nom relevé en 4 n'est pas celui par défaut

# 6. Vérifier l'ISOLEMENT avant tout démarrage — c'est le contrôle qui compte
cd /opt/zammad-staging
docker compose config --format json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["name"], list(d.get("volumes",{}).keys()))'
docker compose config | grep -E 'VIRTUAL_HOST|LETSENCRYPT'

# 7. Premier démarrage, base VIDE. Puis vérifier que les volumes sont NEUFS.
docker compose up -d
docker volume ls | grep zammad-staging
docker volume ls | grep zammad-docker-compose      # doit être inchangé

# 8. Barrière réseau : la seule protection qui survive à une erreur de script
SUBNET=$(docker network inspect zammad-staging_default -f '{{(index .IPAM.Config 0).Subnet}}')
sudo iptables -I DOCKER-USER -s "$SUBNET" -p tcp -m multiport --dports 25,465,587,143,993 -j REJECT
sudo apt install iptables-persistent && sudo netfilter-persistent save

# 9. Premières données, en surveillant le planificateur
cd /opt/odice-ticketing-staging && make refresh-staging

# 10. Répéter la maintenance SUR LE STAGING avant de l'essayer en production
export ZDC=/opt/zammad-staging
make maintenance-on && curl -sI https://staging.support.odice.info/ | head -3
make maintenance-off

# 11. Points d'entrée et clés
cd /opt/odice-ticketing-staging && sudo make install-ci-entry
ssh-keygen -t ed25519 -f ~/.ssh/odice-ci-staging -C odice-ci-staging -N ''
ssh-keygen -t ed25519 -f ~/.ssh/odice-ci-prod    -C odice-ci-prod    -N ''
```

Puis dans `~/.ssh/authorized_keys`, une ligne par clé :

```
command="/usr/local/sbin/odice-deploy-staging",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA… odice-ci-staging
command="/usr/local/sbin/odice-deploy-production",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA… odice-ci-prod
```

Et dans les secrets GitHub : `ODICE_DEPLOY_KEY_STAGING` et
`ODICE_DEPLOY_KEY_PROD` (clés privées). `ODICE_DEPLOY_KEY` reste en repli tant
que le staging n'existe pas — **jusque-là, un push déploie donc encore
directement en production.**

## Deux avertissements

**Le staging héberge l'intégralité du fichier client**, sur un sous-domaine
public, avec le SSO coupé et une simple authentification par mot de passe. C'est
une régression de sécurité par rapport à la production, et une question RGPD.
Ajouter une authentification HTTP au niveau de nginx-proxy :

```bash
docker exec nginx-proxy sh -c 'ls /etc/nginx/htpasswd/'   # retrouver le volume
htpasswd -c /chemin/du/volume/staging.support.odice.info odice
```

**Ne jamais lancer `docker compose down --remove-orphans` ni `down -v`** — ni
dans `/opt/zammad-docker-compose`, ni désormais dans `/opt/zammad-staging`. Le
premier emporterait `nginx-proxy` et `acme-companion`, donc le TLS de tous les
sites du serveur ; le second détruirait les volumes.
