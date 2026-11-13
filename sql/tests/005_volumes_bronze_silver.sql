-- 005_volumes_bronze_silver.sql
-- Releve des volumes Bronze et Silver + ecarts, pour alimenter le rapport.
-- Lecture seule.

\echo '--- 5.1 Inventaire des objets bronze / silver'
SELECT table_schema, table_name, table_type
FROM   information_schema.tables
WHERE  table_schema IN ('bronze', 'silver')
ORDER  BY table_schema, table_name;

\echo '--- 5.2 Volumes Bronze'
SELECT 'bronze.api_works'                   AS objet, COUNT(*) AS lignes FROM bronze.api_works
UNION ALL SELECT 'bronze.api_authors',                COUNT(*) FROM bronze.api_authors
UNION ALL SELECT 'bronze.api_institutions',           COUNT(*) FROM bronze.api_institutions
UNION ALL SELECT 'bronze.csv_paper_citation',         COUNT(*) FROM bronze.csv_paper_citation
UNION ALL SELECT 'bronze.espocrm_account',            COUNT(*) FROM bronze.espocrm_account
UNION ALL SELECT 'bronze.espocrm_contact',            COUNT(*) FROM bronze.espocrm_contact
UNION ALL SELECT 'bronze.espocrm_opportunity',        COUNT(*) FROM bronze.espocrm_opportunity
UNION ALL SELECT 'bronze.espocrm_contact_opportunity',COUNT(*) FROM bronze.espocrm_contact_opportunity
ORDER BY 1;

\echo '--- 5.3 Volumes Silver'
SELECT 'silver.openalex_work'               AS objet, COUNT(*) AS lignes FROM silver.openalex_work
UNION ALL SELECT 'silver.openalex_author',             COUNT(*) FROM silver.openalex_author
UNION ALL SELECT 'silver.openalex_institution',        COUNT(*) FROM silver.openalex_institution
UNION ALL SELECT 'silver.openalex_work_author',        COUNT(*) FROM silver.openalex_work_author
UNION ALL SELECT 'silver.openalex_author_institution', COUNT(*) FROM silver.openalex_author_institution
UNION ALL SELECT 'silver.csv_paper_citation',          COUNT(*) FROM silver.csv_paper_citation
UNION ALL SELECT 'silver.espocrm_account',             COUNT(*) FROM silver.espocrm_account
UNION ALL SELECT 'silver.espocrm_contact',             COUNT(*) FROM silver.espocrm_contact
UNION ALL SELECT 'silver.espocrm_opportunity',         COUNT(*) FROM silver.espocrm_opportunity
UNION ALL SELECT 'silver.espocrm_contact_opportunity', COUNT(*) FROM silver.espocrm_contact_opportunity
ORDER BY 1;

\echo '--- 5.4 Reconciliation OpenAlex'
SELECT * FROM silver.v_openalex_reconciliation;

\echo '--- 5.5 Reconciliation CSV'
SELECT * FROM silver.v_csv_paper_citation_reconciliation;

\echo '--- 5.6 Reconciliation EspoCRM'
SELECT * FROM silver.v_espocrm_reconciliation;

\echo '--- 5.7 Colonnes non conformes a snake_case (toutes vues silver)'
SELECT table_name, column_name
FROM   information_schema.columns
WHERE  table_schema = 'silver'
  AND  column_name !~ '^[a-z][a-z0-9_]*$'
ORDER  BY table_name, column_name;

\echo '--- 5.8 Types observes des vues de liaison (non couvertes par 002)'
SELECT table_name, column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'silver'
  AND  table_name IN ('openalex_work_author', 'openalex_author_institution')
ORDER  BY table_name, ordinal_position;
