# Aide-mémoire — exploitation Odice

Toutes les commandes se lancent **depuis `/opt/odice-ticketing`** sur le VPS.

`ZDC` désigne l'installation Zammad à piloter. `make` importe les variables
d'environnement : **exportez-la une fois, et toutes les commandes en héritent.**

```bash
cd /opt/odice-ticketing
export ZDC=/opt/zammad-docker-compose
```

Pour ne plus jamais y penser, ajoutez cette ligne à `~/.bashrc` :

```bash
echo 'export ZDC=/opt/zammad-docker-compose' >> ~/.bashrc
```

En cas de doute, `make help` affiche en tête la pile réellement visée. Et si
vous oubliez l'export, les commandes refusent de s'exécuter en le rappelant —
elles ne partiront pas sur la mauvaise pile.

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

Puis sur le VPS, **une seule commande** — le tag n'est pas à recopier, il est
calculé à partir du commit :

```bash
cd /opt/odice-ticketing && git pull
make deploy
```

`deploy` vérifie que l'image existe au registry avant de toucher à quoi que ce
soit, prend une sauvegarde, bascule le tag et redémarre. Si la CI n'a pas fini,
il le dit et n'a rien modifié.

Pour connaître le tag sans déployer : `make image-tag`.

**La version en service est affichée dans l'interface**, en bas à droite de
chaque écran — discrète au repos, lisible au survol. C'est la valeur du fichier
`VERSION`, que le Dockerfile réécrit en `7.2.x-<sha8>.docker` : elle identifie
donc exactement le commit déployé, sans ouvrir de terminal.

### Déploiement continu

Une fois configuré (voir [BASCULE.md](BASCULE.md)), **chaque push déploie
automatiquement** : la CI construit l'image, puis ouvre une connexion au serveur
pour lancer le déploiement. Rien à lancer depuis le VPS, et tout se lit au même
endroit.

```bash
gh run list --repo RaphaelHerbepin/odice-ticketing   # build ET déploiement
tail -f tmp/ci-deploy.log                            # détail côté serveur
```

**Ce que cela implique :** chaque commit poussé devient une mise en production.
Chaque déploiement prend une sauvegarde dans `ODICE_ROLLBACK_DIR` au préalable,
et `make use-legacy` reste la porte de sortie.

Pour déployer à la main malgré tout :

```bash
cd /opt/odice-ticketing && git pull && make deploy
```

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

## Statistiques

Trois onglets, à `/desktop/statistics` :

| Onglet | Contenu |
|---|---|
| Vue d'ensemble | chiffres clés, volume créé/clôturé, état, priorité, canal |
| Axes métier | agence, service, objet de la demande — dérivés de vos champs personnalisés |
| Agents | charge, flux et délais par agent |

La période vit dans l'URL : `/desktop/statistics/axes?days=90` se transmet tel
quel, et changer d'onglet la conserve.

**Les axes métier suivent vos champs.** Ils sont dérivés d'`ObjectManager::Attribute` :
ajouter un champ de type liste ou arborescence dans l'administration suffit à le
voir apparaître comme axe, sans intervention sur le code.

**Le décompte du temps est facultatif**, en minutes, sur tous les tickets. Tant
que moins de la moitié des tickets portent une saisie, la carte affiche le taux
de saisie plutôt que le total — un total partiel présenté comme un total induit
en erreur. L'unité n'est qu'un libellé : Zammad ne convertit rien, donc tout le
monde saisit en minutes.

## Relances automatiques

Une automatisation est provisionnée : **rappel au propriétaire d'un ticket sans
activité depuis 3 jours**, les matins ouvrés à 8 h. Elle ne touche que les états
`new` et `open` — les mises en attente volontaires (« pending reminder »,
« pending close ») sont délibérément épargnées, sinon le rappel contredirait la
décision de l'agent.

Elle se trouve dans Administration → Automatisation, sous
« Odice — relance de l'agent après 3 jours sans activité ». **Vous pouvez la
modifier ou la désactiver librement** : le provisionnement ne la réécrit pas, il
se contente de la créer si elle a disparu.

> **Un ticket sans propriétaire ne déclenche aucune relance.** C'est
> intentionnel : sans destinataire, la notification ne partirait pas, le ticket
> resterait éligible indéfiniment et serait réévalué à chaque passage. Si vos
> tickets restent non assignés, c'est cette absence d'affectation qu'il faut
> traiter — au besoin par une seconde automatisation notifiant tous les agents
> du groupe.

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

## Deux environnements

Le déploiement passe désormais par une staging : un push sur `odice/main`
déploie sur `staging.support.odice.info`, et seule une étiquette de version part en
production, page de maintenance comprise.

Voir [ENVIRONNEMENTS.md](ENVIRONNEMENTS.md) — installation, rafraîchissement des
données, et ce qu'il faut savoir avant d'intervenir.

## À ne jamais faire

**`docker compose down --remove-orphans` (dans l'un OU l'autre répertoire de pile) dans `/opt/zammad-docker-compose`.**
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
