---
document : Flux B — Fichier CSV OpenAlex
flux : B
chemin : CSV Kaggle → Airbyte → MinIO RAW → Airbyte → Bronze → Silver
mise_a_jour : 2026-11-13
---

# Flux B — Fichier CSV OpenAlex

> Deuxième chemin d'ingestion. Un fichier CSV de métadonnées bibliographiques dérivé
> d'OpenAlex est téléchargé en HTTPS, conservé tel quel dans MinIO, chargé en Bronze puis
> standardisé en Silver.

```text
CSV Kaggle → Airbyte (File) → MinIO RAW → Airbyte (S3) → Neon / bronze → Neon / silver
```

Contrairement au flux A, le fichier est **déjà aplati** : auteurs, mots-clés et institutions
y figurent sous forme de chaînes de caractères.

## 1. Objectif et périmètre

Fichier contrôlé : `Cited Paper Meta Data (csv).csv`, **9 966 lignes** de données et
**33 colonnes**, avec une ligne d'en-tête. Contrôle local effectué le 2026-11-12.

## 2. Contrat de données

### 2.1 Source et licence

URL HTTPS utilisée par le connecteur File :

```text
https://www.kaggle.com/api/v1/datasets/download/utkarshjain76/research-paper-citation-metadata/Cited%20Paper%20Meta%20Data%20%28csv%29.csv
```

Cette URL de téléchargement direct est préférable à l'URL de la page du jeu de données :
elle renvoie le fichier lui-même et ne dépend pas de l'interface web.

Page du jeu : `https://www.kaggle.com/datasets/utkarshjain76/research-paper-citation-metadata`

| Élément | Valeur |
|---|---|
| Jeu de données | *research-paper-citation-metadata*, publié par Utkarsh Jain |
| Licence Kaggle | **MIT** — réutilisation autorisée en conservant la notice |
| Licence des données sources | **CC0** (OpenAlex) |
| Contenus tiers référencés | conditions propres, à respecter séparément |

### 2.2 Contrat du fichier

| Élément | Valeur retenue |
|---|---|
| Format | CSV |
| Séparateur | Virgule `,` |
| Encadrement des champs | Guillemets doubles dès qu'un champ contient une virgule |
| Décimales | Point `.` |
| Ligne d'en-tête | Oui, noms déjà en `snake_case` |
| Encodage | UTF-8, aucun BOM détecté |
| Fin de ligne | `CRLF` ou `LF` acceptés |
| Grain | Une ligne par publication scientifique |
| Clé | `paper_id` |

`abstract`, `authors`, `keywords` et `title_abstract_text` contiennent des virgules : un
découpage naïf est incorrect. Les valeurs vides sont conservées telles quelles en Bronze ;
la conversion en `NULL`, le nettoyage et les casts appartiennent à Silver.

### 2.3 Clé

`paper_id` porte un identifiant OpenAlex textuel, par exemple
`https://openalex.org/W1901616594`. `doi` est complémentaire et ne remplace pas `paper_id` :
il peut être absent ou varier selon les normalisations de source.

### 2.4 Contrat des colonnes

