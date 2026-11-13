-- Transformation Silver du stream OpenAlex Works.
-- Les propriétés sont extraites de la colonne JSONB Airbyte.
-- Les doublons sont dédoublonnés par identifiant source en conservant le
-- dernier enregistrement extrait. Les lignes sans identifiant, sans titre,
-- hors année 2026 ou sans date d'ingestion restent en Bronze et sont exclues
-- de Silver. Ces exclusions sont comptées dans les contrôles de réconciliation.
-- `id` vient de `_airbyte_data.id`. `source_record_id` conserve
-- `_airbyte_raw_id`, l'identifiant technique Airbyte.

CREATE OR REPLACE VIEW silver.openalex_work AS
WITH typed AS (
SELECT
    _airbyte_raw_id::TEXT AS source_record_id,
    NULLIF(TRIM(_airbyte_data ->> 'id'), '') AS id,
    NULLIF(TRIM(_airbyte_data ->> 'doi'), '') AS doi,
    NULLIF(TRIM(_airbyte_data ->> 'title'), '') AS title,
    NULLIF(TRIM(_airbyte_data ->> 'publication_year'), '')::INTEGER
        AS publication_year,
    NULLIF(TRIM(_airbyte_data ->> 'publication_date'), '')::DATE
        AS publication_date,
    NULLIF(TRIM(_airbyte_data ->> 'type'), '') AS work_type,
    NULLIF(TRIM(_airbyte_data ->> 'cited_by_count'), '')::BIGINT
        AS cited_by_count,
    NULLIF(TRIM(_airbyte_data ->> 'language'), '') AS language,
    _airbyte_data -> 'primary_location' AS primary_location,
    _airbyte_data -> 'topics' AS topics,
    _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at,
    _airbyte_data AS source_payload
FROM bronze.api_works
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
      AND title IS NOT NULL
      AND publication_year = 2026
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    doi,
    title,
    publication_year,
    publication_date,
    work_type,
    cited_by_count,
    language,
    primary_location,
    topics,
    'openalex'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
