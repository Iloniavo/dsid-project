-- Transformation Silver du stream OpenAlex Institutions.
-- Les propriétés sont extraites de la colonne JSONB Airbyte.
-- Les doublons sont dédoublonnés par identifiant source en conservant le
-- dernier enregistrement extrait. Les lignes sans identifiant, avec des
-- compteurs négatifs, un code pays invalide ou sans date d'ingestion restent
-- en Bronze et sont exclues de Silver.
-- `id` vient de `_airbyte_data.id`. `source_record_id` conserve
-- `_airbyte_raw_id`, l'identifiant technique Airbyte.

CREATE OR REPLACE VIEW silver.openalex_institution AS
WITH typed AS (
SELECT
    _airbyte_raw_id::TEXT AS source_record_id,
    NULLIF(TRIM(_airbyte_data ->> 'id'), '') AS id,
    NULLIF(TRIM(_airbyte_data ->> 'ror'), '') AS ror,
    NULLIF(TRIM(_airbyte_data ->> 'display_name'), '') AS display_name,
    NULLIF(TRIM(_airbyte_data ->> 'country_code'), '') AS country_code,
    NULLIF(TRIM(_airbyte_data ->> 'type'), '') AS institution_type,
    NULLIF(TRIM(_airbyte_data ->> 'homepage_url'), '') AS homepage_url,
    NULLIF(TRIM(_airbyte_data ->> 'works_count'), '')::BIGINT AS works_count,
    NULLIF(TRIM(_airbyte_data ->> 'cited_by_count'), '')::BIGINT
        AS cited_by_count,
    _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at,
    _airbyte_data AS source_payload
FROM bronze.api_institutions
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
      AND COALESCE(works_count, 0) >= 0
      AND COALESCE(cited_by_count, 0) >= 0
      AND (
          country_code IS NULL
          OR country_code ~ '^[A-Z]{2}$'
      )
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    ror,
    display_name,
    country_code,
    institution_type,
    homepage_url,
    works_count,
    cited_by_count,
    'openalex'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
