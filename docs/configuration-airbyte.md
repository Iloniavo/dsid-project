---
document : Configuration Airbyte — déploiement, objets et preuves
concerne : les trois flux
mise_a_jour : 2026-11-13
---

# Configuration Airbyte — déploiement, objets et preuves

> Ce document rassemble ce qui est commun aux trois flux : le mode de déploiement retenu,
> l'inventaire des objets Airbyte, les règles de réseau, les preuves à conserver et les
> règles de sécurité. Le détail de chaque flux est dans les documents `01`, `02` et `03`.

## 1. Déploiement retenu : Airbyte Cloud

Le kit du cours prévoit Airbyte Open Source, déployé localement avec `abctl` dans un
Kubernetes-in-Docker — Airbyte n'étant plus distribué officiellement en Docker Compose.

**Le projet utilise Airbyte Cloud.** Les ressources du poste ne permettent pas d'exécuter
confortablement un cluster local en plus de la stack Compose, qui demande déjà 8 Go de RAM
au minimum pour Airbyte seul. L'orchestration part donc dans le cloud, et l'entrepôt
PostgreSQL également, sur **Neon**. Le poste n'exécute plus que les services sources et le
stockage RAW.

| Élément | Kit du cours | Ce projet |
|---|---|---|
| Orchestration | `abctl` local, `http://localhost:8000` | Airbyte Cloud |
| Entrepôt | PostgreSQL du Compose, port 5432 | Neon PostgreSQL |
| Sources locales | PostgreSQL, MariaDB, EspoCRM, MinIO, Adminer | identiques, via Docker Compose |
| Accès aux services locaux | réseau Docker | Quick Tunnel Cloudflare et tunnel SSH inversé |

Ce qui ne change pas : la convention RAW → Bronze → Silver, les schémas `bronze` et
`silver`, les scripts SQL versionnés et les contrôles.

### 1.1 Pour mémoire — déploiement local avec abctl

```bash
abctl version
abctl local install
abctl local credentials
```

Airbyte est alors accessible sur `http://localhost:8000`.

## 2. Le piège de `localhost`

Depuis un connecteur Airbyte, `localhost` désigne le conteneur du connecteur, pas la machine
hôte.

| Contexte | Hôte à utiliser |
|---|---|
| `abctl` local, Windows ou macOS | tester `host.docker.internal` avec les ports exposés (5432, 3306, 9000) |
| `abctl` local, Linux | si `host.docker.internal` ne résout pas, utiliser l'adresse de passerelle Docker du nœud kind, et la documenter |
| **Airbyte Cloud** | aucun nom d'hôte local n'est joignable : il faut un tunnel |

Sous Linux, la passerelle se relève ainsi :

```bash
NODE=$(docker ps --filter name=airbyte-abctl-control-plane --format '{{.Names}}' | head -n 1)
docker inspect "$NODE" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
```

Avec Airbyte Cloud, deux mécanismes d'exposition contrôlée sont mis en place :

- [`10-reseau-minio-cloudflare.md`](./10-reseau-minio-cloudflare.md) pour MinIO ;
- [`11-reseau-tunnel-ssh-mariadb.md`](./11-reseau-tunnel-ssh-mariadb.md) pour MariaDB.

## 3. Inventaire des objets

### 3.1 Sources et destinations

| Objet | Type et version | Flux | Rôle |
|---|---|---|---|
| `api_openalex` | Source · connecteur déclaratif (Builder) | A | Interroge `works`, `authors`, `institutions` |
| `csv_openalex` | Source · File v0.6.1 | B | Télécharge le CSV en HTTPS |
| `espocrm` | Source · MySQL v3.53.10 | C | Lit MariaDB via le tunnel SSH |
| `minio_raw_source` | Source · S3 | A et B | Relit les lots RAW |
| `minio_raw_destination` | Destination · S3 v1.9.11 | A et B | Dépose les lots en JSON Lines |
| `neon_postgres` | Destination · PostgreSQL | A, B, C | Charge le schéma `bronze` |

