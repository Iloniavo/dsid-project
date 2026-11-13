-- Relation entre les auteurs et leurs institutions OpenAlex.
-- Un auteur peut avoir plusieurs affiliations. Les institutions absentes de
-- Silver sont conservées avec un statut explicite au lieu d'être supprimées.
--
-- `last_known_institutions` et `affiliations` restent disponibles dans Bronze.
-- Cette relation n'a pas d'identifiant source propre : `id` et
-- `source_record_id` est une clé stable dérivée de l'auteur, de l'institution,
-- du type de relation et de la position d'affiliation.
-- Les identifiants extraits sont des clés logiques tant que les vues Silver
-- ne sont pas matérialisées en tables avec des contraintes FOREIGN KEY.

CREATE OR REPLACE VIEW silver.openalex_author_institution AS
WITH author_records AS (
    SELECT
        a.id AS author_id,
        b._airbyte_data -> 'last_known_institutions' AS last_known_institutions,
        b._airbyte_data -> 'affiliations' AS affiliations
    FROM bronze.api_authors AS b
    JOIN silver.openalex_author AS a
      ON a.id = NULLIF(TRIM(b._airbyte_data ->> 'id'), '')
), last_known AS (
    SELECT
        author_id,
        NULLIF(TRIM(institutions.institution_data ->> 'id'), '') AS institution_id,
        NULL::INTEGER AS affiliation_position,
        'last_known_institution'::TEXT AS relationship_type
    FROM author_records
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(last_known_institutions) = 'array'
            THEN last_known_institutions
            ELSE '[]'::JSONB
        END
    ) AS institutions(institution_data)
), affiliations AS (
    SELECT
        author_id,
        NULLIF(
            TRIM(affiliation_data -> 'institution' ->> 'id'),
            ''
        ) AS institution_id,
        affiliation_position::INTEGER,
        'affiliation'::TEXT AS relationship_type
    FROM author_records
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(affiliations) = 'array'
            THEN affiliations
            ELSE '[]'::JSONB
        END
    ) WITH ORDINALITY AS affiliation_rows(
        affiliation_data,
        affiliation_position
    )
), extracted AS (
    SELECT * FROM last_known
    UNION ALL
    SELECT * FROM affiliations
), classified AS (
    SELECT DISTINCT
        extracted.author_id,
        extracted.institution_id,
        extracted.affiliation_position,
        extracted.relationship_type,
        (institution.id IS NOT NULL)
            AS institution_present_in_silver,
        CASE
            WHEN institution.id IS NOT NULL
                THEN 'registered'
            ELSE 'known_by_openalex_not_loaded'
        END AS institution_status
    FROM extracted
    LEFT JOIN silver.openalex_institution AS institution
      ON institution.id = extracted.institution_id
    WHERE extracted.institution_id IS NOT NULL
)
SELECT
    CONCAT(
        author_id,
        ':',
        institution_id,
        ':',
        relationship_type,
        ':',
        COALESCE(affiliation_position, 0)
    ) AS id,
    CONCAT(
        author_id,
        ':',
        institution_id,
        ':',
        relationship_type,
        ':',
        COALESCE(affiliation_position, 0)
    ) AS source_record_id,
    author_id,
    institution_id,
    affiliation_position,
    relationship_type,
    institution_present_in_silver,
    institution_status
FROM classified;
