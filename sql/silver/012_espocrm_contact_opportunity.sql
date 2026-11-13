-- Transformation Silver de la relation contacts/opportunités EspoCRM.
-- Source Bronze attendue : bronze.espocrm_contact_opportunity avec les
-- colonnes MariaDB exposées directement par le connecteur Airbyte.
-- `id` reprend l'identifiant de la table source et `source_record_id`
-- reprend l'identifiant technique `_airbyte_raw_id` de la table source de
-- relation ; le grain Silver reste une relation contact/opportunité unique.

CREATE OR REPLACE VIEW silver.espocrm_contact_opportunity AS
WITH typed AS (
    SELECT
        id AS source_relation_id,
        _airbyte_raw_id::TEXT AS source_record_id,
        NULLIF(BTRIM(contact_id), '') AS contact_id,
        NULLIF(BTRIM(opportunity_id), '') AS opportunity_id,
        NULLIF(BTRIM(role), '') AS relationship_role,
        COALESCE(deleted, FALSE) AS is_deleted,
        _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at
    FROM bronze.espocrm_contact_opportunity
), ranked AS (
    SELECT
        typed.*,
        ROW_NUMBER() OVER (
            PARTITION BY contact_id, opportunity_id
            ORDER BY extracted_at DESC NULLS LAST,
                     source_relation_id DESC
        ) AS row_number
    FROM typed
    WHERE contact_id IS NOT NULL
      AND opportunity_id IS NOT NULL
), eligible AS (
    SELECT *
    FROM ranked
    WHERE row_number = 1
      AND is_deleted = FALSE
      AND extracted_at IS NOT NULL
)
SELECT
    source_relation_id AS id,
    source_record_id,
    contact_id,
    opportunity_id,
    relationship_role,
    'espocrm_mariadb'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible
WHERE EXISTS (
    SELECT 1
    FROM silver.espocrm_contact AS contact
    WHERE contact.id = eligible.contact_id
)
AND EXISTS (
    SELECT 1
    FROM silver.espocrm_opportunity AS opportunity
    WHERE opportunity.id = eligible.opportunity_id
);