| Colonne | Type Silver | Signification |
|---|---|---|
| `paper_id` | `TEXT` | Identifiant OpenAlex ; clé technique |
| `doi` | `TEXT` | DOI lorsqu'il existe |
| `paper_title` | `TEXT` | Titre |
| `abstract` | `TEXT` | Résumé |
| `publication_year` | `INTEGER` | Année de publication |
| `publication_date` | `DATE` | Date de publication |
| `paper_type` | `TEXT` | Type, par exemple `review` ou `preprint` |
| `language` | `TEXT` | Langue |
| `journal` | `TEXT` | Revue ou source éditoriale |
| `publisher` | `TEXT` | Éditeur |
| `source_type` | `TEXT` | Type de source, par exemple `journal` ou `repository` |
| `open_access` | `BOOLEAN` | Accès ouvert ; le CSV fournit `0`/`1` |
| `open_access_status` | `TEXT` | Statut, par exemple `closed` ou `green` |
| `field_of_study` | `TEXT` | Domaine principal |
| `keywords` | `TEXT` | Mots-clés aplatis |
| `number_of_authors` | `INTEGER` | Nombre d'auteurs |
| `authors` | `TEXT` | Noms d'auteurs aplatis |
| `first_author` | `TEXT` | Premier auteur |
| `institution` | `TEXT` | Institutions aplaties |
| `number_of_institutions` | `INTEGER` | Nombre d'institutions |
| `institution_country` | `TEXT` | Pays des institutions |
| `international_collaboration` | `BOOLEAN` | Collaboration internationale ; `0`/`1` |
| `references_count` | `BIGINT` | Nombre de références |
| `citation_count` | `BIGINT` | Nombre de citations |
| `title_length_words` | `INTEGER` | Mots du titre |
| `abstract_length_words` | `INTEGER` | Mots du résumé |
| `keyword_count` | `INTEGER` | Nombre de mots-clés |
| `publication_age` | `INTEGER` | Âge de la publication |
| `citation_count_log` | `NUMERIC` | Log du nombre de citations |
| `references_count_log` | `NUMERIC` | Log du nombre de références |
| `number_of_authors_log` | `NUMERIC` | Log du nombre d'auteurs |
| `title_abstract_text` | `TEXT` | Concaténation titre + résumé |
| `citation_rate_per_year` | `NUMERIC` | Citations rapportées à l'âge |

Les colonnes `*_log`, `title_abstract_text` et `citation_rate_per_year` sont des indicateurs
dérivés **fournis par le dataset**. Elles sont conservées comme reçues en Bronze : leur
formule est une propriété du jeu de données, pas une transformation du projet.

## 3. Configuration Airbyte

### 3.1 Objets

| Objet | Type et version | Rôle |
|---|---|---|
| `csv_openalex` | Source · File (CSV, JSON, Excel, Feather, Parquet) v0.6.1 | Télécharge le fichier en HTTPS ; jeu de données `paper_citation`, d'où le stream `csv_paper_citation` |
| `minio_raw_destination` | Destination · S3 v1.9.11 | Conserve le fichier original dans MinIO |
| `minio_raw_source` | Source · S3 | Relit le lot CSV |
| `neon_postgres` | Destination · PostgreSQL | Charge le schéma `bronze` |

Le fournisseur de stockage de la source est **HTTPS : Public Web** : aucun identifiant
Kaggle n'est nécessaire, l'URL étant publique.

### 3.2 Connexions et modes

| Connexion | Mode | Fréquence | Justification |
|---|---|---|---|
| `csv_openalex → minio_csv_raw` | Full Refresh / Overwrite | Manuelle | Le fichier est déposé comme un nouveau lot RAW daté. |
| `minio_raw → neon_postgres` | Full Refresh / Append | Manuelle | Chaque lot est ajouté à Bronze ; Silver dédoublonne. |

La seconde connexion est partagée avec le flux A : elle doit lire le préfixe du lot CSV
attendu, et non tous les anciens objets. `Append` ne dédoublonne pas — un rejeu réintroduit
les mêmes `paper_id` en Bronze, ce que les contrôles quantifient et que Silver traite.

## 4. Zone RAW et couche Bronze

Le dépôt RAW du flux CSV utilise le bucket **`kagglesources`**, distinct du bucket `dsidraw`
des lots API.

> **Écart assumé avec la convention du sujet.** Le préfixe recommandé était
> `raw/csv/openalex/extraction_date=YYYY-MM-DD/`. La date du lot figure dans le nom de
> l'objet généré par le connecteur S3, non dans une partition. L'historique reste conservé.

Table Bronze : **`bronze.csv_paper_citation`**. Son nom reprend celui du stream Airbyte,
lui-même dérivé du nom de jeu de données `paper_citation`. Le payload est stocké dans
`_airbyte_data`, à côté des colonnes techniques Airbyte.

