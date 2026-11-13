---
document : Flux A — API publique OpenAlex
flux : A
chemin : API OpenAlex → Airbyte → MinIO RAW → Airbyte → Bronze → Silver
mise_a_jour : 2026-11-13
---

# Flux A — API publique OpenAlex

> Premier des trois chemins d'ingestion. OpenAlex expose par `GET` les métadonnées de la
> recherche scientifique. Les réponses sont déposées telles quelles dans MinIO, relues par
> Airbyte, chargées en Bronze puis standardisées en Silver.

```text
API OpenAlex → Airbyte (Builder) → MinIO RAW → Airbyte (S3) → Neon / bronze → Neon / silver
```

## 1. Objectif et périmètre

La collecte porte sur trois ressources, chacune avec un grain distinct.

| Stream | Endpoint | Grain | Clé source |
|---|---|---|---|
| Works | `/works` | Une publication scientifique | `id` |
| Authors | `/authors` | Un auteur | `id` |
| Institutions | `/institutions` | Une institution | `id` |

API de base : `https://api.openalex.org/` — méthode `GET`.

Les identifiants OpenAlex sont des URI textuelles. Ils restent en `text` et ne sont jamais
convertis en nombres.

## 2. Contrat de données

### 2.1 Réponse aux huit critères de cadrage

| Critère | Décision retenue |
|---|---|
| Objet métier | Métadonnées de la recherche : publications, auteurs, institutions. |
| URL `GET` | `/works`, `/authors` et `/institutions`, avec le paramètre `filter` selon le stream. |
| Grain | Une publication, un auteur ou une institution ; les objets imbriqués restent rattachés à leur enregistrement. |
| Clé | Le champ `id`, conservé en texte. |
| Pagination et complétude | La réponse porte `meta.count` et `results`. L'extraction est complète lorsque le volume reçu est rapproché de `meta.count` et que la pagination s'arrête sans erreur : dernière page, ou `next_cursor` absent. |
| Types | Identifiants et textes en `TEXT`, `publication_date` en `DATE`, compteurs en `BIGINT`, objets imbriqués en `JSONB` (§2.4). |
| Fraîcheur | Une synchronisation hebdomadaire suffit pour ce projet. Une extraction ponctuelle peut être relancée avant une analyse ; les lots sont datés dans MinIO. |
| Limites | 100 résultats par page au maximum, curseur obligatoire au-delà de 10 000 résultats, temporisation sur une réponse `429`, budget quotidien lié à la clé API. |

### 2.2 Authentification

OpenAlex autorise l'accès sans clé pour un usage limité. Le projet utilise une clé API afin
d'augmenter le budget quotidien et de suivre la consommation. Elle est transmise en en-tête
HTTP selon le schéma Bearer.

| Paramètre Airbyte | Valeur |
|---|---|
| Type | Header |
| Nom | `Authorization` |
| Valeur | `Bearer` suivi de la clé, référencée par `{{ config['api_key'] }}` |

La clé est stockée dans le gestionnaire de secrets d'Airbyte. Elle n'apparaît ni dans l'URL,
ni dans les captures, ni dans le dépôt, ni dans le rapport. La variante `?api_key=` acceptée
par OpenAlex est écartée : les URL se retrouvent dans les journaux.

Test local, avec la clé en variable d'environnement :

```powershell
$headers = @{ Authorization = $env:OPENALEX_AUTHORIZATION }
Invoke-RestMethod `
  -Uri "https://api.openalex.org/works?filter=publication_year:2026&per-page=1" `
  -Headers $headers
```

En cas d'exposition, la clé est révoquée et remplacée depuis l'espace OpenAlex.

### 2.3 Filtres et justification

Une collecte complète d'OpenAlex dépasse les ressources du projet : le free tier limite le
nombre d'appels et la capacité de traitement. Les filtres réduisent le volume tout en
gardant un jeu exploitable et reproductible.

| Stream | Filtre | Justification |
|---|---|---|
| Works | `publication_year:2026` | Limiter à l'année étudiée et maîtriser le volume. |
| Authors | `works_count:>10` | Conserver les auteurs à l'activité significative. Le `>` est encodé `%3E` si le connecteur l'exige. |
| Institutions | aucun | Le référentiel complet est chargé ; un filtre géographique reste possible si le volume devient contraignant. |

Les filtres ne remplacent pas les contrôles : ils sont eux-mêmes vérifiés après chargement
(§6).

### 2.4 Champs retenus et contrat de types

