---
document : Réseau — exposer MinIO à Airbyte Cloud via Cloudflare
concerne : flux A et B
mise_a_jour : 2026-11-13
---

# Réseau — exposer MinIO à Airbyte Cloud via Cloudflare

> MinIO tourne localement dans Docker et expose son API S3 sur le port `9000`. Airbyte Cloud
> ne peut pas joindre `localhost`. Un Quick Tunnel Cloudflare publie temporairement cette API
> en HTTPS, sans ouvrir le moindre port entrant sur le poste.

```text
MinIO :9000 → cloudflared (sortant) → https://<nom>.trycloudflare.com → Airbyte Cloud
```

## 1. Objectif

Rendre l'API S3 de MinIO joignable depuis Airbyte Cloud, le temps d'un job, en conservant la
console d'administration strictement locale.

## 2. Prérequis

```powershell
docker compose up -d minio
docker ps
Invoke-WebRequest http://localhost:9000/minio/health/live
```

Une réponse positive confirme que l'API répond. La console reste sur `http://localhost:9001`
et **ne doit jamais être publiée** par le tunnel.

Le dépôt contient `cloudflared-windows-386.exe`. Vérifier que son architecture correspond au
système, ou installer `cloudflared` depuis la distribution officielle Cloudflare.

## 3. Mise en œuvre

### 3.1 Démarrer le tunnel

```powershell
cd <racine du projet>
.\cloudflared-windows-386.exe tunnel --url http://localhost:9000

# si cloudflared est dans le PATH
cloudflared tunnel --url http://localhost:9000
```

La commande affiche une URL de la forme `https://<nom>.trycloudflare.com`. La fenêtre
PowerShell reste ouverte pendant toute la synchronisation ; `Ctrl+C` arrête le tunnel.

### 3.2 L'URL change à chaque démarrage

C'est le principal piège de ce montage. L'URL d'un Quick Tunnel est temporaire : une URL
valide aujourd'hui devient invalide dès que le processus `cloudflared` s'arrête, et les
synchronisations échouent alors sur une erreur de connexion.

Procédure à chaque redémarrage :

1. copier la nouvelle URL ;
2. mettre à jour l'endpoint de la source **et** de la destination MinIO dans Airbyte ;
3. relancer **Test connection** ;
4. seulement ensuite, lancer la synchronisation ;
5. consigner l'URL, la date et l'heure dans les preuves du job.

L'URL n'est jamais écrite en dur dans un script, un manifeste, une configuration permanente
ou un rapport rendu.

### 3.3 Paramètres Airbyte

| Paramètre | Valeur |
|---|---|
| Endpoint S3 | URL `https://<nom>.trycloudflare.com` du tunnel en cours |
| Bucket | `dsidraw` (lots API) · `kagglesources` (lot CSV) |
| Access key / Secret key | Compte MinIO dédié, stocké comme secret Airbyte |
| Région | valeur acceptée par le connecteur, par exemple `us-east-1` |
| SSL / HTTPS | activé |
| Path-style access | activé si le connecteur le demande |
| Format de sortie | JSON Lines, sans compression |

Un compte MinIO dédié, limité aux buckets du projet, est préférable au compte
administrateur. Les identifiants ne figurent ni dans un fichier Markdown, ni dans une
capture, ni dans Git.

### 3.4 Organisation des objets

```text
dsidraw/
  api/api_works/<AAAA_MM_JJ>_<horodatage>_<n>.jsonl
  api/api_authors/...
  api/api_institutions/...

kagglesources/
  <lot CSV daté>
```

Les buckets restent **privés**. Airbyte doit lire le préfixe du lot attendu, et non
l'ensemble du bucket : cette règle évite de rejouer tous les anciens lots.

> **Écart assumé avec la convention du sujet.** Le sujet recommande
> `s3://dsid-raw/raw/api/<source>/extraction_date=YYYY-MM-DD/`. La date du lot figure ici
> dans le nom de l'objet, généré par le connecteur S3, plutôt que dans une partition.
> L'historique est conservé et chaque lot reste identifiable.

## 4. Vérification

```powershell
# 1. MinIO répond localement
Invoke-WebRequest http://localhost:9000/minio/health/live

# 2. le tunnel atteint l'API
Invoke-WebRequest https://<nom>.trycloudflare.com/minio/health/live
```

Un health check positif ne remplace pas un test S3 avec les identifiants et le bucket. Dans
Airbyte, dans l'ordre : enregistrer l'URL, **Test connection**, vérifier l'accès au bucket,
vérifier le préfixe, lancer une synchronisation de test, contrôler l'objet produit ou les
lignes chargées en Bronze.

> **Incident rencontré — validation HTTPS du connecteur Source S3.** La branche actuelle du
> connecteur applique une validation HTTPS aux endpoints S3 compatibles personnalisés. Un
> MinIO exposé en `http://…:9000` peut être refusé même si le service fonctionne. Le Quick
> Tunnel fournit un endpoint HTTPS au certificat reconnu, ce qui satisfait la validation.
> Le simple démarrage des conteneurs ne vaut pas validation : seuls un *Test connection*
> réussi et une synchronisation complète font foi.

## 5. Limites et sécurité

Le Quick Tunnel convient aux tests et aux démonstrations, pas à une exploitation durable :
l'URL change à chaque recréation, le tunnel dépend du processus local et de la connexion
Internet, fermer PowerShell coupe l'accès, et l'URL publique expose un service local tant
que le tunnel vit. Les performances ne sont pas garanties. Pour un usage durable, un tunnel
nommé avec domaine stable, politique d'accès et configuration versionnée sans secrets est
préférable.

Règles appliquées :

- ne jamais publier le port `9001` de la console ;
- conserver les buckets privés ;
- utiliser des identifiants MinIO dédiés et limités ;
- ne jamais transmettre de secret dans l'URL ;
- arrêter le tunnel après le job (`Ctrl+C`) ;
- régénérer les credentials MinIO en cas d'exposition ;
- vérifier les journaux `cloudflared`, Airbyte et MinIO en cas d'accès inattendu.

## 6. Preuves à conserver

Date et heure de démarrage, URL temporaire générée, commande utilisée sans secret, résultat
du health check local, résultat du health check HTTPS, résultat du *Test connection*
Airbyte, nom du bucket et préfixe utilisé, nom et statut du job, objet MinIO ou volume
Bronze produit.

L'URL temporaire peut servir de preuve d'exécution, mais elle est masquée dans tout document
rendu et ne constitue jamais une configuration permanente.
