-- Contrôles de la couche Bronze OpenAlex.
-- Airbyte conserve les propriétés source dans _airbyte_data.

-- 1. Clés non nulles en Bronze.
SELECT 'bronze_works_null_id' AS check_name, COUNT(*) AS failures
FROM bronze.api_works
WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NULL
UNION ALL
SELECT 'bronze_authors_null_id', COUNT(*)
FROM bronze.api_authors
WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NULL
UNION ALL
SELECT 'bronze_institutions_null_id', COUNT(*)
FROM bronze.api_institutions
WHERE NULLIF(TRIM(_airbyte_data ->> 'id'), '') IS NULL;

-- 2. Doublons Bronze par clé source.
SELECT 'bronze_works_duplicate_id' AS check_name, COUNT(*) AS duplicate_keys
FROM (
    SELECT _airbyte_data ->> 'id' AS id
    FROM bronze.api_works
    GROUP BY _airbyte_data ->> 'id'
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'bronze_authors_duplicate_id', COUNT(*)
FROM (
    SELECT _airbyte_data ->> 'id' AS id
    FROM bronze.api_authors
    GROUP BY _airbyte_data ->> 'id'
    HAVING COUNT(*) > 1
) duplicates
UNION ALL
SELECT 'bronze_institutions_duplicate_id', COUNT(*)
FROM (
    SELECT _airbyte_data ->> 'id' AS id
    FROM bronze.api_institutions
    GROUP BY _airbyte_data ->> 'id'
    HAVING COUNT(*) > 1
) duplicates;

-- 3. Colonnes techniques Airbyte attendues en Bronze.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
  AND table_name IN (
      'api_works',
      'api_authors',
      'api_institutions'
  )
  AND column_name LIKE '_airbyte_%'
ORDER BY table_name, ordinal_position;
