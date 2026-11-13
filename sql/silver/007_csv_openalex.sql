-- Transformation Silver du CSV de métadonnées OpenAlex.
-- Contrat Bronze attendu : bronze.csv_paper_citation avec une colonne JSONB
-- `_airbyte_data` et les métadonnées techniques Airbyte.
--
-- Les colonnes dérivées redondantes (*_log et title_abstract_text) ne sont
-- pas reprises : les mesures principales sont conservées pour l'analyse et
-- peuvent être recalculées selon le besoin.
-- `id` reprend la clé métier `paper_id` ; `source_record_id` conserve
-- `_airbyte_raw_id`, l'identifiant technique Airbyte.

CREATE OR REPLACE VIEW silver.csv_paper_citation AS
WITH typed AS (
    SELECT
        _airbyte_raw_id::TEXT AS source_record_id,
        NULLIF(TRIM(_airbyte_data ->> 'paper_id'), '') AS id,
        NULLIF(TRIM(_airbyte_data ->> 'doi'), '') AS doi,
        NULLIF(TRIM(_airbyte_data ->> 'paper_title'), '') AS title,
        NULLIF(TRIM(_airbyte_data ->> 'abstract'), '') AS abstract,
        NULLIF(TRIM(_airbyte_data ->> 'publication_year'), '')::INTEGER
            AS publication_year,
        NULLIF(TRIM(_airbyte_data ->> 'publication_date'), '')::DATE
            AS publication_date,
        NULLIF(TRIM(_airbyte_data ->> 'paper_type'), '') AS paper_type,
        NULLIF(TRIM(_airbyte_data ->> 'language'), '') AS language,
        NULLIF(TRIM(_airbyte_data ->> 'journal'), '') AS journal,
        NULLIF(TRIM(_airbyte_data ->> 'publisher'), '') AS publisher,
        NULLIF(TRIM(_airbyte_data ->> 'source_type'), '') AS source_type,
        CASE
            WHEN NULLIF(TRIM(_airbyte_data ->> 'open_access'), '') IN ('1', 'true', 'TRUE')
                THEN TRUE
            WHEN NULLIF(TRIM(_airbyte_data ->> 'open_access'), '') IN ('0', 'false', 'FALSE')
                THEN FALSE
        END AS open_access,
        NULLIF(TRIM(_airbyte_data ->> 'open_access_status'), '') AS open_access_status,
        NULLIF(TRIM(_airbyte_data ->> 'field_of_study'), '') AS field_of_study,
        NULLIF(TRIM(_airbyte_data ->> 'keywords'), '') AS keywords,
        NULLIF(TRIM(_airbyte_data ->> 'number_of_authors'), '')::INTEGER
            AS number_of_authors,
        NULLIF(TRIM(_airbyte_data ->> 'first_author'), '') AS first_author,
        NULLIF(TRIM(_airbyte_data ->> 'institution_country'), '') AS institution_country,
        NULLIF(TRIM(_airbyte_data ->> 'number_of_institutions'), '')::INTEGER
            AS number_of_institutions,
        CASE
            WHEN NULLIF(TRIM(_airbyte_data ->> 'international_collaboration'), '') IN ('1', 'true', 'TRUE')
                THEN TRUE
            WHEN NULLIF(TRIM(_airbyte_data ->> 'international_collaboration'), '') IN ('0', 'false', 'FALSE')
                THEN FALSE
        END AS international_collaboration,
        NULLIF(TRIM(_airbyte_data ->> 'references_count'), '')::BIGINT
            AS references_count,
        NULLIF(TRIM(_airbyte_data ->> 'citation_count'), '')::BIGINT
            AS citation_count,
        NULLIF(TRIM(_airbyte_data ->> 'title_length_words'), '')::INTEGER
            AS title_length_words,
        NULLIF(TRIM(_airbyte_data ->> 'abstract_length_words'), '')::INTEGER
            AS abstract_length_words,
        NULLIF(TRIM(_airbyte_data ->> 'keyword_count'), '')::INTEGER
            AS keyword_count,
        NULLIF(TRIM(_airbyte_data ->> 'publication_age'), '')::INTEGER
            AS publication_age,
        NULLIF(TRIM(_airbyte_data ->> 'citation_rate_per_year'), '')::NUMERIC
            AS citation_rate_per_year,
        _airbyte_extracted_at::TIMESTAMPTZ AS extracted_at,
        _airbyte_data AS source_payload
    FROM bronze.csv_paper_citation
), ranked AS (
    SELECT
        typed.*,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY extracted_at DESC NULLS LAST, source_payload::TEXT DESC
        ) AS row_number
    FROM typed
    WHERE id IS NOT NULL
), eligible AS (
    SELECT *
    FROM ranked
    WHERE row_number = 1
      AND title IS NOT NULL
      AND extracted_at IS NOT NULL
      AND open_access IS NOT NULL
      AND international_collaboration IS NOT NULL
      AND COALESCE(number_of_authors, 0) >= 0
      AND COALESCE(number_of_institutions, 0) >= 0
      AND COALESCE(references_count, 0) >= 0
      AND COALESCE(citation_count, 0) >= 0
      AND COALESCE(title_length_words, 0) >= 0
      AND COALESCE(abstract_length_words, 0) >= 0
      AND COALESCE(keyword_count, 0) >= 0
      AND COALESCE(publication_age, 0) >= 0
      AND COALESCE(citation_rate_per_year, 0) >= 0
)
SELECT
    id,
    source_record_id,
    doi,
    title,
    abstract,
    publication_year,
    publication_date,
    paper_type,
    language,
    journal,
    publisher,
    source_type,
    open_access,
    open_access_status,
    field_of_study,
    keywords,
    number_of_authors,
    first_author,
    number_of_institutions,
    institution_country,
    international_collaboration,
    references_count,
    citation_count,
    title_length_words,
    abstract_length_words,
    keyword_count,
    publication_age,
    citation_rate_per_year,
    'csv_paper_citation'::TEXT AS source_system,
    extracted_at AS ingested_at_utc
FROM eligible;
