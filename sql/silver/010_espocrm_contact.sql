-- Transformation Silver des contacts EspoCRM.
-- Source Bronze attendue : bronze.espocrm_contact avec les colonnes MariaDB
-- exposées directement par le connecteur Airbyte.
-- `id` reprend la colonne native EspoCRM ; `source_record_id` conserve
-- l'identifiant technique `_airbyte_raw_id`.

CREATE OR REPLACE VIEW silver.espocrm_contact AS
WITH typed AS (
    SELECT
        NULLIF(BTRIM(id), '') AS id,
        _airbyte_raw_id::TEXT AS source_record_id,
        NULLIF(BTRIM(salutation_name), '') AS salutation,
        NULLIF(BTRIM(first_name), '') AS first_name,
        NULLIF(BTRIM(last_name), '') AS last_name,
        NULLIF(BTRIM(address_city), '') AS city,
        NULLIF(BTRIM(address_country), '') AS country,
        NULLIF(BTRIM(address_postal_code), '') AS postal_code,
        NULLIF(BTRIM(account_id), '') AS account_id,
        COALESCE(do_not_call, FALSE) AS do_not_call,
        created_at::TIMESTAMPTZ AS created_at,
        modified_at::TIMESTAMPTZ AS modified_at,
        stream_updated_at::TIMESTAMPTZ AS stream_updated_at,
        COALESCE(deleted, FALSE) AS is_deleted,
        _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at
    FROM bronze.espocrm_contact
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
      AND (first_name IS NOT NULL OR last_name IS NOT NULL)
      AND extracted_at IS NOT NULL
)
SELECT
    id,
    source_record_id,
    salutation,
    first_name,
    last_name,
    CONCAT_WS(' ', first_name, last_name) AS full_name,
    city,
    country,
    postal_code,
    account_id,
    do_not_call,
    created_at,
    modified_at,
    stream_updated_at,
    'espocrm_mariadb'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
