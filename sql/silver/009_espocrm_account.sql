-- Transformation Silver des comptes EspoCRM.
-- Source Bronze attendue : bronze.espocrm_account avec les colonnes MariaDB
-- exposées directement par le connecteur Airbyte.
-- `id` reprend la colonne native EspoCRM ; `source_record_id` conserve
-- l'identifiant technique `_airbyte_raw_id`.

CREATE OR REPLACE VIEW silver.espocrm_account AS
WITH typed AS (
    SELECT
        NULLIF(BTRIM(id), '') AS id,
        _airbyte_raw_id::TEXT AS source_record_id,
        NULLIF(BTRIM(name), '') AS account_name,
        NULLIF(BTRIM(website), '') AS website,
        NULLIF(BTRIM(type), '') AS account_type,
        NULLIF(BTRIM(industry), '') AS industry,
        NULLIF(BTRIM(billing_address_city), '') AS billing_city,
        NULLIF(BTRIM(billing_address_country), '') AS billing_country,
        NULLIF(BTRIM(billing_address_postal_code), '') AS billing_postal_code,
        created_at::TIMESTAMPTZ AS created_at,
        modified_at::TIMESTAMPTZ AS modified_at,
        stream_updated_at::TIMESTAMPTZ AS stream_updated_at,
        COALESCE(deleted, FALSE) AS is_deleted,
        _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at
    FROM bronze.espocrm_account
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
      AND account_name IS NOT NULL
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    account_name,
    website,
    account_type,
    industry,
    billing_city,
    billing_country,
    billing_postal_code,
    created_at,
    modified_at,
    stream_updated_at,
    'espocrm_mariadb'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
