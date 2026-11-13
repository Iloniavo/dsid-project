# Starter — Projet Big Data M1 MIAGE 2026-2027

Ce dossier fournit une base technique. Il ne réalise pas le projet à votre place.

## Pipeline attendu

1. API publique GET → Airbyte → MinIO → Airbyte S3 Source → PostgreSQL `bronze`.
2. CSV accessible à Airbyte → Airbyte → MinIO → Airbyte S3 Source → PostgreSQL `bronze`.
3. Nouvelles données saisies dans EspoCRM → MariaDB → Airbyte MySQL Source → PostgreSQL `bronze`.
4. SQL versionné → PostgreSQL `silver`.
5. Tests de structure, types, unicité, doublons, volumes et traçabilité.

Pour la partie API, le contrat OpenAlex et les trois streams utilisés (`works`, `authors` et `institutions`) sont documentés dans `airbyte/openalex.md`.

Consultez `README_DOCKER.md` pour l'installation et `sql/` pour les modèles de contrôle.

L'architecture hybride détaillée est décrite dans
[ARCHITECTURE.md](ARCHITECTURE.md).

Le deuxième chemin d'ingestion, basé sur le fichier CSV Kaggle, est documenté
dans [airbyte/csv_openalex.md](airbyte/csv_openalex.md).

Le troisième chemin d'ingestion, basé sur EspoCRM/MariaDB, est documenté dans
[airbyte/espocrm.md](airbyte/espocrm.md).

La mise à disposition temporaire de MinIO local pour Airbyte via Cloudflare
est documentée dans
[airbyte/minio-cloudflare.md](airbyte/minio-cloudflare.md).

## Bronze/Silver

Les tables Bronze utilisées par ce projet sont `bronze.api_works`,
`bronze.api_authors` et `bronze.api_institutions`. Elles restent fidèles au
JSON reçu par Airbyte et ne sont jamais mises à jour pour corriger une donnée.

Silver est exposée par les vues `sql/silver/001_*.sql` à `003_*.sql`. Chaque
vue standardise les noms et les types, conserve `id`, `source_record_id`,
`source_system` et `ingested_at_utc`, puis dédoublonne de façon déterministe
par identifiant source et `_airbyte_extracted_at` décroissant. Les lignes sans
clé restent consultables en Bronze et les lignes écartées sont mesurées par
les contrôles de réconciliation. La vue
`sql/silver/004_openalex_reconciliation.sql` compare les clés distinctes
éligibles aux lignes Silver et explique les écarts par les doublons, les clés
nulles, les règles métier et la provenance incomplète. Aucun rapprochement
entre sources n'est réalisé à ce stade.
