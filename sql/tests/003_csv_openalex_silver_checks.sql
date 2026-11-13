-- Contrôles de conformité de la transformation Silver CSV OpenAlex.
-- Les contrôles d'intégrité doivent retourner failures = 0.

SELECT 'csv_silver_null_paper_id' AS check_name, COUNT(*) AS failures
FROM silver.csv_paper_citation
WHERE id IS NULL OR source_record_id IS NULL
UNION ALL
SELECT 'csv_silver_duplicate_paper_id', COUNT(*)
FROM (
    SELECT id
    FROM silver.csv_paper_citation
    GROUP BY id
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'csv_silver_missing_source_record_id', COUNT(*)
FROM silver.csv_paper_citation
WHERE source_record_id IS NULL
UNION ALL
SELECT 'csv_silver_missing_title', COUNT(*)
FROM silver.csv_paper_citation
WHERE title IS NULL
UNION ALL
SELECT 'csv_silver_invalid_counts', COUNT(*)
FROM silver.csv_paper_citation
WHERE COALESCE(number_of_authors, 0) < 0
   OR COALESCE(number_of_institutions, 0) < 0
   OR COALESCE(references_count, 0) < 0
   OR COALESCE(citation_count, 0) < 0
   OR COALESCE(title_length_words, 0) < 0
   OR COALESCE(abstract_length_words, 0) < 0
   OR COALESCE(keyword_count, 0) < 0
   OR COALESCE(publication_age, 0) < 0
   OR COALESCE(citation_rate_per_year, 0) < 0
UNION ALL
SELECT 'csv_silver_invalid_boolean', COUNT(*)
FROM silver.csv_paper_citation
WHERE open_access IS NULL
   OR international_collaboration IS NULL
UNION ALL
SELECT 'csv_silver_missing_source_system', COUNT(*)
FROM silver.csv_paper_citation
WHERE source_system <> 'csv_openalex'
   OR source_system IS NULL
UNION ALL
SELECT 'csv_silver_missing_ingestion_timestamp', COUNT(*)
FROM silver.csv_paper_citation
WHERE ingested_at_utc IS NULL
UNION ALL
SELECT 'csv_silver_invalid_publication_date', COUNT(*)
FROM silver.csv_paper_citation
WHERE publication_date IS NOT NULL
  AND publication_year IS NOT NULL
  AND EXTRACT(YEAR FROM publication_date)::INTEGER <> publication_year;

-- Réconciliation : failures doit être égal à zéro.
SELECT
    entity,
    eligible_rows - silver_rows AS failures
FROM silver.v_csv_paper_citation_reconciliation;

-- Vérification des noms et types Silver.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name = 'csv_paper_citation'
ORDER BY ordinal_position;

SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name = 'csv_paper_citation'
  AND column_name !~ '^[a-z][a-z0-9_]*$'
ORDER BY ordinal_position;

-- Métrique informative : doublons et clés nulles quantifiés en Bronze.
SELECT
    bronze_rows,
    non_null_key_rows,
    distinct_keys,
    bronze_duplicate_or_null_rows,
    business_or_provenance_exclusions,
    silver_rows
FROM silver.v_csv_paper_citation_reconciliation;
