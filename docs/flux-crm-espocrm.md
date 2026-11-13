---
document : Flux C — EspoCRM via MariaDB
flux : C
chemin : EspoCRM → MariaDB → tunnel SSH → Airbyte → Bronze → Silver
mise_a_jour : 2026-11-13
---

# Flux C — EspoCRM via MariaDB

> Troisième chemin d'ingestion. Les données commerciales saisies dans EspoCRM sont lues
> directement dans MariaDB, au travers d'un tunnel SSH inversé, puis chargées en Bronze et
> standardisées en Silver.

```text
EspoCRM → MariaDB → tunnel SSH → Airbyte (MySQL) → Neon / bronze → Neon / silver
```

Ce flux **ne passe pas par MinIO** : la source opérationnelle est la base relationnelle
elle-même. Il ne comporte donc qu'une seule connexion Airbyte.

## 1. Objectif et périmètre

Transporter les comptes, contacts et opportunités d'EspoCRM afin d'en permettre l'analyse,
et **prouver qu'une information nouvellement saisie dans le CRM arrive effectivement en
Bronze** (§7).

## 2. Contrat de données

### 2.1 Source et accès

| Paramètre | Valeur |
|---|---|
| Source Airbyte | `espocrm` — connecteur MySQL v3.53.10 |
| Destination | `neon_postgres`, schéma `bronze` |
| Base | `espocrm` |
| Hôte vu par Airbyte | `127.0.0.1` **sur la VM relais**, extrémité du tunnel SSH |
| Chiffrement | `required` |
| Authentification au rebond | SSH Key Authentication, utilisateur `opc`, clé dédiée à Airbyte |
| Adresse de la VM | masquée dans toute documentation rendue |

La mise en place du tunnel est décrite dans
[`11-reseau-tunnel-ssh-mariadb.md`](./11-reseau-tunnel-ssh-mariadb.md).

Avant chaque synchronisation, vérifier que le tunnel est actif, que le port `13306` écoute
sur la VM, que MariaDB accepte la connexion et que le *Test connection* d'Airbyte réussit.

> **Point ouvert — compte de lecture.** Le sujet impose un compte Airbyte **en lecture
> seule**. Le dépôt provisionne ce compte : `init/mariadb/01_airbyte_user.sh` crée
> l'utilisateur `airbyte` avec `GRANT SELECT` uniquement. Or la source est actuellement
> configurée avec l'utilisateur `espocrm`, qui est le compte applicatif et dispose des
> droits d'écriture. **À corriger avant le rendu** : basculer la source sur `airbyte` et son
> mot de passe (`AIRBYTE_MARIADB_PASSWORD`), puis relancer le test de connexion.

### 2.2 Nature et licence des données

Les données de test sont générées par
[`001_espocrm_mariadb_fake_data.sql`](../sql/fixtures/001_espocrm_mariadb_fake_data.sql) :
1 000 comptes, 5 000 contacts, 10 000 opportunités et environ 20 000 relations. Elles sont
**fictives** et ne représentent ni personne ni entreprise réelle.

Les données saisies ensuite dans EspoCRM suivent les règles de confidentialité du projet.
Aucun secret, mot de passe ou identifiant SSH ne figure dans cette documentation.

### 2.3 Tables, grain et clés

Noms physiques vérifiés dans MariaDB — ils ne sont pas devinés.

| Table | Objet métier | Grain | Clé |
|---|---|---|---|
| `account` | Compte ou organisation | Une ligne par compte | `id` `VARCHAR(17)` |
| `contact` | Contact rattaché à un compte | Une ligne par contact | `id` `VARCHAR(17)` |
| `opportunity` | Opportunité commerciale | Une ligne par opportunité | `id` `VARCHAR(17)` |
| `contact_opportunity` | Participation d'un contact à une opportunité | Une ligne par relation | `id` `BIGINT` ; couple (`contact_id`, `opportunity_id`) unique |

```text
contact.account_id            -> account.id
opportunity.account_id        -> account.id
opportunity.contact_id        -> contact.id
contact_opportunity.contact_id     -> contact.id
contact_opportunity.opportunity_id -> opportunity.id
```

