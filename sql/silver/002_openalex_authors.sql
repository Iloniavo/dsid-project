-- Transformation Silver du stream OpenAlex Authors.
-- Les propriétés sont extraites de la colonne JSONB Airbyte.
-- Les doublons sont dédoublonnés par identifiant source en conservant le
-- dernier enregistrement extrait. Les lignes sans identifiant, avec un nombre
-- de travaux absent ou inférieur à 10, avec des citations négatives, ou sans
-- date d'ingestion restent en Bronze et sont exclues de Silver.
-- `id` vient de `_airbyte_data.id`. `source_record_id` conserve
-- `_airbyte_raw_id`, l'identifiant technique Airbyte.

CREATE OR REPLACE VIEW silver.openalex_author AS
WITH typed AS (
SELECT
    _airbyte_raw_id::TEXT AS source_record_id,
    NULLIF(TRIM(_airbyte_data ->> 'id'), '') AS id,
    NULLIF(TRIM(_airbyte_data ->> 'orcid'), '') AS orcid,
    NULLIF(TRIM(_airbyte_data ->> 'display_name'), '') AS display_name,
    NULLIF(TRIM(_airbyte_data ->> 'full_name'), '') AS full_name,
    NULLIF(TRIM(_airbyte_data ->> 'works_count'), '')::BIGINT AS works_count,
    NULLIF(TRIM(_airbyte_data ->> 'cited_by_count'), '')::BIGINT
        AS cited_by_count,
    _airbyte_data -> 'summary_stats' AS summary_stats,
    _airbyte_data -> 'ids' AS ids,
    _airbyte_data -> 'affiliations' AS affiliations,
    _airbyte_data -> 'last_known_institutions' AS last_known_institutions,
    _airbyte_data -> 'topics' AS topics,
    _airbyte_data -> 'counts_by_year' AS counts_by_year,
    NULLIF(TRIM(_airbyte_data ->> 'updated_date'), '')::TIMESTAMPTZ
        AS updated_at,
    NULLIF(TRIM(_airbyte_data ->> 'created_date'), '')::TIMESTAMPTZ
        AS created_at,
    _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at,
    _airbyte_data AS source_payload
FROM bronze.api_authors
), ranked AS (
    SELECT
        typed.*,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY extracted_at DESC NULLS LAST, source_payload::TEXT DESC
        ) AS row_number
    FROM typed
    WHERE id IS NOT NULL
), eligible AS (
    SELECT *
    FROM ranked
    WHERE row_number = 1
      AND works_count > 10
      AND COALESCE(cited_by_count, 0) >= 0
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    orcid,
    display_name,
    full_name,
    works_count,
    cited_by_count,
    summary_stats,
    ids,
    affiliations,
    last_known_institutions,
    topics,
    counts_by_year,
    updated_at,
    created_at,
    'openalex'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
