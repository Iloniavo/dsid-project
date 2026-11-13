-- Transformation Silver des opportunités EspoCRM.
-- Source Bronze attendue : bronze.espocrm_opportunity avec les colonnes
-- MariaDB exposées directement par le connecteur Airbyte.
-- `id` reprend la colonne native EspoCRM ; `source_record_id` conserve
-- l'identifiant technique `_airbyte_raw_id`.

CREATE OR REPLACE VIEW silver.espocrm_opportunity AS
WITH typed AS (
    SELECT
        NULLIF(BTRIM(id), '') AS id,
        _airbyte_raw_id::TEXT AS source_record_id,
        NULLIF(BTRIM(name), '') AS opportunity_name,
        amount::NUMERIC(14, 2) AS amount,
        NULLIF(BTRIM(amount_currency), '') AS amount_currency,
        NULLIF(BTRIM(stage), '') AS stage,
        NULLIF(BTRIM(last_stage), '') AS last_stage,
        probability::INTEGER AS probability,
        NULLIF(BTRIM(lead_source), '') AS lead_source,
        close_date::DATE AS close_date,
        NULLIF(BTRIM(account_id), '') AS account_id,
        NULLIF(BTRIM(contact_id), '') AS contact_id,
        created_at::TIMESTAMPTZ AS created_at,
        modified_at::TIMESTAMPTZ AS modified_at,
        stream_updated_at::TIMESTAMPTZ AS stream_updated_at,
        COALESCE(deleted, FALSE) AS is_deleted,
        _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at
    FROM bronze.espocrm_opportunity
), ranked AS (
    SELECT
        typed.*,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY extracted_at DESC NULLS LAST,
                     modified_at DESC NULLS LAST,
                     id DESC
        ) AS row_number
    FROM typed
    WHERE id IS NOT NULL
), eligible AS (
    SELECT *
    FROM ranked
    WHERE row_number = 1
      AND is_deleted = FALSE
      AND opportunity_name IS NOT NULL
      AND amount IS NOT NULL
      AND amount >= 0
      AND probability BETWEEN 0 AND 100
      AND stage IN (
          'Prospecting',
          'Qualification',
          'Proposal',
          'Negotiation',
          'Closed Won',
          'Closed Lost'
      )
      AND (
          close_date IS NULL
          OR created_at IS NULL
          OR close_date >= created_at::DATE
      )
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    opportunity_name,
    amount,
    amount_currency,
    stage,
    last_stage,
    probability,
    lead_source,
    close_date,
    account_id,
    contact_id,
    created_at,
    modified_at,
    stream_updated_at,
    'espocrm_mariadb'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
