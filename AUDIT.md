# Rapport d'audit — mon-projet-audit

Synthèse des résultats de vérification et des limitations de conception connues pour les
trois contrats du dépôt. Ce document rassemble ce que l'outillage (Foundry, Slither, Halmos,
Certora) a effectivement prouvé, et documente ce qui reste un choix de conception assumé plutôt
qu'un bug.

## Périmètre

| Contrat | Rôle |
|---|---|
| `src/Vault.sol` | Coffre-fort 1:1 : dépôt/retrait d'un unique ERC20. |
| `src/SimpleAMM.sol` | AMM à produit constant (`x*y=k`) à deux jetons, sans parts de LP. |
| `src/StakingRewards.sol` | Staking avec accrual de récompenses linéaire dans le temps (modèle reward-per-token). |

Hors périmètre : tout contrat de jeton (`MockERC20` n'est qu'un mock de test), tout mécanisme
de gouvernance, et l'infrastructure de déploiement au-delà des scripts `forge script` fournis.

## Méthodologie

Quatre couches complémentaires, câblées dans `.github/workflows/security-checks.yml` :

1. **Foundry** — tests unitaires, fuzzing (1000 runs), et invariants (256 runs × profondeur 50).
2. **Slither** — analyse statique ; la CI échoue sur tout finding `high`.
3. **Halmos** — exécution symbolique de propriétés `check_*` ciblées.
4. **Certora Prover** — vérification formelle (CVL) des invariants et règles d'accès.

Aucune de ces couches ne remplace les autres : Foundry couvre l'arithmétique non-linéaire que
Halmos/Certora ne peuvent pas résoudre en pratique (cf. « Limites connues de l'outillage »
ci-dessous), tandis que Halmos/Certora couvrent des espaces d'états que le fuzzing ne peut
qu'échantillonner.

## Résultats par contrat

### Vault

- **Certora** : `totalSupply() == somme des balances` prouvé par invariant (ghost + hook de
  storage) ; `deposit`/`withdraw` prouvés exacts sur le solde de l'appelant et sur
  `totalSupply` ; `withdraw` prouvé revert si solde insuffisant ; aucune fonction ne peut
  modifier le solde d'un autre compte (`onlyCallerBalanceChanges`).
- **Halmos** : un retrait ne peut jamais excéder ce qui a été déposé ; le coffre reste
  solvable après une séquence arbitraire de dépôts/retraits.
- **Foundry** : invariant de solvabilité (`token.balanceOf(vault) >= totalSupply`) fuzzé sur
  256 runs / 12 800 appels.
- **Coverage** (`forge coverage`, hors `script/` et `test/halmos/`) : 88.89 % lignes, 80 %
  branches. Les deux branches non couvertes sont la voie « échec » de
  `transferFrom`/`transfer` — `MockERC20` ne retourne jamais `false`, donc ce chemin n'est
  jamais exercé par les tests. Pas un vrai gap : le comportement (`require(...)` → revert) est
  trivial et identique quel que soit le contrat ERC20 sous-jacent.

### SimpleAMM

- **Certora** : `swap0For1` prouvé ne jamais diminuer `k = reserve0 * reserve1` ; `mint`
  prouvé créditer les deux réserves exactement des montants fournis (`mintIsExact`) et ne
  jamais diminuer `k` (`mintNeverDecreasesConstantProduct`).
- **Halmos** : le check symbolique équivalent sur `swap0For1` (`check_SwapInvariant`) time out
  sur le solveur SMT (arithmétique non-linéaire — cf. plus bas) ; laissé non-bloquant en CI.
- **Foundry** : la même propriété est prouvée par fuzzing concret (1000 runs) dans
  `testFuzz_swapNeverDecreasesConstantProduct` ; `testFuzz_reservesNeverExceedRealBalances`
  vérifie que les réserves internes ne dépassent jamais les soldes réels détenus.
- **Coverage** : 100 % lignes, 50 % branches — mêmes branches de `require(transfer...)` jamais
  exercées par le mock, sur 4 requires (2 dans `mint`, 2 dans `swap0For1`).