Le périmètre s'arrête à ces quatre tables. Aucune autre table EspoCRM n'est ingérée.

### 2.4 Contrat des colonnes

**`account`**

| Colonne | Type source | Utilité |
|---|---|---|
| `id` | `VARCHAR(17)` | Identifiant stable |
| `name` | `VARCHAR` | Nom du compte |
| `website` | `VARCHAR` | Site web |
| `type` | `VARCHAR` | Type commercial |
| `industry` | `VARCHAR` | Secteur d'activité |
| `billing_address_city`, `billing_address_country`, `billing_address_postal_code` | `VARCHAR` | Analyse géographique |
| `created_at`, `modified_at` | `DATETIME` | Création ; curseur incrémental |
| `stream_updated_at` | `DATETIME` | Date technique EspoCRM |
| `deleted` | `TINYINT(1)` | Suppression logique |

**`contact`**

| Colonne | Type source | Utilité |
|---|---|---|
| `id` | `VARCHAR(17)` | Identifiant stable |
| `salutation_name` | `VARCHAR` | Civilité |
| `first_name`, `last_name` | `VARCHAR` | Nom ; calcul de `full_name` |
| `address_city`, `address_country`, `address_postal_code` | `VARCHAR` | Analyse géographique |
| `account_id` | `VARCHAR(17)` | Rattachement au compte |
| `do_not_call` | `TINYINT(1)` | Préférence de contact |
| `created_at`, `modified_at` | `DATETIME` | Création ; curseur incrémental |
| `stream_updated_at` | `DATETIME` | Date technique EspoCRM |
| `deleted` | `TINYINT(1)` | Suppression logique |

**`opportunity`**

| Colonne | Type source | Utilité |
|---|---|---|
| `id` | `VARCHAR(17)` | Identifiant stable |
| `name` | `VARCHAR` | Nom de l'opportunité |
| `amount` | `DOUBLE` | Montant commercial |
| `amount_currency` | `VARCHAR(3)` | Devise |
| `stage`, `last_stage` | `VARCHAR` | Étape courante et précédente |
| `probability` | `INTEGER` | Probabilité de 0 à 100 |
| `lead_source` | `VARCHAR` | Origine du prospect |
| `close_date` | `DATE` | Clôture prévisionnelle ou effective |
| `account_id`, `contact_id` | `VARCHAR(17)` | Rattachements commerciaux |
| `created_at`, `modified_at` | `DATETIME` | Création ; curseur incrémental |
| `stream_updated_at` | `DATETIME` | Date technique EspoCRM |
| `deleted` | `TINYINT(1)` | Suppression logique |

**`contact_opportunity`**

| Colonne | Type source | Utilité |
|---|---|---|
| `id` | `BIGINT` | Identifiant de la relation |
| `contact_id` | `VARCHAR(17)` | Contact participant |
| `opportunity_id` | `VARCHAR(17)` | Opportunité concernée |
| `role` | `VARCHAR(50)` | Rôle du contact dans l'opportunité |
| `deleted` | `TINYINT(1)` | Suppression logique |

## 3. Configuration Airbyte

| Connexion | Source | Destination | Mode | Fréquence |
|---|---|---|---|---|
| `espocrm → neon_postgres` | `espocrm` | `neon_postgres` | Incrémental avec curseur | Manuelle |

### 3.1 Curseurs

| Table | Curseur | Justification |
|---|---|---|
| `account` | `modified_at` | Capture créations et modifications ; `created_at` manquerait les mises à jour. |
| `contact` | `modified_at` | Capture les modifications et les changements de rattachement. |
| `opportunity` | `modified_at` | Capture montant, étape, probabilité, rattachements et date de clôture. |
| `contact_opportunity` | `id`, insertions seulement | La table n'a pas de `modified_at`. Le curseur auto-incrémenté ne détecte ni les changements de `role` ni les suppressions : un rechargement complet périodique est nécessaire. |

`deleted` reste sélectionné pour gérer les suppressions logiques.