| Stream | Identifiants | Textes | Dates | Nombres | JSONB |
|---|---|---|---|---|---|
| Works | `id`, `doi` | `title`, `type`, `language` | `publication_date` → `DATE` | `publication_year` → `INTEGER` · `cited_by_count` → `BIGINT` | `primary_location`, `authorships`, `topics` |
| Authors | `id`, `orcid` | `display_name`, `full_name` | `updated_date`, `created_date` → `TIMESTAMPTZ` | `works_count`, `cited_by_count` → `BIGINT` | `summary_stats`, `ids`, `affiliations`, `last_known_institutions`, `topics`, `counts_by_year` |
| Institutions | `id`, `ror` | `display_name`, `country_code`, `type`, `homepage_url` | — | `works_count`, `cited_by_count` → `BIGINT` | — |

Les objets imbriqués restent en `JSONB` : cette décision évite un aplatissement silencieux
et permet de créer des tables de relation quand les analyses le réclament. Une valeur vide
devient `NULL` uniquement en Silver, par `NULLIF(TRIM(...), '')`. Une date ou un nombre
malformé est signalé par les contrôles, jamais corrigé en silence. Les champs non listés
ci-dessus ne sont pas retenus.

### 2.5 Pagination

| Stratégie | Usage | Forme |
|---|---|---|
| Pagination classique | volume inférieur ou égal à 10 000 | `?page=1&per-page=100` |
| Pagination par curseur | au-delà de 10 000, recommandée par OpenAlex | `?per-page=100&cursor=*` puis `cursor=<next_cursor>` |

La stratégie retenue est la suivante : estimer le volume avec `meta.count`, utiliser le
curseur dès que le seuil est franchi, arrêter la collecte quand `next_cursor` disparaît, et
consigner le filtre, la stratégie, le nombre de pages, le dernier curseur, le volume reçu et
le volume chargé.

## 3. Configuration Airbyte

Le manifeste de la source est versionné dans
[`data/manifests/api_openalex_builder.yaml`](../data/manifests/api_openalex_builder.yaml).

### 3.1 Objets

| Objet | Type et version | Rôle |
|---|---|---|
| `api_openalex` | Source · connecteur déclaratif (Builder) | Interroge `works`, `authors` et `institutions`. |
| `minio_raw_destination` | Destination · S3 v1.9.11 | Dépose les réponses au format JSON Lines dans MinIO. |
| `minio_raw_source` | Source · S3 | Relit les lots RAW du bucket `dsidraw`. |
| `neon_postgres` | Destination · PostgreSQL | Charge le schéma `bronze` de la base Neon `api_openalex`. |

### 3.2 Connexions et modes

| Connexion | Mode | Fréquence | Justification |
|---|---|---|---|
| `api_openalex → minio_raw` | Full Refresh / Overwrite | Manuelle | Chaque synchronisation écrit un nouvel objet daté : aucun lot historique n'est écrasé. |
| `minio_raw → neon_postgres` | Full Refresh / Append | Manuelle | Chaque lot est ajouté à Bronze. Les doublons sont quantifiés en Bronze puis éliminés en Silver. |

`Append` ne dédoublonne pas : rejouer un lot charge deux fois les mêmes identifiants. Ce
comportement est assumé, puisque Silver applique un dédoublonnage déterministe par `id` sur
`_airbyte_extracted_at`. `minio_raw_source` doit donc lire le préfixe du lot attendu, et non
tout le bucket.

### 3.3 Streams

```yaml
# extrait du manifeste — stream works
requester:
  url: https://api.openalex.org/works
  http_method: GET
  request_parameters:
    cursor: "{{ next_page_token['next_page_token'] if next_page_token else '*' }}"
    filter: publication_year:2026
paginator:
  pagination_strategy:
    type: CursorPagination
    page_size: 100
    cursor_value: "{{ response['meta']['next_cursor'] }}"
    stop_condition: "{{ not response.get('meta', {}).get('next_cursor') }}"
record_selector:
  extractor: { type: DpathExtractor, field_path: [results] }
primary_key: id
```

La sélection des propriétés se fait dans le schéma du stream, et non par un aplatissement
manuel des objets imbriqués.

## 4. Zone RAW et couche Bronze

### 4.1 Arborescence RAW observée

```text
s3://dsidraw/api/api_works/<AAAA_MM_JJ>_<horodatage>_<n>.jsonl
s3://dsidraw/api/api_authors/<AAAA_MM_JJ>_<horodatage>_<n>.jsonl
s3://dsidraw/api/api_institutions/<AAAA_MM_JJ>_<horodatage>_<n>.jsonl
```

> **Écart assumé avec la convention du sujet.** Le sujet recommande
> `s3://dsid-raw/raw/api/<source>/extraction_date=YYYY-MM-DD/<lot>.jsonl`. L'implémentation
> utilise le bucket `dsidraw`, le préfixe `api/<stream>/` et le nom d'objet généré par le
> connecteur S3, par exemple `2026_11_11_1794359619080_0.jsonl`. La date du lot reste
> présente, dans le nom de l'objet plutôt que dans une partition. L'historique est donc
> conservé et chaque lot reste identifiable ; seul le filtrage par partition est moins
> direct. La nomenclature réelle est documentée telle quelle plutôt que corrigée après coup.