## 5. Couche Silver

La vue `silver.csv_paper_citation` est créée par
[`007_csv_openalex.sql`](../sql/silver/007_csv_openalex.sql). La sélection répond à trois
objectifs : identifier la publication, décrire son contexte scientifique, mesurer son impact.

| Famille | Colonnes | Apport analytique |
|---|---|---|
| Identité | `id` (← `paper_id`), `source_record_id`, `doi` | Clé logique stable, lien vers Bronze, rapprochement externe |
| Texte | `title`, `abstract` | Analyse textuelle, recherche thématique |
| Temps | `publication_year`, `publication_date`, `publication_age` | Tendances, cohérence année ↔ date, comparaison à ancienneté égale |
| Contexte | `paper_type`, `language`, `journal`, `publisher`, `source_type` | Regroupements par support et origine éditoriale |
| Accès | `open_access`, `open_access_status` | Étude de l'accessibilité |
| Thème | `field_of_study`, `keywords` | Répartition thématique |
| Collaboration | `number_of_authors`, `first_author`, `number_of_institutions`, `institution_country`, `international_collaboration` | Taille des équipes, diversité institutionnelle, géographie |
| Impact | `references_count`, `citation_count`, `citation_rate_per_year` | Mesure bibliométrique, normalisée par l'âge |
| Structure | `title_length_words`, `abstract_length_words`, `keyword_count` | Richesse descriptive |
| Traçabilité | `source_system`, `ingested_at_utc` | Origine et fraîcheur de chaque ligne |

### 5.1 Colonnes volontairement non exposées

`authors` et `institution` sont des listes aplaties : elles n'autorisent aucune jointure
fiable et seront normalisées dans une table dédiée si le besoin apparaît.
`title_abstract_text` est recalculable. Les colonnes `*_log` sont redondantes avec les
colonnes brutes et dépendent d'une méthode statistique à choisir. Toutes restent disponibles
en Bronze.

### 5.2 Dédoublonnage

La règle conserve le dernier enregistrement par `paper_id` selon `_airbyte_extracted_at`,
puis exclut les lignes sans clé, sans titre, sans timestamp, avec un booléen invalide ou un
compteur négatif. Les écarts sont mesurés par
[`008_csv_openalex_reconciliation.sql`](../sql/silver/008_csv_openalex_reconciliation.sql),
qui crée `silver.v_csv_paper_citation_reconciliation`.

## 6. Contrôles et résultats

Script : [`003_csv_openalex_silver_checks.sql`](../sql/tests/003_csv_openalex_silver_checks.sql),
lancé par [`preuves/run_tests.ps1`](../preuves/run_tests.ps1) ; sortie dans `preuves/logs/`.

### 6.1 Volumes mesurés le 13/11/2026

| Étape | Lignes |
|---|---:|
| Fichier source | 9 966 |
| Chargé vers MinIO | 9 966 |
| `bronze.csv_paper_citation` | 9 966 |
| `silver.csv_paper_citation` | 9 966 |
| Doublons, clés nulles, écart Bronze → Silver | 0 |

Le fichier a traversé la chaîne sans perte ni ligne supplémentaire.

### 6.2 Résultats des contrôles

Huit des neuf contrôles retournent `0`.

| Contrôle | Résultat | Lecture |
|---|---:|---|
| Clé nulle, doublon, titre, compteurs, booléens, horodatage, date de publication | 0 | Vue conforme. |
| Réconciliation Bronze ↔ Silver | 0 | Aucun écart. |

## 7. Limites

`authors`, `keywords` et `institution` restent des textes. Ils ne doivent pas être traités
comme des clés étrangères vers les tables du flux A sans règle de rapprochement explicite.
**Aucun rapprochement API ↔ CSV n'est réalisé** en Bronze ni en Silver : il relève du volet
BI de mars 2027.

Aucun mot de passe, token ou credential Kaggle n'est stocké dans le dépôt.