> **Observation du 13/11/2026.** `contact` a chargé 2 lignes et `opportunity` 1 ligne, ce
> qui démontre le bon fonctionnement du curseur `modified_at`. En revanche `account` a
> chargé 1 001 lignes et `contact_opportunity` 20 001, soit la totalité des tables. Pour
> `contact_opportunity`, c'est le comportement documenté ci-dessus. Pour `account`, le
> volume complet indique que le stream est resté en Full Refresh ou que le curseur n'a pas
> été retenu : vérifier l'onglet *Schema* de la connexion. Le sujet accepte un Full Refresh
> **s'il est justifié**.

## 4. Couche Bronze

```text
bronze.espocrm_account
bronze.espocrm_contact
bronze.espocrm_opportunity
bronze.espocrm_contact_opportunity
```

Pour ce flux, le connecteur expose **directement les colonnes MariaDB** : les vues Silver ne
lisent pas `_airbyte_data`. Les colonnes techniques `_airbyte_raw_id` et
`_airbyte_extracted_at` sont néanmoins conservées.

## 5. Couche Silver

| Script | Vue | Transformation |
|---|---|---|
| [`009_espocrm_account.sql`](../sql/silver/009_espocrm_account.sql) | `silver.espocrm_account` | Normalise les noms (`account_name`, `account_type`, `billing_city`…), convertit les dates, exclut les comptes supprimés ou sans nom. |
| [`010_espocrm_contact.sql`](../sql/silver/010_espocrm_contact.sql) | `silver.espocrm_contact` | Calcule `full_name`, conserve le rattachement au compte, exclut les contacts supprimés ou sans nom. |
| [`011_espocrm_opportunity.sql`](../sql/silver/011_espocrm_opportunity.sql) | `silver.espocrm_opportunity` | `amount` → `NUMERIC(14,2)`, probabilité 0–100, étape valide, `close_date ≥ created_at`. |
| [`012_espocrm_contact_opportunity.sql`](../sql/silver/012_espocrm_contact_opportunity.sql) | `silver.espocrm_contact_opportunity` | Déduplique les couples et ne conserve que les relations dont les deux extrémités existent en Silver. |
| [`013_espocrm_reconciliation.sql`](../sql/silver/013_espocrm_reconciliation.sql) | `silver.v_espocrm_reconciliation` | Compare lignes Bronze, clés distinctes, doublons et lignes conservées. |

Traçabilité commune :

```text
id               <- colonne métier MariaDB id
source_record_id <- _airbyte_raw_id
source_system    <- 'espocrm_mariadb'
ingested_at_utc  <- _airbyte_extracted_at
```

Les vues portent des clés logiques. De vraies contraintes `PRIMARY KEY` et `FOREIGN KEY`
demanderaient de matérialiser les tables.

### 5.1 Ordre d'exécution

```text
009_espocrm_account.sql
010_espocrm_contact.sql
011_espocrm_opportunity.sql
012_espocrm_contact_opportunity.sql
013_espocrm_reconciliation.sql
004_espocrm_silver_checks.sql
```

Les scripts ne modifient jamais Bronze : ils créent ou remplacent des vues et sont rejouables
après chaque synchronisation.

## 6. Contrôles et résultats

Script : [`004_espocrm_silver_checks.sql`](../sql/tests/004_espocrm_silver_checks.sql), lancé
par [`preuves/run_tests.ps1`](../preuves/run_tests.ps1) ; sortie dans `preuves/logs/`.

### 6.1 Volumes mesurés le 13/11/2026

| Entité | Bronze | Clés distinctes | Doublons Bronze | Exclusions | Silver |
|---|---:|---:|---:|---:|---:|
| `account` | 3 001 | 1 001 | 2 000 | 0 | 1 001 |
| `contact` | 10 002 | 5 002 | 5 000 | 0 | 5 002 |
| `opportunity` | 20 001 | 10 001 | 10 000 | 1 115 | 8 886 |
| `contact_opportunity` | 20 001 | 20 001 | 0 | 2 230 | 17 771 |

Les doublons Bronze viennent des rejeux en mode Append. Ils sont **éliminés en Silver** :
c'est exactement le comportement attendu de la règle de dédoublonnage.

### 6.2 Résultats des contrôles

Les **27 contrôles d'intégrité retournent `0`** : clés non nulles, unicité, absence de
doublons, traçabilité, montants, probabilités, étapes, cohérence des dates, existence des
comptes et contacts référencés, relations non orphelines, nommage `snake_case`.

