-- Contrôles de conformité des transformations Silver EspoCRM.
-- Les anomalies d'intégrité doivent retourner failures = 0.

WITH checks AS (
    SELECT 'account_null_id' AS check_name, COUNT(*) AS failures
    FROM silver.espocrm_account
    WHERE id IS NULL OR source_record_id IS NULL
    UNION ALL
    SELECT 'account_duplicate_id', COUNT(*)
    FROM (
        SELECT id
        FROM silver.espocrm_account
        GROUP BY id
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'contact_null_id', COUNT(*)
    FROM silver.espocrm_contact
    WHERE id IS NULL OR source_record_id IS NULL
    UNION ALL
    SELECT 'contact_duplicate_id', COUNT(*)
    FROM (
        SELECT id
        FROM silver.espocrm_contact
        GROUP BY id
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'opportunity_null_id', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE id IS NULL OR source_record_id IS NULL
    UNION ALL
    SELECT 'opportunity_duplicate_id', COUNT(*)
    FROM (
        SELECT id
        FROM silver.espocrm_opportunity
        GROUP BY id
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'account_missing_source_record_id', COUNT(*)
    FROM silver.espocrm_account
    WHERE source_record_id IS NULL
    UNION ALL
    SELECT 'contact_missing_source_record_id', COUNT(*)
    FROM silver.espocrm_contact
    WHERE source_record_id IS NULL
    UNION ALL
    SELECT 'opportunity_missing_source_record_id', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE source_record_id IS NULL
    UNION ALL
    SELECT 'relation_missing_source_record_id', COUNT(*)
    FROM silver.espocrm_contact_opportunity
    WHERE source_record_id IS NULL
    UNION ALL
    SELECT 'relation_duplicate', COUNT(*)
    FROM (
        SELECT contact_id, opportunity_id
        FROM silver.espocrm_contact_opportunity
        GROUP BY contact_id, opportunity_id
        HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'opportunity_invalid_amount', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE amount IS NULL OR amount < 0
    UNION ALL
    SELECT 'opportunity_invalid_probability', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE probability IS NULL OR probability NOT BETWEEN 0 AND 100
    UNION ALL
    SELECT 'opportunity_invalid_stage', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE stage NOT IN (
        'Prospecting', 'Qualification', 'Proposal', 'Negotiation',
        'Closed Won', 'Closed Lost'
    )
    UNION ALL
    SELECT 'opportunity_closed_probability_mismatch', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE (stage = 'Closed Won' AND probability <> 100)
       OR (stage = 'Closed Lost' AND probability <> 0)
    UNION ALL
    SELECT 'opportunity_close_before_creation', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE close_date IS NOT NULL
      AND created_at IS NOT NULL
      AND close_date < created_at::DATE
    UNION ALL
    SELECT 'contact_missing_name', COUNT(*)
    FROM silver.espocrm_contact
    WHERE first_name IS NULL AND last_name IS NULL
    UNION ALL
    SELECT 'account_missing_name', COUNT(*)
    FROM silver.espocrm_account
    WHERE account_name IS NULL
    UNION ALL
    SELECT 'contact_missing_account', COUNT(*)
    FROM silver.espocrm_contact contact
    LEFT JOIN silver.espocrm_account account
      ON account.id = contact.account_id
    WHERE contact.account_id IS NOT NULL
      AND account.id IS NULL
    UNION ALL
    SELECT 'opportunity_missing_account', COUNT(*)
    FROM silver.espocrm_opportunity opportunity
    LEFT JOIN silver.espocrm_account account
      ON account.id = opportunity.account_id
    WHERE opportunity.account_id IS NOT NULL
      AND account.id IS NULL
    UNION ALL
    SELECT 'opportunity_missing_contact', COUNT(*)
    FROM silver.espocrm_opportunity opportunity
    LEFT JOIN silver.espocrm_contact contact
      ON contact.id = opportunity.contact_id
    WHERE opportunity.contact_id IS NOT NULL
      AND contact.id IS NULL
    UNION ALL
    SELECT 'relation_missing_contact', COUNT(*)
    FROM silver.espocrm_contact_opportunity relation
    LEFT JOIN silver.espocrm_contact contact
      ON contact.id = relation.contact_id
    WHERE contact.id IS NULL
    UNION ALL
    SELECT 'relation_missing_opportunity', COUNT(*)
    FROM silver.espocrm_contact_opportunity relation
    LEFT JOIN silver.espocrm_opportunity opportunity
      ON opportunity.id = relation.opportunity_id
    WHERE opportunity.id IS NULL
    UNION ALL
    SELECT 'account_missing_traceability', COUNT(*)
    FROM silver.espocrm_account
    WHERE source_system <> 'espocrm_mariadb'
       OR source_system IS NULL
       OR ingested_at_utc IS NULL
    UNION ALL
    SELECT 'contact_missing_traceability', COUNT(*)
    FROM silver.espocrm_contact
    WHERE source_system <> 'espocrm_mariadb'
       OR source_system IS NULL
       OR ingested_at_utc IS NULL
    UNION ALL
    SELECT 'opportunity_missing_traceability', COUNT(*)
    FROM silver.espocrm_opportunity
    WHERE source_system <> 'espocrm_mariadb'
       OR source_system IS NULL
       OR ingested_at_utc IS NULL
    UNION ALL
    SELECT 'relation_missing_traceability', COUNT(*)
    FROM silver.espocrm_contact_opportunity
    WHERE source_system <> 'espocrm_mariadb'
       OR source_system IS NULL
       OR ingested_at_utc IS NULL
)
SELECT check_name, failures
FROM checks
ORDER BY check_name;

-- Réconciliation Bronze/Silver : l'écart doit être expliqué, pas ignoré.
SELECT
    entity,
    bronze_rows,
    distinct_keys,
    silver_rows,
    bronze_duplicate_or_null_rows,
    excluded_rows,
    distinct_keys - silver_rows AS unexplained_difference
FROM silver.v_espocrm_reconciliation
ORDER BY entity;

-- Vérification des noms et types Silver.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name IN (
      'espocrm_account',
      'espocrm_contact',
      'espocrm_opportunity',
      'espocrm_contact_opportunity'
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name IN (
      'espocrm_account',
      'espocrm_contact',
      'espocrm_opportunity',
      'espocrm_contact_opportunity'
  )
  AND column_name !~ '^[a-z][a-z0-9_]*$'
ORDER BY table_name, ordinal_position;
