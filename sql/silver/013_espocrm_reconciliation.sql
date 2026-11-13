-- Réconciliation des flux EspoCRM Bronze/Silver.
-- Les doublons Bronze, lignes supprimées et lignes invalides restent mesurables.

CREATE OR REPLACE VIEW silver.v_espocrm_reconciliation AS
WITH account_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(DISTINCT NULLIF(BTRIM(id), ''))::BIGINT AS distinct_keys
    FROM bronze.espocrm_account
), account_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM silver.espocrm_account
), contact_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(DISTINCT NULLIF(BTRIM(id), ''))::BIGINT AS distinct_keys
    FROM bronze.espocrm_contact
), contact_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM silver.espocrm_contact
), opportunity_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(DISTINCT NULLIF(BTRIM(id), ''))::BIGINT AS distinct_keys
    FROM bronze.espocrm_opportunity
), opportunity_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM silver.espocrm_opportunity
), relation_base AS (
    SELECT
        COUNT(*)::BIGINT AS bronze_rows,
        COUNT(DISTINCT (
            NULLIF(BTRIM(contact_id), ''),
            NULLIF(BTRIM(opportunity_id), '')
        ))::BIGINT AS distinct_keys
    FROM bronze.espocrm_contact_opportunity
), relation_eligible AS (
    SELECT COUNT(*)::BIGINT AS eligible_rows
    FROM silver.espocrm_contact_opportunity
)
SELECT
    'account'::TEXT AS entity,
    account_base.bronze_rows,
    account_base.distinct_keys,
    account_eligible.eligible_rows AS silver_rows,
    account_base.bronze_rows - account_base.distinct_keys AS bronze_duplicate_or_null_rows,
    account_base.distinct_keys - account_eligible.eligible_rows AS excluded_rows
FROM account_base CROSS JOIN account_eligible
UNION ALL
SELECT
    'contact',
    contact_base.bronze_rows,
    contact_base.distinct_keys,
    contact_eligible.eligible_rows,
    contact_base.bronze_rows - contact_base.distinct_keys,
    contact_base.distinct_keys - contact_eligible.eligible_rows
FROM contact_base CROSS JOIN contact_eligible
UNION ALL
SELECT
    'opportunity',
    opportunity_base.bronze_rows,
    opportunity_base.distinct_keys,
    opportunity_eligible.eligible_rows,
    opportunity_base.bronze_rows - opportunity_base.distinct_keys,
    opportunity_base.distinct_keys - opportunity_eligible.eligible_rows
FROM opportunity_base CROSS JOIN opportunity_eligible
UNION ALL
SELECT
    'contact_opportunity',
    relation_base.bronze_rows,
    relation_base.distinct_keys,
    relation_eligible.eligible_rows,
    relation_base.bronze_rows - relation_base.distinct_keys,
    relation_base.distinct_keys - relation_eligible.eligible_rows
FROM relation_base CROSS JOIN relation_eligible;