Le bucket `dsidraw` est privé, créé le 10/11/2026, et contient 11 objets pour 1,0 Gio. Le
fichier original, sa taille, sa date et son SHA-256 doivent être conservés ; aucune
correction de contenu n'est faite avant le dépôt.

### 4.2 Tables Bronze

```text
bronze.api_works
bronze.api_authors
bronze.api_institutions
```

Le payload reçu reste dans la colonne `JSONB` `_airbyte_data`, à côté des colonnes
techniques Airbyte.

## 5. Couche Silver

### 5.1 Vues et scripts

| Script | Vue | Règles d'éligibilité |
|---|---|---|
| [`001_openalex_works.sql`](../sql/silver/001_openalex_works.sql) | `silver.openalex_work` | titre présent · `publication_year = 2026` · timestamp présent |
| [`002_openalex_authors.sql`](../sql/silver/002_openalex_authors.sql) | `silver.openalex_author` | `works_count > 10` · compteurs valides · timestamp présent |
| [`003_openalex_institutions.sql`](../sql/silver/003_openalex_institutions.sql) | `silver.openalex_institution` | compteurs positifs · `country_code` ISO |
| [`004_openalex_reconciliation.sql`](../sql/silver/004_openalex_reconciliation.sql) | `silver.v_openalex_reconciliation` | comptage Bronze, valides, distincts, Silver |
| [`005_openalex_work_author.sql`](../sql/silver/005_openalex_work_author.sql) | `silver.openalex_work_author` | relation publication ↔ auteur |
| [`006_openalex_author_institution.sql`](../sql/silver/006_openalex_author_institution.sql) | `silver.openalex_author_institution` | relation auteur ↔ institution |

Chaque vue porte `id`, `source_record_id`, `source_system` et `ingested_at_utc` :

```text
id               <- _airbyte_data ->> 'id'
source_record_id <- _airbyte_raw_id
source_system    <- 'openalex'
ingested_at_utc  <- _airbyte_extracted_at
```

La déduplication conserve la ligne dont `_airbyte_extracted_at` est le plus récent pour un
`id` donné. Les lignes sans identifiant restent consultables en Bronze et sont exclues de
Silver.

### 5.2 Vue de liaison `silver.openalex_work_author`

Relation plusieurs-à-plusieurs entre une publication et ses auteurs. Une publication produit
donc plusieurs lignes.

| Colonne | Signification | Source |
|---|---|---|
| `id` | Identifiant stable de la relation | dérivé de `work_id`, `author_id` et `author_position` |
| `source_record_id` | Identifiant technique de la ligne | dérivé : la relation n'a pas de `_airbyte_raw_id` propre |
| `work_id` | Publication | `silver.openalex_work.id` |
| `author_id` | Auteur | `works.authorships[].author.id` |
| `author_position` | Rang de l'auteur | ordre du tableau `authorships`, à partir de 1 |
| `is_corresponding` | Auteur correspondant | `authorships[].is_corresponding`, `FALSE` par défaut |
| `author_present_in_silver` | Auteur chargé en Silver | `TRUE` si `author_id` existe dans `silver.openalex_author` |
| `author_status` | Explication de l'absence | `registered` ou `known_by_openalex_not_loaded` |

### 5.3 Vue de liaison `silver.openalex_author_institution`

| Colonne | Signification | Source |
|---|---|---|
| `id` | Identifiant stable de la relation | dérivé de l'auteur, de l'institution, du type et de la position |
| `source_record_id` | Identifiant technique de la ligne | dérivé |
| `author_id` | Auteur | `silver.openalex_author.id` |
| `institution_id` | Institution | `last_known_institutions[].id` ou `affiliations[].institution.id` |
| `affiliation_position` | Rang de l'affiliation | ordre du tableau `affiliations` ; `NULL` pour `last_known_institutions` |
| `relationship_type` | Origine de la relation | `affiliation` ou `last_known_institution` |
| `institution_present_in_silver` | Institution chargée en Silver | `TRUE` si `institution_id` existe dans `silver.openalex_institution` |
| `institution_status` | Explication de l'absence | `registered` ou `known_by_openalex_not_loaded` |

`known_by_openalex_not_loaded` signifie que l'identifiant est bien référencé par OpenAlex
mais que l'entité n'est pas dans le périmètre Silver chargé — par exemple un auteur qui ne
respecte pas `works_count > 10`. Ce n'est pas un identifiant invalide : l'entité est
conservée avec un statut explicite plutôt que supprimée en silence.

