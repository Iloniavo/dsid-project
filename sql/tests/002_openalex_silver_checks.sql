-- Contrôles de conformité de la couche Silver OpenAlex.
-- Une anomalie d'intégrité doit retourner failures = 0.

-- 1. Clés stables, non nulles et uniques en Silver.
SELECT 'silver_works_null_id' AS check_name, COUNT(*) AS failures
FROM silver.openalex_work
WHERE id IS NULL OR source_record_id IS NULL
UNION ALL
SELECT 'silver_works_duplicate_id', COUNT(*)
FROM (
    SELECT id
    FROM silver.openalex_work
    GROUP BY id
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'silver_authors_null_id', COUNT(*)
FROM silver.openalex_author
WHERE id IS NULL OR source_record_id IS NULL
UNION ALL
SELECT 'silver_authors_duplicate_id', COUNT(*)
FROM (
    SELECT id
    FROM silver.openalex_author
    GROUP BY id
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'silver_institutions_null_id', COUNT(*)
FROM silver.openalex_institution
WHERE id IS NULL OR source_record_id IS NULL
UNION ALL
SELECT 'silver_institutions_duplicate_id', COUNT(*)
FROM (
    SELECT id
    FROM silver.openalex_institution
    GROUP BY id
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'silver_works_missing_source_record_id', COUNT(*)
FROM silver.openalex_work
WHERE source_record_id IS NULL
UNION ALL
SELECT 'silver_authors_missing_source_record_id', COUNT(*)
FROM silver.openalex_author
WHERE source_record_id IS NULL
UNION ALL
SELECT 'silver_institutions_missing_source_record_id', COUNT(*)
FROM silver.openalex_institution
WHERE source_record_id IS NULL;

-- 2. Règles métier après standardisation.
SELECT 'silver_works_invalid_filter_year' AS check_name, COUNT(*) AS failures
FROM silver.openalex_work
WHERE publication_year IS NULL OR publication_year <> 2026
UNION ALL
SELECT 'silver_works_empty_title', COUNT(*)
FROM silver.openalex_work
WHERE title IS NULL
UNION ALL
SELECT 'silver_works_negative_citations', COUNT(*)
FROM silver.openalex_work
WHERE cited_by_count < 0
UNION ALL
SELECT 'silver_authors_filter_not_respected', COUNT(*)
FROM silver.openalex_author
WHERE works_count IS NULL OR works_count <= 10
UNION ALL
SELECT 'silver_authors_negative_citations', COUNT(*)
FROM silver.openalex_author
WHERE cited_by_count < 0
UNION ALL
SELECT 'silver_institutions_negative_works', COUNT(*)
FROM silver.openalex_institution
WHERE works_count < 0
UNION ALL
SELECT 'silver_institutions_negative_citations', COUNT(*)
FROM silver.openalex_institution
WHERE cited_by_count < 0
UNION ALL
SELECT 'silver_institutions_invalid_country_code', COUNT(*)
FROM silver.openalex_institution
WHERE country_code IS NOT NULL
  AND country_code !~ '^[A-Z]{2}$';

-- 3. Traçabilité obligatoire.
SELECT 'silver_works_missing_source_system' AS check_name, COUNT(*) AS failures
FROM silver.openalex_work
WHERE source_system IS NULL OR source_system <> 'openalex'
UNION ALL
SELECT 'silver_works_missing_ingestion_timestamp', COUNT(*)
FROM silver.openalex_work
WHERE ingested_at_utc IS NULL
UNION ALL
SELECT 'silver_authors_missing_source_system', COUNT(*)
FROM silver.openalex_author
WHERE source_system IS NULL OR source_system <> 'openalex'
UNION ALL
SELECT 'silver_authors_missing_ingestion_timestamp', COUNT(*)
FROM silver.openalex_author
WHERE ingested_at_utc IS NULL
UNION ALL
SELECT 'silver_institutions_missing_source_system', COUNT(*)
FROM silver.openalex_institution
WHERE source_system IS NULL OR source_system <> 'openalex'
UNION ALL
SELECT 'silver_institutions_missing_ingestion_timestamp', COUNT(*)
FROM silver.openalex_institution
WHERE ingested_at_utc IS NULL;

-- 4. Réconciliation Bronze/Silver.
-- Silver doit contenir une ligne par clé distincte qui respecte la règle
-- métier et la présence du timestamp d'ingestion. Les doublons Bronze et les
-- lignes écartées sont quantifiés dans silver.v_openalex_reconciliation.
SELECT *
FROM silver.v_openalex_reconciliation;

-- Contrôle strict de la réconciliation.
SELECT
    entity,
    eligible_rows - silver_rows AS failures
FROM silver.v_openalex_reconciliation;

-- 5. Colonnes de traçabilité et noms normalisés.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name IN (
      'openalex_work',
      'openalex_author',
      'openalex_institution'
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name IN (
      'openalex_work',
      'openalex_author',
      'openalex_institution'
  )
  AND column_name !~ '^[a-z][a-z0-9_]*$'
ORDER BY table_name, ordinal_position;

-- 6. Relations Works/Authors : chaque relation doit référencer une clé
-- existante dans les vues Silver quand elle est déclarée `registered`.
WITH work_author_checks AS (
    SELECT 'work_author_missing_work' AS check_name, COUNT(*) AS failures
    FROM silver.openalex_work_author wa
    LEFT JOIN silver.openalex_work w ON w.id = wa.work_id
    WHERE w.id IS NULL
    UNION ALL
    SELECT 'work_author_null_key', COUNT(*)
    FROM silver.openalex_work_author
    WHERE work_id IS NULL OR author_id IS NULL
    UNION ALL
    SELECT 'work_author_duplicate_relation', COUNT(*)
    FROM (
        SELECT work_id, author_id
        FROM silver.openalex_work_author
        GROUP BY work_id, author_id
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'work_author_invalid_position', COUNT(*)
    FROM silver.openalex_work_author
    WHERE author_position IS NULL OR author_position < 1
    UNION ALL
    SELECT 'work_author_invalid_corresponding_flag', COUNT(*)
    FROM silver.openalex_work_author
    WHERE is_corresponding IS NULL
    UNION ALL
    SELECT 'work_author_invalid_status', COUNT(*)
    FROM silver.openalex_work_author
    WHERE author_status NOT IN (
        'registered',
        'known_by_openalex_not_loaded'
    )
       OR author_present_in_silver IS NULL
    UNION ALL
    SELECT 'work_author_status_mismatch', COUNT(*)
    FROM silver.openalex_work_author
    WHERE (
            author_present_in_silver = TRUE
            AND author_status <> 'registered'
        )
       OR (
            author_present_in_silver = FALSE
            AND author_status <> 'known_by_openalex_not_loaded'
        )
    UNION ALL
    SELECT 'work_author_registered_missing_author', COUNT(*)
    FROM silver.openalex_work_author wa
    LEFT JOIN silver.openalex_author a
      ON a.id = wa.author_id
    WHERE wa.author_status = 'registered'
      AND a.id IS NULL
)
SELECT check_name, failures
FROM work_author_checks;

-- Information : les relations non résolues sont attendues lorsque l'auteur
-- OpenAlex n'est pas chargé dans silver.openalex_author.
SELECT
    'work_author_unresolved_count' AS metric_name,
    COUNT(*) AS relation_count
FROM silver.openalex_work_author
WHERE author_status = 'known_by_openalex_not_loaded';

-- Relations Authors/Institutions : les relations non résolues sont autorisées,
-- mais les clés de relation et les doublons doivent rester contrôlés.
WITH author_institution_checks AS (
    SELECT 'author_institution_null_author' AS check_name, COUNT(*) AS failures
    FROM silver.openalex_author_institution
    WHERE author_id IS NULL
    UNION ALL
    SELECT 'author_institution_null_institution', COUNT(*)
    FROM silver.openalex_author_institution
    WHERE institution_id IS NULL
    UNION ALL
    SELECT 'author_institution_duplicate_relation', COUNT(*)
    FROM (
        SELECT author_id, institution_id, relationship_type
        FROM silver.openalex_author_institution
        GROUP BY author_id, institution_id, relationship_type
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'author_institution_missing_author', COUNT(*)
    FROM silver.openalex_author_institution ai
    LEFT JOIN silver.openalex_author a ON a.id = ai.author_id
    WHERE a.id IS NULL
    UNION ALL
    SELECT 'author_institution_invalid_type', COUNT(*)
    FROM silver.openalex_author_institution
    WHERE relationship_type NOT IN (
        'affiliation',
        'last_known_institution'
    )
    UNION ALL
    SELECT 'author_institution_invalid_position', COUNT(*)
    FROM silver.openalex_author_institution
    WHERE (
            relationship_type = 'affiliation'
            AND (
                affiliation_position IS NULL
                OR affiliation_position < 1
            )
        )
       OR (
            relationship_type = 'last_known_institution'
            AND affiliation_position IS NOT NULL
        )
    UNION ALL
    SELECT 'author_institution_invalid_status', COUNT(*)
    FROM silver.openalex_author_institution
    WHERE institution_status NOT IN (
        'registered',
        'known_by_openalex_not_loaded'
    )
       OR institution_present_in_silver IS NULL
    UNION ALL
    SELECT 'author_institution_status_mismatch', COUNT(*)
    FROM silver.openalex_author_institution
    WHERE (
            institution_present_in_silver = TRUE
            AND institution_status <> 'registered'
        )
       OR (
            institution_present_in_silver = FALSE
            AND institution_status <> 'known_by_openalex_not_loaded'
        )
    UNION ALL
    SELECT 'author_institution_registered_missing_institution', COUNT(*)
    FROM silver.openalex_author_institution ai
    LEFT JOIN silver.openalex_institution i
      ON i.id = ai.institution_id
    WHERE ai.institution_status = 'registered'
      AND i.id IS NULL
)
SELECT check_name, failures
FROM author_institution_checks;

-- Information : les relations non résolues sont attendues lorsque
-- l'institution OpenAlex n'est pas chargée dans Silver.
SELECT
    'author_institution_unresolved_count' AS metric_name,
    COUNT(*) AS relation_count
FROM silver.openalex_author_institution
WHERE institution_status = 'known_by_openalex_not_loaded';
