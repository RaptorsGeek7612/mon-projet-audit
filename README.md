# mon-projet-audit

Squelette de projet d'audit Web3 : contrat Solidity (Foundry), tests unitaires/fuzz/invariants, exécution symbolique (Halmos) et vérification formelle (Certora), le tout branché sur une CI GitHub Actions.

## Structure

```
mon-projet-audit/
├── .github/workflows/security-checks.yml   # CI: forge fmt/build/test, Slither, Halmos, Certora
├── certora/
│   ├── conf/                               # Config Certora par contrat (fichiers, spec, options)
│   │   ├── Vault.conf
│   │   ├── AMM.conf
│   │   └── StakingRewards.conf
│   └── specs/                              # Règles CVL par contrat
│       ├── Vault.spec
│       ├── AMM.spec
│       └── StakingRewards.spec
├── src/
│   ├── Vault.sol                           # Coffre-fort 1:1 deposit/withdraw
│   ├── SimpleAMM.sol                       # AMM x*y=k (mint/swap)
│   ├── StakingRewards.sol                  # Staking a recompenses lineaires (reward-per-token)
│   └── interfaces/IERC20.sol
├── test/
│   ├── Vault.t.sol                         # Tests unitaires, fuzz, invariant Foundry
│   ├── AMM.t.sol
│   ├── StakingRewards.t.sol
│   ├── mocks/MockERC20.sol
│   └── halmos/                             # Tests d'exécution symbolique Halmos
│       ├── Vault.halmos.sol
│       ├── AMM.halmos.sol
│       └── StakingRewards.halmos.sol
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

halmos --contract VaultHalmosTest           # exécution symbolique
halmos --contract AMMHalmosTest
halmos --contract StakingRewardsHalmosTest

certoraRun certora/conf/Vault.conf          # vérification formelle (nécessite CERTORAKEY)
certoraRun certora/conf/AMM.conf
certoraRun certora/conf/StakingRewards.conf
```

## CI

Le workflow `.github/workflows/security-checks.yml` s'exécute sur chaque push/PR vers `master` :
- `foundry` : format, build, tests (échoue le pipeline si un test casse) ;
- `slither` : analyse statique, échoue sur les findings de sévérité `high` ;
- `halmos` : exécution symbolique des propriétés `check_*` (le check AMM non-linéaire est non-bloquant, cf. commentaire dans le workflow) ;
- `certora` : vérification formelle des trois contrats, seulement si le secret de repo `CERTORAKEY` est défini (sinon le job passe en no-op).
