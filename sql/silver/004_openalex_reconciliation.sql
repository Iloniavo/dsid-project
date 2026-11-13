-- Réconciliation Bronze/Silver.
-- `silver_rows` doit être égal à `eligible_distinct_keys`. L'écart avec
-- Bronze est expliqué par les clés nulles, les doublons, les règles métier
-- et les lignes sans timestamp d'ingestion.

CREATE OR REPLACE VIEW silver.v_openalex_reconciliation AS
WITH works_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(*) FILTER (
            WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
        )::BIGINT AS non_null_key_rows,
        COUNT(DISTINCT NULLIF(TRIM(_airbyte_data ->> 'id'), ''))::BIGINT
            AS distinct_keys
    FROM bronze.api_works
), works_ranked AS (
    SELECT
        source_row.*,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(_airbyte_data ->> 'id'), '')
            ORDER BY _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_data::TEXT DESC
        ) AS row_number
    FROM bronze.api_works AS source_row
    WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
), works_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM works_ranked
    WHERE row_number = 1
      AND NULLIF(TRIM(_airbyte_data ->> 'title'), '') IS NOT NULL
      AND NULLIF(TRIM(_airbyte_data ->> 'publication_year'), '')::INTEGER = 2026
      AND _airbyte_extracted_at IS NOT NULL
), authors_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(*) FILTER (
            WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
        )::BIGINT AS non_null_key_rows,
        COUNT(DISTINCT NULLIF(TRIM(_airbyte_data ->> 'id'), ''))::BIGINT
            AS distinct_keys
    FROM bronze.api_authors
), authors_ranked AS (
    SELECT
        source_row.*,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(_airbyte_data ->> 'id'), '')
            ORDER BY _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_data::TEXT DESC
        ) AS row_number
    FROM bronze.api_authors AS source_row
    WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
), authors_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM authors_ranked
    WHERE row_number = 1
      AND NULLIF(TRIM(_airbyte_data ->> 'works_count'), '')::BIGINT > 10
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'cited_by_count'), '')::BIGINT, 0) >= 0
      AND _airbyte_extracted_at IS NOT NULL
), institutions_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(*) FILTER (
            WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
        )::BIGINT AS non_null_key_rows,
        COUNT(DISTINCT NULLIF(TRIM(_airbyte_data ->> 'id'), ''))::BIGINT
            AS distinct_keys
    FROM bronze.api_institutions
), institutions_ranked AS (
    SELECT
        source_row.*,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(_airbyte_data ->> 'id'), '')
            ORDER BY _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_data::TEXT DESC
        ) AS row_number
    FROM bronze.api_institutions AS source_row
    WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NOT NULL
), institutions_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM institutions_ranked
    WHERE row_number = 1
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'works_count'), '')::BIGINT, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'cited_by_count'), '')::BIGINT, 0) >= 0
      AND (
          NULLIF(TRIM(_airbyte_data ->> 'country_code'), '') IS NULL
          OR NULLIF(TRIM(_airbyte_data ->> 'country_code'), '') ~ '^[A-Z]{2}$'
      )
      AND _airbyte_extracted_at IS NOT NULL
)
SELECT
    'openalex_works'::TEXT AS entity,
    works_base.bronze_rows,
    works_base.non_null_key_rows,
    works_base.distinct_keys,
    works_eligible.eligible_rows,
    (SELECT COUNT(*) FROM silver.openalex_work)::BIGINT AS silver_rows,
    works_base.bronze_rows - works_base.distinct_keys
        AS bronze_duplicate_or_null_rows,
    works_base.distinct_keys - works_eligible.eligible_rows
        AS business_or_provenance_exclusions
FROM works_base CROSS JOIN works_eligible
UNION ALL
SELECT
    'openalex_authors',
    authors_base.bronze_rows,
    authors_base.non_null_key_rows,
    authors_base.distinct_keys,
    authors_eligible.eligible_rows,
    (SELECT COUNT(*) FROM silver.openalex_author),
    authors_base.bronze_rows - authors_base.distinct_keys,
    authors_base.distinct_keys - authors_eligible.eligible_rows
FROM authors_base CROSS JOIN authors_eligible
UNION ALL
SELECT
    'openalex_institutions',
    institutions_base.bronze_rows,
    institutions_base.non_null_key_rows,
    institutions_base.distinct_keys,
    institutions_eligible.eligible_rows,
    (SELECT COUNT(*) FROM silver.openalex_institution),
    institutions_base.bronze_rows - institutions_base.distinct_keys,
    institutions_base.distinct_keys - institutions_eligible.eligible_rows
FROM institutions_base CROSS JOIN institutions_eligible;
