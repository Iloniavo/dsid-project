---
document : Réseau — tunnel SSH inversé entre MariaDB et Airbyte Cloud
concerne : flux C
mise_a_jour : 2026-11-13
---

# Réseau — tunnel SSH inversé entre MariaDB et Airbyte Cloud

> MariaDB tourne dans Docker sur un poste Windows. Airbyte Cloud ne peut pas joindre
> `localhost`. Une VM Oracle Cloud sert de relais : le poste y ouvre une connexion SSH
> **sortante** qui crée un port d'écoute, et Airbyte se connecte à ce port par SSH. Le port
> MariaDB n'est jamais exposé sur Internet.

## 1. Objectif

Donner à Airbyte Cloud un accès en lecture à la base `espocrm`, sans ouvrir de port entrant
sur le poste ni sur la box.

## 2. Architecture

```text
                  AIRBYTE CLOUD
                       |
                       |  connexion SSH, port 22
                       v
              ORACLE CLOUD (VM)
              Oracle Linux 9
              IP : xxx.xxx.xxx.xxx   (masquée)
              Utilisateur : opc
                       |
                 127.0.0.1:13306
                       |
                       |  tunnel SSH inversé
                       v
              WINDOWS (DOCKER)
              MariaDB :3306
              Base : espocrm
```

1. Le poste Windows établit une connexion SSH **sortante** vers la VM.
2. Cette connexion crée un port d'écoute `13306` sur la VM, limité à `127.0.0.1`.
3. Les connexions reçues sur ce port sont redirigées vers le port `3306` de MariaDB.
4. Airbyte Cloud se connecte à la VM par SSH et atteint ainsi MariaDB.

> L'adresse IP publique de la VM est masquée dans toute documentation rendue. Elle figure
> dans la configuration Airbyte, jamais dans le dépôt.

## 3. Mise en œuvre

### 3.1 La VM Oracle Cloud

| Paramètre | Valeur |
|---|---|
| Système | Oracle Linux 9 |
| Utilisateur SSH | `opc` |
| Adresse IP publique | `xxx.xxx.xxx.xxx` |
| Port SSH | `22` |

Opérations réalisées : création d'un VCN et d'un sous-réseau public, attribution d'une
adresse IPv4 publique, autorisation du trafic entrant TCP sur le port 22 dans les règles
réseau. **Le port 13306 n'est pas ouvert** dans ces règles : il reste lié à `127.0.0.1`.

### 3.2 Les deux paires de clés

L'accès d'administration et l'accès d'Airbyte sont séparés.

| Fichier | Usage |
|---|---|
| `oracle-relay.key` | Administration de la VM depuis le poste |
| `airbyte_oracle` | Clé privée fournie à Airbyte Cloud |
| `airbyte_oracle.pub` | Clé publique autorisée sur la VM |

```powershell
ssh-keygen -t rsa -b 4096 -m PEM `
  -f "$HOME\.ssh\airbyte_oracle" `
  -C "airbyte-cloud"
```

Passphrase laissée vide, le connecteur ne la gérant pas. Autorisation de la clé publique sur
la VM :

```powershell
Get-Content "$HOME\.ssh\airbyte_oracle.pub" |
  ssh -i "$HOME\.ssh\oracle-relay.key" opc@xxx.xxx.xxx.xxx `
  "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
```

### 3.3 Ouvrir le tunnel

```powershell
ssh -i "$HOME\.ssh\oracle-relay.key" `
  -N `
  -o ExitOnForwardFailure=yes `
  -R 127.0.0.1:13306:127.0.0.1:3306 `
  opc@xxx.xxx.xxx.xxx
```

| Paramètre | Rôle |
|---|---|
| `-N` | N'exécute aucune commande distante |
| `-R` | Transfert de port inversé |
| `127.0.0.1:13306` | Adresse et port d'écoute sur la VM |
| `127.0.0.1:3306` | MariaDB tel que vu depuis le poste |
| `ExitOnForwardFailure=yes` | Interrompt la connexion si le transfert échoue |

La fenêtre PowerShell doit rester ouverte : fermer la session ferme le tunnel.

### 3.4 Paramètres Airbyte

| Paramètre | Valeur |
|---|---|
| Database Host | `127.0.0.1` — vu **depuis la VM**, pas depuis Airbyte |
| Database Port | `13306` |
| Database Name | `espocrm` |
| Username / Password | compte MariaDB dédié en lecture seule (voir §5) |
| Encryption | `required` |
| SSH Host | `xxx.xxx.xxx.xxx` |
| SSH Port | `22` |
| SSH User | `opc` |
| SSH Authentication | SSH Key |
| SSH Private Key | contenu de `airbyte_oracle`, stocké comme secret Airbyte |

## 4. Vérification

Depuis une seconde session SSH sur la VM :

```bash
ss -lnt | grep 13306
# LISTEN 0 128 127.0.0.1:13306 0.0.0.0:*

nc -vz 127.0.0.1 13306
# connexion réussie
```

Puis la clé dédiée :

```powershell
ssh -i "$HOME\.ssh\airbyte_oracle" -o IdentitiesOnly=yes opc@xxx.xxx.xxx.xxx
```

Enfin, le *Test connection* d'Airbyte doit réussir avant toute synchronisation. Il valide à
la fois le rebond SSH et l'accès MariaDB.

## 5. Limites et sécurité

- La session PowerShell qui porte le tunnel doit rester active ; une mise en veille ou une
  perte de réseau l'interrompt.
- La clé privée `airbyte_oracle` n'est jamais communiquée ni versionnée.
- Le port `13306` reste lié à `127.0.0.1` et n'est pas ouvert dans les règles réseau Oracle.
- **Le compte MariaDB transmis à Airbyte doit être un compte de lecture.**
  `init/mariadb/01_airbyte_user.sh` crée l'utilisateur `airbyte` avec `GRANT SELECT`
  uniquement ; c'est ce compte qui doit être configuré, et non le compte applicatif
  `espocrm`. Voir le point ouvert signalé dans
  [`03-flux-crm-espocrm.md`](./03-flux-crm-espocrm.md).
- Pour un usage durable, automatiser le démarrage et la reconnexion du tunnel, par exemple
  avec `autossh` ou une tâche planifiée.

## 6. Preuves à conserver

Capture de la source Airbyte et de sa section SSH avec l'adresse masquée, sortie de
`ss -lnt | grep 13306`, résultat de `nc -vz`, résultat du *Test connection*, date et heure
de la synchronisation, nombre de lignes par stream.

Aucun contenu de clé privée, aucun mot de passe et aucune adresse IP publique ne figure
dans le rendu.