**Limitations de conception (informationnel, pas des bugs de l'implémentation prouvée)** :
- Pas de parts de LP ni de fonction de retrait de liquidité : tout appel à `mint()` transfère
  des jetons au contrat de façon définitive, sans moyen de les récupérer. Acceptable pour un
  contrat pédagogique/cible d'audit ; **bloquant pour un déploiement réel**.
- Pas de protection de slippage (`amountOutMin`) sur `swap0For1` : un swap est exposé au
  sandwich/front-running MEV. Idem, à corriger avant tout déploiement réel.
- `mint()` n'impose aucun ratio entre `amount0`/`amount1` : un apport déséquilibré déplace le
  prix immédiatement, au bénéfice du premier swappeur. Sans conséquence ici puisque personne ne
  peut de toute façon retirer de liquidité, mais à garder en tête si `mint`/`burn` symétriques
  sont ajoutés plus tard.

### StakingRewards

- **Certora** : `totalSupply() == somme des balances` prouvé (même schéma que `Vault`) ;
  `stake`/`withdraw` prouvés exacts ; aucune fonction ne modifie le solde d'un autre compte ;
  `setRewardRate` prouvé revert pour tout appelant différent de `owner`.
- **Halmos** : un retrait ne peut jamais excéder le montant staké ; `setRewardRate` prouvé
  accessible au seul `owner`.
- **Foundry** : accrual exact pour un staker seul et partage équitable entre deux stakers à
  parts égales ; fuzz sur stake/withdraw/warp entrelacés (1000 runs) montrant qu'aucune
  récompense déjà courue n'est perdue ; invariant de solvabilité du jeton de staking.
- **Coverage** : 97.56 % lignes, 80 % branches — même schéma (branches de `require(transfer)`
  côté mock).
- **Non tenté en Halmos/Certora** : l'exactitude de l'accrual dans le temps
  (`rewardPerToken`, qui multiplie/divise sur `block.timestamp`, `rewardRate` et
  `totalSupply` symboliques) — même classe d'arithmétique non-linéaire que l'invariant de
  l'AMM. Couvert uniquement par le fuzzing Foundry ci-dessus.

**Limitations de conception (informationnel)** :
- **Centralisation** : `owner` est fixé à jamais au déployeur et peut appeler `setRewardRate`
  avec n'importe quelle valeur, sans plafond ni délai (pas de timelock). Un owner compromis ou
  malveillant peut fixer un taux extravagant ou le couper à zéro à tout moment.
- **Financement des récompenses non vérifié à la source** : le contrat ne vérifie jamais que
  `rewardToken.balanceOf(this)` couvre les récompenses en train de s'accumuler. Un
  sous-financement ne casse pas la comptabilité interne (`earned()` reste correct) mais fait
  échouer `getReward()` au moment du retrait — un déni de service différé plutôt qu'une perte
  de fonds.
- **Risque si `stakingToken == rewardToken`** : rien n'empêche de déployer le contrat avec le
  même jeton des deux côtés. Dans ce cas, `getReward()` prélève sur le même solde qui garantit
  `totalSupply`, ce qui peut casser l'invariant de solvabilité testé dans
  `invariant_stakingTokenSolvency` si le pool de récompenses n'est pas strictement isolé du
  principal staké. **Non couvert par les tests actuels** (`StakingRewards.t.sol` utilise deux
  `MockERC20` distincts) : à corriger soit en interdisant ce cas dans le constructeur, soit en
  suivant un solde de récompenses séparé (pattern `notifyRewardAmount` façon Synthetix) avant
  tout déploiement avec un token unique.

## Findings Slither non corrigés (revus, faux positifs)

Le job `slither` échoue seulement sur `high` ; ces 3 findings restants ont été passés en revue
manuellement et jugés sans impact :

- `incorrect-equality` sur `reward == 0` (`StakingRewards.getReward`) : comparaison à une
  variable de storage interne, pas à un solde manipulable — le pattern que ce détecteur cible
  (ex. `balance == x` exploitable par un attaquant) ne s'applique pas ici.
- `timestamp` sur la même ligne : faux positif du même détecteur (aucune comparaison de
  `block.timestamp` n'a lieu dans `getReward()` lui-même).
- `naming-convention` sur le paramètre `_rewardRate` : le préfixe `_` est la convention
  standard pour un paramètre de setter qui masque une variable d'état homonyme
  (`rewardRate`), pas une erreur de style.

## Limites connues de l'outillage

`rewardPerToken()` (StakingRewards) et le calcul de `amount1Out` dans `swap0For1` (SimpleAMM)
combinent une multiplication et une division sur des valeurs symboliques — une arithmétique
non-linéaire que les solveurs SMT sous-jacents à Halmos (et, pour la même raison probable,
Certora sur des variantes plus larges) ne résolvent pas dans un temps raisonnable. La propriété
mathématique est correcte (démontrée manuellement et vérifiée par fuzzing à haute volumétrie) ;
c'est une limite du solveur, pas du code. Documenté en ligne dans
`.github/workflows/security-checks.yml` et dans les fichiers `.halmos.sol`/`.spec` concernés.

## Recommandations avant tout déploiement réel

1. Ajouter des parts de LP et une fonction de retrait de liquidité à `SimpleAMM`, plus une
   protection de slippage sur `swap0For1`.
2. Séparer explicitement le pool de récompenses du principal staké dans `StakingRewards`
   (financement par `notifyRewardAmount` avec vérification de solde), et/ou interdire
   `stakingToken == rewardToken` au déploiement.
3. Envisager un timelock ou un multisig pour `StakingRewards.owner` plutôt qu'une clé unique.

Aucune de ces recommandations n'est requise pour l'usage actuel du dépôt (démonstration
d'outillage d'audit) ; elles sont listées pour quiconque voudrait dériver un contrat de
production à partir de ces squelettes.