`authorships` reste disponible en Bronze mais n'est plus exposé dans `silver.openalex_work`.
Les vues utilisent des clés logiques ; de vraies contraintes `FOREIGN KEY` demanderaient de
matérialiser les tables.

## 6. Contrôles et résultats

Les scripts sont versionnés :
[`001_openalex_checks.sql`](../sql/tests/001_openalex_checks.sql) pour Bronze et
[`002_openalex_silver_checks.sql`](../sql/tests/002_openalex_silver_checks.sql) pour Silver.
Ils sont lancés par [`preuves/run_tests.ps1`](../preuves/run_tests.ps1), qui écrit chaque
sortie dans `preuves/logs/`.

### 6.1 Volumes mesurés le 13/11/2026

| Objet | Bronze | Silver | Écart |
|---|---:|---:|---:|
| `api_works` → `openalex_work` | 70 671 | 70 670 | 1 ligne écartée par une règle métier |
| `api_authors` → `openalex_author` | 12 916 | 12 916 | 0 |
| `api_institutions` → `openalex_institution` | 145 454 | 145 454 | 0 |
| `openalex_work_author` | — | 542 172 | — |
| `openalex_author_institution` | — | 781 655 | — |

Parmi les 542 172 relations publication ↔ auteur, 531 679 pointent vers un auteur absent de
Silver du fait du filtre `works_count > 10` : elles portent le statut
`known_by_openalex_not_loaded`.

### 6.2 Résultats des contrôles

Les 46 contrôles des deux scripts retournent `0`, à une exception près.

| Contrôle | Résultat | Lecture |
|---|---:|---|
| Clés Bronze nulles et dupliquées, colonnes `_airbyte_*` | 0 | Bronze conforme. |
| Clés Silver nulles, unicité, règles métier, traçabilité | 0 | Silver conforme sur les trois vues principales. |
| `work_author_duplicate_relation` | **1 586** | Écart. La vue est au grain `(work_id, author_id, author_position)` ; le contrôle teste `(work_id, author_id)`. L'expansion du tableau `authorships` produit une ligne par position, et OpenAlex liste parfois le même auteur à deux positions. La clé de la vue reste unique. |
| Réconciliation Bronze ↔ Silver | résidu 0 | L'unique ligne absente est expliquée par une règle métier. |

> **Correctif à trancher.** Soit aligner le contrôle sur le grain déclaré, soit décider que
> le grain est `(work_id, author_id)` et ne conserver que la position la plus faible. Le
> choix dépend de l'usage visé.

### 6.3 Couverture restante

Les deux vues de liaison ne figurent pas dans `v_openalex_reconciliation` et leur
traçabilité n'est pas testée. Leur nommage et leurs types sont couverts par
[`005_volumes_bronze_silver.sql`](../sql/tests/005_volumes_bronze_silver.sql).

## 7. Limites, sécurité et preuves

- Endpoints publics uniquement ; `per-page` plafonné à 100.
- Sans clé, l'accès vise un usage ponctuel. Une clé gratuite multiplie le budget quotidien
  par dix et sert la pagination par curseur au-delà de la première page.
- Les réponses `429` imposent de ralentir puis de reprendre, jamais de boucler.
- Les filtres `from_publication_date` et `from_updated_date` ne font plus partie du free
  tier : l'extraction incrémentale côté API n'est pas disponible.
- Les données OpenAlex sont publiées sous CC0. Les textes reçus restent des données externes,
  à traiter comme non fiables à l'affichage.
- Aucun secret dans le dépôt, les captures ou le rapport.

Preuves à conserver : URL et filtre par stream, stratégie de pagination, date et heure de
collecte, `meta.count`, nombre de pages ou de curseurs, volumes RAW, Bronze et Silver,
nombre de doublons, sorties des contrôles, incidents rencontrés et leur résolution.

## 8. Documentation OpenAlex

Consultée le 2026-11-12.

- [API overview](https://help.openalex.org/api/) — fonctionnement général et format des réponses
- [Authentication](https://help.openalex.org/api/authentication/) — création et transmission de la clé
- [API endpoints](https://help.openalex.org/api/endpoints/) — liste des ressources
- [Filtering](https://help.openalex.org/api/filtering/) — syntaxe des filtres
- [Paging](https://help.openalex.org/api/paging/) — pagination classique et par curseur
- [Selecting fields](https://help.openalex.org/api/selecting-fields/) — sélection des propriétés
- [Data reference](https://help.openalex.org/data/) — définition des champs et identifiants
- [OpenAPI specification](https://help.openalex.org/openapi.json) — spécification des endpoints
- [Rate limits and usage](https://openalex.org/settings/usage) — suivi de la consommation
