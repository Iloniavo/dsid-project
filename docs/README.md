---
document : Index de la documentation Airbyte
mise_a_jour : 2026-11-13
---

# Documentation Airbyte

Documentation d'ingestion du Projet Big Data — M1 MIAGE, UE DSID, Université Paris-Saclay.
Trois chemins d'ingestion convergent vers une même convention `RAW → Bronze → Silver`.

```text
Flux A   API OpenAlex → Airbyte → MinIO RAW → Airbyte → bronze → silver
Flux B   CSV Kaggle   → Airbyte → MinIO RAW → Airbyte → bronze → silver
Flux C   EspoCRM → MariaDB → tunnel SSH → Airbyte → bronze → silver
```

## Sommaire

| Document | Contenu |
|---|---|
| [`01-flux-api-openalex.md`](./01-flux-api-openalex.md) | Flux A : contrat de l'API, filtres, pagination, manifeste, zone RAW, vues Silver et vues de liaison |
| [`02-flux-csv-openalex.md`](./02-flux-csv-openalex.md) | Flux B : contrat du fichier, licence, colonnes retenues, dédoublonnage |
| [`03-flux-crm-espocrm.md`](./03-flux-crm-espocrm.md) | Flux C : tables CRM, curseurs incrémentaux, vues Silver, preuve du delta |
| [`10-reseau-minio-cloudflare.md`](./10-reseau-minio-cloudflare.md) | Exposer l'API S3 de MinIO à Airbyte Cloud par un Quick Tunnel |
| [`11-reseau-tunnel-ssh-mariadb.md`](./11-reseau-tunnel-ssh-mariadb.md) | Tunnel SSH inversé entre MariaDB, une VM Oracle et Airbyte Cloud |
| [`20-configuration-airbyte.md`](./20-configuration-airbyte.md) | Déploiement, inventaire des objets, modes de synchronisation, preuves, sécurité |

Les documents `01` à `03` décrivent un flux de bout en bout. Les documents `10` et `11`
traitent de l'accès réseau, commun à plusieurs flux. Le document `20` rassemble ce qui vaut
pour les trois.

## Où trouver le reste

| Sujet | Emplacement |
|---|---|
| Architecture générale du projet | [`../ARCHITECTURE.md`](../ARCHITECTURE.md) |
| Démarrage de la stack locale | [`../README_DOCKER.md`](../README_DOCKER.md) |
| Manifeste de la source API | [`../data/manifests/api_openalex_builder.yaml`](../data/manifests/api_openalex_builder.yaml) |
| Transformations Silver | [`../sql/silver/`](../sql/silver/) |
| Contrôles qualité | [`../sql/tests/`](../sql/tests/) |
| Lanceur des contrôles | [`../preuves/run_tests.ps1`](../preuves/run_tests.ps1) |
| Sorties des contrôles | [`../preuves/logs/`](../preuves/logs/) |
| Rapport final | [`../rapport/`](../rapport/) |

## État actuel

| Flux | Bronze | Silver | Contrôles |
|---|---:|---:|---|
| A — API OpenAlex | 229 041 lignes | 229 040 + 1 323 827 relations | 1 écart, sur le grain de la vue de liaison |
| B — CSV OpenAlex | 9 966 lignes | 9 966 lignes | 1 écart, sur la valeur de `source_system` |
| C — EspoCRM | 53 005 lignes | 32 660 lignes | 27 contrôles au vert ; réconciliation à requalifier |

Les trois écarts proviennent des requêtes de contrôle elles-mêmes, et non des données
chargées. Chacun est détaillé dans le document du flux concerné, avec son correctif.
