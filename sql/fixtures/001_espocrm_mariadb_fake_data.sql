-- Jeu de données factices cohérent pour EspoCRM/MariaDB.
--
-- Noms physiques vérifiés dans la base MariaDB locale le 2026-11-13 :
--   account
--   contact
--   opportunity
--   contact_opportunity
--
-- Les relations utilisées sont :
--   contact.account_id
--   opportunity.account_id
--   opportunity.contact_id
--   contact_opportunity.contact_id / opportunity_id
--
-- Volumes générés :
--   1 000 comptes
--   5 000 contacts
--  10 000 opportunités
--  20 000 relations contact-opportunité
--
-- Le script est rejouable : il n'écrase pas une ligne existante portant l'un
-- des identifiants déterministes du jeu de données.
--
-- Attention : l'insertion directe contourne les événements et les contrôles
-- applicatifs EspoCRM. À utiliser uniquement pour alimenter un environnement
-- de développement ou de test.

START TRANSACTION;

SET SESSION max_recursive_iterations = 10000;

DROP TEMPORARY TABLE IF EXISTS _fixture_numbers;
CREATE TEMPORARY TABLE _fixture_numbers (
    n INT NOT NULL PRIMARY KEY
);

INSERT INTO _fixture_numbers (n)
WITH RECURSIVE sequence_numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1
    FROM sequence_numbers
    WHERE n < 10000
)
SELECT n
FROM sequence_numbers;

-- Les identifiants font 17 caractères, comme le contrat découvert dans
-- MariaDB : acct + 13 chiffres, cont + 13 chiffres, oppo + 13 chiffres.
INSERT INTO account (
    id,
    name,
    deleted,
    website,
    type,
    industry,
    billing_address_street,
    billing_address_city,
    billing_address_country,
    billing_address_postal_code,
    description,
    is_locked,
    created_at,
    modified_at,
    stream_updated_at,
    version_number
)
SELECT
    CONCAT('acct', LPAD(n, 13, '0')),
    CONCAT(
        ELT(MOD(n - 1, 5) + 1, 'Atlas', 'Nova', 'Orion', 'Pixel', 'Vertex'),
        ' ',
        ELT(MOD(n - 1, 5) + 1, 'Research', 'Industries', 'Analytics', 'Systems', 'Labs'),
        ' ',
        LPAD(n, 4, '0')
    ),
    0,
    CONCAT('https://account-', LPAD(n, 4, '0'), '.example.test'),
    ELT(MOD(n - 1, 3) + 1, 'Customer', 'Partner', 'Prospect'),
    ELT(MOD(n - 1, 5) + 1, 'Technology', 'Healthcare', 'Education', 'Finance', 'Energy'),
    CONCAT(LPAD(10 + MOD(n, 990), 3, '0'), ' Rue de la Recherche'),
    ELT(MOD(n - 1, 5) + 1, 'Paris', 'Lyon', 'Lille', 'Nantes', 'Toulouse'),
    'France',
    CONCAT('75', LPAD(MOD(n, 900) + 100, 3, '0')),
    'Compte de démonstration généré pour tester le flux EspoCRM.',
    0,
    DATE_ADD('2024-01-01 09:00:00', INTERVAL MOD(n, 730) DAY),
    DATE_ADD('2024-01-01 09:00:00', INTERVAL MOD(n, 730) DAY),
    DATE_ADD('2024-01-01 09:00:00', INTERVAL MOD(n, 730) DAY),
    1
FROM _fixture_numbers AS numbers
WHERE n <= 1000
  AND NOT EXISTS (
      SELECT 1
      FROM account AS existing_account
      WHERE existing_account.id = CONCAT('acct', LPAD(numbers.n, 13, '0'))
  );

INSERT INTO contact (
    id,
    deleted,
    salutation_name,
    first_name,
    last_name,
    description,
    do_not_call,
    address_street,
    address_city,
    address_country,
    address_postal_code,
    created_at,
    modified_at,
    stream_updated_at,
    account_id
)
SELECT
    CONCAT('cont', LPAD(n, 13, '0')),
    0,
    ELT(MOD(n - 1, 3) + 1, 'Mr.', 'Ms.', 'Dr.'),
    ELT(MOD(n - 1, 10) + 1, 'Alex', 'Camille', 'Sam', 'Morgan', 'Noa', 'Lea', 'Yanis', 'Emma', 'Hugo', 'Mia'),
    CONCAT('Contact', LPAD(n, 5, '0')),
    'Contact de démonstration rattaché à un compte client.',
    0,
    CONCAT(LPAD(10 + MOD(n, 990), 3, '0'), ' Avenue des Sciences'),
    ELT(MOD(n - 1, 5) + 1, 'Paris', 'Lyon', 'Lille', 'Nantes', 'Toulouse'),
    'France',
    CONCAT('69', LPAD(MOD(n, 900) + 100, 3, '0')),
    DATE_ADD('2024-02-01 09:00:00', INTERVAL MOD(n, 700) DAY),
    DATE_ADD('2024-02-01 09:00:00', INTERVAL MOD(n, 700) DAY),
    DATE_ADD('2024-02-01 09:00:00', INTERVAL MOD(n, 700) DAY),
    CONCAT('acct', LPAD(MOD(n - 1, 1000) + 1, 13, '0'))
