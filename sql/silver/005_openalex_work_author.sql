-- Relation normalisée entre les publications et les auteurs.
-- `authorships` reste conservé dans Bronze pour fidélité à la source, mais
-- n'est pas exposé dans silver.openalex_work.
-- Cette relation n'a pas d'identifiant source propre : `id` et
-- `source_record_id` est donc une clé stable dérivée du work, de l'auteur et
-- de la position d'auteur.
--
-- Les objets Silver étant actuellement des vues, les références ci-dessous
-- sont des clés logiques. Pour de vraies contraintes FOREIGN KEY, il faudra
-- matérialiser les deux vues Silver en tables.

CREATE OR REPLACE VIEW silver.openalex_work_author AS
WITH extracted AS (
    SELECT
        w.id AS work_id,
        NULLIF(TRIM(authors.authorship -> 'author' ->> 'id'), '') AS author_id,
        author_position::INTEGER AS author_position,
        COALESCE(
            (authors.authorship ->> 'is_corresponding')::BOOLEAN,
            FALSE
        ) AS is_corresponding
    FROM bronze.api_works b
    JOIN silver.openalex_work w
      ON w.id = NULLIF(TRIM(b._airbyte_data ->> 'id'), '')
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(b._airbyte_data -> 'authorships') = 'array'
            THEN b._airbyte_data -> 'authorships'
            ELSE '[]'::JSONB
        END
    ) WITH ORDINALITY AS authors(authorship, author_position)
), classified AS (
    SELECT DISTINCT
        extracted.work_id,
        extracted.author_id,
        extracted.author_position,
        extracted.is_corresponding,
        (a.id IS NOT NULL) AS author_present_in_silver,
        CASE
            WHEN a.id IS NOT NULL THEN 'registered'
            ELSE 'known_by_openalex_not_loaded'
        END AS author_status
    FROM extracted
    LEFT JOIN silver.openalex_author a
      ON a.id = extracted.author_id
    WHERE extracted.author_id IS NOT NULL
)
SELECT
    CONCAT(work_id, ':', author_id, ':', author_position) AS id,
    CONCAT(work_id, ':', author_id, ':', author_position) AS source_record_id,
    work_id,
    author_id,
    author_position,
    is_corresponding,
    author_present_in_silver,
    author_status
FROM classified;