### 3.2 Connexions

| Connexion | Source → destination | Mode | Fréquence |
|---|---|---|---|
| `api_openalex → minio_raw` | `api_openalex` → `minio_raw_destination` | Full Refresh / Overwrite | Manuelle |
| `csv_openalex → minio_csv_raw` | `csv_openalex` → `minio_raw_destination` | Full Refresh / Overwrite | Manuelle |
| `minio_raw → neon_postgres` | `minio_raw_source` → `neon_postgres` | Full Refresh / Append | Manuelle |
| `espocrm → neon_postgres` | `espocrm` → `neon_postgres` | Incrémental avec curseur | Manuelle |

Les quatre connexions étaient au vert lors du relevé du 13/11/2026.

> **Fréquence manuelle, assumée.** Pour le périmètre du projet, le déclenchement à la main
> garantit que chaque lot est lancé, observé et documenté. Une planification relèverait
> d'une mise en production, avec la supervision et les alertes correspondantes.

### 3.3 Tables Bronze produites

```text
bronze.api_works                     bronze.espocrm_account
bronze.api_authors                   bronze.espocrm_contact
bronze.api_institutions              bronze.espocrm_opportunity
bronze.csv_paper_citation            bronze.espocrm_contact_opportunity
```

## 4. Modes de synchronisation

| Mode | Où | Ce qu'il implique |
|---|---|---|
| Full Refresh / Overwrite | vers MinIO | Chaque synchronisation écrit un nouvel objet daté ; aucun lot historique n'est écrasé. |
| Full Refresh / Append | MinIO → Bronze | Les lots s'ajoutent. Les doublons sont quantifiés en Bronze et éliminés en Silver. |
| Incrémental avec curseur | MariaDB → Bronze | Seules les lignes dont le curseur a progressé sont relues. |

`Append` ne dédoublonne pas : rejouer un lot charge deux fois les mêmes identifiants. C'est
assumé, puisque Silver applique un dédoublonnage déterministe par clé sur
`_airbyte_extracted_at`. La source S3 doit lire le préfixe du lot attendu, et non tout le
bucket.

## 5. Qualification du flux MinIO → PostgreSQL

Le connecteur **Source S3** valide en HTTPS les endpoints personnalisés. Un MinIO de
développement qui expose son API en HTTP peut donc être refusé, même s'il fonctionne. C'est
le Quick Tunnel Cloudflare, dont le certificat est reconnu, qui satisfait cette validation.

Le simple démarrage des conteneurs ne vaut pas qualification. Sont exigés : la version
exacte du connecteur, la preuve d'un **Test connection** réussi, puis celle d'une
synchronisation complète vers PostgreSQL.

## 6. Preuves à conserver

Pour chaque connexion : capture de la configuration, nom de la source et de la destination,
streams sélectionnés, mode de synchronisation, test de connexion réussi, job réussi, volumes
chargés, erreurs rencontrées et leur résolution.

Pour MinIO : bucket, clé objet, taille, date, manifeste et SHA-256 du lot.

Pour le CRM : volumes relevés avant la saisie, entités créées avec leurs identifiants,
volumes après synchronisation, et requête retrouvant ces identifiants en Bronze.

Chaque capture est accompagnée d'une phrase expliquant ce qu'elle prouve — c'est une
exigence explicite du sujet. Une capture ne vaut jamais test : un test est une requête SQL,
son résultat et son interprétation.

## 7. Sécurité

Ne jamais versionner `.env`, un mot de passe, un token, un cookie ou une clé d'accès réelle.
Le dépôt ne contient que `.env.example` et des captures masquées.

Dans tout document rendu, sont masqués : l'adresse IP publique de la VM relais, l'URL réelle
du Quick Tunnel, les clés d'accès MinIO, la clé API OpenAlex, le contenu des clés SSH et les
coordonnées personnelles figurant dans les captures du CRM.

Les secrets vivent dans le gestionnaire de secrets d'Airbyte Cloud, jamais dans une URL, un
fichier Markdown ou une capture.
