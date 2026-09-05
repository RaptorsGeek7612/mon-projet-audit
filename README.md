# mon-projet-audit

Squelette de projet d'audit Web3 : contrat Solidity (Foundry), tests unitaires/fuzz/invariants, exécution symbolique (Halmos) et vérification formelle (Certora), le tout branché sur une CI GitHub Actions.

## Structure

```
mon-projet-audit/
├── .github/workflows/security-checks.yml   # CI: forge fmt/build/test, Slither, Halmos, Certora
├── certora/
│   ├── conf/Vault.conf                     # Config Certora (fichiers, spec, options)
│   └── specs/Vault.spec                    # Règles CVL
├── src/
│   ├── Vault.sol                           # Contrat cible de l'audit
│   └── interfaces/IERC20.sol
├── test/
│   ├── Vault.t.sol                         # Tests unitaires, fuzz, invariant Foundry
│   ├── mocks/MockERC20.sol
│   └── halmos/Vault.halmos.sol             # Tests d'exécution symbolique Halmos
├── foundry.toml
└── remappings.txt
```

## Prérequis

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, `anvil`) — déjà utilisé pour ce squelette.
- Python 3 + pip, pour Halmos et Certora :
  ```shell
  sudo apt-get install -y python3-pip python3-venv   # si pip/venv ne sont pas déjà présents
  python3 -m venv .venv && source .venv/bin/activate
  pip install halmos certora-cli
  ```
- Une clé Java 17+ pour le Certora Prover (`sudo apt-get install -y openjdk-17-jdk`), et une clé API Certora (`export CERTORAKEY=...`) pour lancer `certoraRun` en local.

## Commandes

```shell
forge build              # compilation
forge fmt --check        # style
forge test -vvv          # tests unitaires + fuzz + invariants

halmos --contract VaultHalmosTest        # exécution symbolique

certoraRun certora/conf/Vault.conf        # vérification formelle (nécessite CERTORAKEY)
```

## CI

Le workflow `.github/workflows/security-checks.yml` s'exécute sur chaque push/PR vers `main` :
- `foundry` : format, build, tests (échoue le pipeline si un test casse) ;
- `slither` : analyse statique, échoue sur les findings de sévérité `high` ;
- `halmos` : exécution symbolique des propriétés `check_*` ;
- `certora` : vérification formelle, seulement si le secret de repo `CERTORAKEY` est défini (sinon le job passe en no-op).
