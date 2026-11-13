-- Réconciliation du CSV Bronze avec la vue Silver.
-- Les lignes écartées sont expliquées par une clé absente, un titre absent,
-- un timestamp absent ou une valeur quantitative négative.

CREATE OR REPLACE VIEW silver.v_csv_paper_citation_reconciliation AS
WITH base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(*) FILTER (
            WHERE NULLIF(TRIM(_airbyte_data ->> 'paper_id'), '') IS NOT NULL
        )::BIGINT AS non_null_key_rows,
        COUNT(DISTINCT NULLIF(TRIM(_airbyte_data ->> 'paper_id'), ''))::BIGINT
            AS distinct_keys
    FROM bronze.csv_paper_citation
), ranked AS (
    SELECT
        _airbyte_data,
        _airbyte_extracted_at,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(_airbyte_data ->> 'paper_id'), '')
            ORDER BY _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_data::TEXT DESC
        ) AS row_number
    FROM bronze.csv_paper_citation
    WHERE NULLIF(TRIM(_airbyte_data ->> 'paper_id'), '') IS NOT NULL
), eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM ranked
    WHERE row_number = 1
      AND NULLIF(TRIM(_airbyte_data ->> 'paper_title'), '') IS NOT NULL
      AND _airbyte_extracted_at IS NOT NULL
      AND NULLIF(TRIM(_airbyte_data ->> 'open_access'), '') IN ('0', '1', 'true', 'TRUE', 'false', 'FALSE')
      AND NULLIF(TRIM(_airbyte_data ->> 'international_collaboration'), '') IN ('0', '1', 'true', 'TRUE', 'false', 'FALSE')
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'number_of_authors'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'number_of_institutions'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'references_count'), '')::BIGINT, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'citation_count'), '')::BIGINT, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'title_length_words'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'abstract_length_words'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'keyword_count'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'publication_age'), '')::INTEGER, 0) >= 0
      AND COALESCE(NULLIF(TRIM(_airbyte_data ->> 'citation_rate_per_year'), '')::NUMERIC, 0) >= 0
)
SELECT
    'csv_paper_citation'::TEXT AS entity,
    base.bronze_rows,
    base.non_null_key_rows,
    base.distinct_keys,
    eligible.eligible_rows,
    (SELECT COUNT(*) FROM silver.csv_paper_citation)::BIGINT AS silver_rows,
    base.bronze_rows - base.distinct_keys AS bronze_duplicate_or_null_rows,
    base.distinct_keys - eligible.eligible_rows AS business_or_provenance_exclusions
FROM base CROSS JOIN eligible;