FROM _fixture_numbers AS numbers
WHERE n <= 5000
  AND NOT EXISTS (
      SELECT 1
      FROM contact AS existing_contact
      WHERE existing_contact.id = CONCAT('cont', LPAD(numbers.n, 13, '0'))
  );

INSERT INTO opportunity (
    id,
    name,
    deleted,
    amount,
    stage,
    last_stage,
    probability,
    lead_source,
    close_date,
    description,
    created_at,
    modified_at,
    amount_currency,
    stream_updated_at,
    account_id,
    contact_id,
    version_number
)
SELECT
    CONCAT('oppo', LPAD(n, 13, '0')),
    CONCAT('Projet ', ELT(MOD(n - 1, 5) + 1, 'Atlas', 'Nova', 'Orion', 'Pixel', 'Vertex'), ' - ', LPAD(n, 5, '0')),
    0,
    CAST(5000 + MOD(n * 7919, 195000) AS DECIMAL(12, 2)),
    ELT(MOD(n - 1, 6) + 1, 'Prospecting', 'Qualification', 'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost'),
    ELT(MOD(n - 2, 6) + 1, 'Prospecting', 'Qualification', 'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost'),
    CASE
        WHEN MOD(n - 1, 6) = 4 THEN 100
        WHEN MOD(n - 1, 6) = 5 THEN 0
        ELSE 10 + MOD(n * 7, 81)
    END,
    ELT(MOD(n - 1, 5) + 1, 'Website', 'Referral', 'Partner', 'Conference', 'Email'),
    DATE_ADD('2025-01-15', INTERVAL MOD(n * 13, 730) DAY),
    'Opportunité de démonstration générée pour tester les agrégations commerciales.',
    DATE_ADD('2024-03-01 09:00:00', INTERVAL MOD(n, 650) DAY),
    DATE_ADD('2024-03-01 09:00:00', INTERVAL MOD(n, 650) DAY),
    'EUR',
    DATE_ADD('2024-03-01 09:00:00', INTERVAL MOD(n, 650) DAY),
    CONCAT('acct', LPAD(MOD(n - 1, 1000) + 1, 13, '0')),
    CONCAT('cont', LPAD(MOD(n - 1, 5000) + 1, 13, '0')),
    1
FROM _fixture_numbers AS numbers
WHERE n <= 10000
  AND NOT EXISTS (
      SELECT 1
      FROM opportunity AS existing_opportunity
      WHERE existing_opportunity.id = CONCAT('oppo', LPAD(numbers.n, 13, '0'))
  );

-- Deux contacts cohérents par opportunité : le contact principal déjà présent
-- dans opportunity.contact_id et un contact secondaire dans la table de liaison.
INSERT INTO contact_opportunity (
    contact_id,
    opportunity_id,
    role,
    deleted
)
SELECT
    CONCAT('cont', LPAD(MOD(n - 1, 5000) + 1, 13, '0')),
    CONCAT('oppo', LPAD(n, 13, '0')),
    'Primary contact',
    0
FROM _fixture_numbers AS numbers
WHERE n <= 10000
  AND NOT EXISTS (
      SELECT 1
      FROM contact_opportunity AS existing_relation
      WHERE existing_relation.contact_id = CONCAT('cont', LPAD(MOD(numbers.n - 1, 5000) + 1, 13, '0'))
        AND existing_relation.opportunity_id = CONCAT('oppo', LPAD(numbers.n, 13, '0'))
  )
UNION ALL
SELECT
    CONCAT('cont', LPAD(MOD(n, 5000) + 1, 13, '0')),
    CONCAT('oppo', LPAD(n, 13, '0')),
    'Influencer',
    0
FROM _fixture_numbers AS numbers
WHERE n <= 10000
  AND NOT EXISTS (
      SELECT 1
      FROM contact_opportunity AS existing_relation
      WHERE existing_relation.contact_id = CONCAT('cont', LPAD(MOD(numbers.n, 5000) + 1, 13, '0'))
        AND existing_relation.opportunity_id = CONCAT('oppo', LPAD(numbers.n, 13, '0'))
  );

COMMIT;

DROP TEMPORARY TABLE IF EXISTS _fixture_numbers;

-- Contrôles de résultat.
SELECT 'account' AS table_name, COUNT(*) AS generated_rows
FROM account
WHERE id LIKE 'acct_____________'
UNION ALL
SELECT 'contact', COUNT(*)
FROM contact
WHERE id LIKE 'cont_____________'
UNION ALL
SELECT 'opportunity', COUNT(*)
FROM opportunity
WHERE id LIKE 'oppo_____________'
UNION ALL
SELECT 'contact_opportunity', COUNT(*)
FROM contact_opportunity
WHERE opportunity_id LIKE 'oppo_____________';