> **Lecture de la réconciliation.** Le script affiche une colonne
> `unexplained_difference` calculée comme `distinct_keys − silver_rows`. Or la vue
> `v_espocrm_reconciliation` définit déjà `excluded_rows` par cette même soustraction : les
> deux colonnes mesurent la même quantité, et l'écart « inexpliqué » est l'écart expliqué,
> recompté. Le résidu réel, `distinct_keys − excluded_rows − silver_rows`, vaut **0** pour
> les quatre entités.
>
> Les 1 115 opportunités écartées ne satisfont pas un filtre de `011` : montant absent ou
> négatif, probabilité hors de 0–100, étape hors nomenclature, ou clôture antérieure à la
> création. Ces incohérences viennent du script de données fictives, qui ne garantit pas la
> cohérence métier. `012` ne conservant que les relations dont les deux extrémités existent
> en Silver, ces 1 115 opportunités entraînent mécaniquement 2 230 relations écartées, soit
> environ deux par opportunité — le ratio du jeu de données.
>
> **Correctif.** Corriger la formule du contrôle, puis ventiler les exclusions par règle
> pour les justifier une à une.

### 6.3 Écart de couverture

Pour `espocrm_contact_opportunity`, le test de clé non nulle porte sur `source_record_id`
mais pas sur `id`. Ajouter un contrôle `relation_null_id`.

## 7. Preuve du delta CRM

Le sujet exige de prouver qu'une information nouvellement saisie est collectée. Protocole en
cinq étapes : état initial, saisie, synchronisation, Bronze, preuve.

### 7.1 Saisie du 13/11/2026

| Entité | Valeurs | Identifiant |
|---|---|---|
| Account | `Iloniavo Randriamanga`, type `Customer`, secteur `Architecture` | `6af6e2cae8100f4c9` |
| Contact 1 | `Tori Kelly`, rattaché au compte `Pixel Systems 0729` | — |
| Contact 2 | `John Doe`, rattaché au nouveau compte | — |
| Opportunity | `Vente Télephone`, 500,00 $, étape `Prospecting`, probabilité 87 %, clôture au 20/11, contact `John Doe` | `6af6e3f0e6664f12a` |

### 7.2 Avant et après

Le même filtre est appliqué sur `bronze.espocrm_account` : `where name equals
« Iloniavo Randriaman… »`. Avant la synchronisation, aucune ligne. Après, une ligne portant
l'identifiant saisi, le type `Customer`, `deleted = FALSE`, et les colonnes techniques
`_airbyte_extracted_at` = 2026-11-13 10:29:06 et `_airbyte_generation_id` = 2.

Les **clés distinctes en Bronze** — 1 001 comptes, 5 002 contacts, 10 001 opportunités —
correspondent exactement à l'état d'EspoCRM après la saisie : les quatre entités créées sont
donc toutes arrivées, pas seulement le compte vérifié ligne à ligne.

```sql
-- Retrouver en Bronze les entités créées dans EspoCRM
SELECT id, name, type, deleted, _airbyte_extracted_at
FROM   bronze.espocrm_account
WHERE  id = '6af6e2cae8100f4c9';

SELECT o.id, o.name, o.amount, o.stage, o.account_id, o._airbyte_extracted_at
FROM   bronze.espocrm_opportunity o
WHERE  o.id = '6af6e3f0e6664f12a';

SELECT co.contact_id, co.opportunity_id
FROM   bronze.espocrm_contact_opportunity co
WHERE  co.opportunity_id = '6af6e3f0e6664f12a';
```

## 8. Preuves à conserver

Captures de la source `espocrm` et de sa configuration SSH, de la destination
`neon_postgres`, de la connexion et de son mode incrémental ; curseurs configurés par table ;
résultat du test du tunnel ; nombre de lignes par stream ; date et heure de synchronisation ;
fiches EspoCRM des entités créées avec leurs identifiants ; résultat des contrôles Silver et
de `silver.v_espocrm_reconciliation`.

Les captures contenant des coordonnées personnelles doivent être masquées avant diffusion :
le sujet proscrit les données personnelles dans le rendu.
