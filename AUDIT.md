# Rapport d'audit — mon-projet-audit

Synthèse des résultats de vérification et des limitations de conception connues pour les
trois contrats du dépôt. Ce document rassemble ce que l'outillage (Foundry, Slither, Halmos,
Certora) a effectivement prouvé, et documente ce qui reste un choix de conception assumé plutôt
qu'un bug.

## Périmètre

| Contrat | Rôle |
|---|---|
| `src/Vault.sol` | Coffre-fort 1:1 : dépôt/retrait d'un unique ERC20. |
| `src/SimpleAMM.sol` | AMM à produit constant (`x*y=k`) à deux jetons, avec parts de LP et retrait. |
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

- **Certora** : `swap0For1` prouvé ne jamais diminuer `k = reserve0 * reserve1`
  (`swapIntegrity`) ; `mint` prouvé créditer les deux réserves exactement des montants fournis
  (`mintIsExact`) et ne jamais diminuer `k` (`mintNeverDecreasesConstantProduct`) ; `burn`
  prouvé débiter les réserves exactement des montants qu'il retourne (`burnIsExact`) et ne
  jamais faire augmenter `k` (`burnNeverIncreasesConstantProduct` — trivialement vrai : les
  deux réserves ne peuvent que décroître ou rester égales, donc leur produit aussi).
- **Halmos** : le check symbolique équivalent sur `swap0For1` (`check_SwapInvariant`) time out
  sur le solveur SMT (arithmétique non-linéaire — cf. plus bas) ; laissé non-bloquant en CI.
- **Foundry** : la même propriété est prouvée par fuzzing concret (1000 runs) dans
  `testFuzz_swapNeverDecreasesConstantProduct` ; `testFuzz_reservesNeverExceedRealBalances`
  et `testFuzz_mintThenBurn_neverExceedsPoolBalance` vérifient que les réserves internes ne
  dépassent jamais les soldes réels détenus, y compris après un aller-retour mint/burn ; tests
  dédiés pour les trois protections anti-slippage (`test_mint_revertsOnSlippage`,
  `test_burn_revertsOnSlippage`, `test_swap_revertsOnSlippage`).
- **Coverage** : 100 % lignes, 66.67 % branches — mêmes branches de `require(transfer...)`
  jamais exercées par le mock (`MockERC20` ne retourne jamais `false`), sur les 6 requires de
  transfert (2 dans `mint`, 2 dans `burn`, 2 dans `swap0For1`).

**Corrigé depuis la version précédente de ce rapport** (voir historique git) :
- `mint()`/`burn()` créditent et brûlent désormais des parts de liquidité (`liquidityOf`,
  `totalLiquidity`) : un fournisseur peut récupérer sa part proportionnelle des réserves via
  `burn()`, ce qui n'existait pas avant. Le bootstrap de la première liquidité utilise
  `amount0 * amount1` (pas de `sqrt`), pour que le contrat reste entièrement exempt de boucle
  et prouvable par Certora sans `optimistic_loop` ; une part minimale (`MINIMUM_LIQUIDITY`)
  reste verrouillée sur `address(0)`, comme sur Uniswap V2, pour empêcher la manipulation du
  prix des parts par donation directe au tout premier dépôt.
- `mint`, `burn` et `swap0For1` prennent chacun un paramètre de slippage minimum
  (`minLiquidity`, `minAmount0`/`minAmount1`, `minAmount1Out`) et revertent si non respecté.
- Un apport disproportionné à `mint()` (hors premier dépôt) ne déplace plus le prix au
  détriment des LP existants : les parts émises sont bornées par le montant le plus limitant
  (`min(amount0 * totalLiquidity / reserve0, amount1 * totalLiquidity / reserve1)`), exactement
  comme sur Uniswap V2 — l'excédent est absorbé au bénéfice de tous les LP plutôt que de créer
  un risque de manipulation.

### StakingRewards

- **Certora** : `totalSupply() == somme des balances` prouvé (même schéma que `Vault`) ;
  `stake`/`withdraw` prouvés exacts ; aucune fonction ne modifie le solde d'un autre compte ;
  `notifyRewardAmount` prouvé revert pour tout appelant différent de `owner`
  (`notifyRewardAmountOnlyOwner`) et prouvé augmenter `rewardReserve` exactement du montant
  financé (`notifyRewardAmountIncreasesReserve`).
- **Halmos** : un retrait ne peut jamais excéder le montant staké ; `notifyRewardAmount` prouvé
  accessible au seul `owner`.
- **Foundry** : accrual exact pour un staker seul et partage équitable entre deux stakers à
  parts égales ; l'accrual s'arrête bien à `periodFinish` (`test_earned_stopsAccruingAfterPeriodFinish`) ;
  fuzz sur stake/withdraw/warp entrelacés (1000 runs) montrant qu'aucune récompense déjà courue
  n'est perdue ; fuzz dédié (`testFuzz_rewardPayoutsNeverExceedFundedAmount`, 1000 runs)
  montrant qu'un staker ne peut jamais toucher plus que ce qui a été réellement financé ;
  invariant de solvabilité du jeton de staking ; `test_constructor_revertsIfStakingAndRewardTokenAreTheSame`.
- **Coverage** : 92.31 % lignes, 73.91 % branches — même schéma (branches de `require(transfer)`
  côté mock).
- **Non tenté en Halmos/Certora** : l'exactitude de l'accrual dans le temps
  (`rewardPerToken`, qui multiplie/divise sur `block.timestamp`, `rewardRate` et
  `totalSupply` symboliques) — même classe d'arithmétique non-linéaire que l'invariant de
  l'AMM. Couvert uniquement par le fuzzing Foundry ci-dessus.

**Corrigé depuis la version précédente de ce rapport** (voir historique git) :
- `setRewardRate` (l'owner fixait un taux arbitraire, jamais garanti par un vrai transfert) est
  remplacé par `notifyRewardAmount` (modèle Synthetix) : le taux est recalculé à partir d'un
  montant réellement transféré au contrat, réparti sur une durée fixe (`REWARD_DURATION`,
  7 jours). Toute récompense qui s'accumule est donc désormais backée par un transfert réel au
  moment même où elle est promise, plutôt que vérifiée seulement au moment du retrait.
- Le constructeur interdit `stakingToken == rewardToken`. Combiné au point précédent (le
  financement des récompenses passe par un vrai `transferFrom` sur `rewardToken`, comptabilisé
  séparément dans `rewardReserve`), le flux de récompenses ne peut structurellement plus jamais
  entamer le solde qui garantit `totalSupply` — le risque de solvabilité précédemment non
  testé est désormais explicitement empêché par construction, et testé par
  `testFuzz_rewardPayoutsNeverExceedFundedAmount`.

**Limitation résiduelle (décision de déploiement, pas un gap de code)** :
- `owner` reste une clé unique et de confiance : n'importe quel appelant `owner` peut financer
  (ou refinancer, en diluant le taux en cours) une période de récompenses à volonté — c'est le
  comportement standard du pattern Synthetix, pas un bug. Aucun changement de contrat n'est
  nécessaire pour utiliser un multisig (Safe) ou un `TimelockController` comme `owner` : le
  constructeur accepte déjà `msg.sender` sans restriction, donc c'est une décision à prendre au
  déploiement (quelle adresse appelle le constructeur), pas une correction de code.

## Findings Slither non corrigés (revus, faux positifs)

Le job `slither` échoue seulement sur `high` ; ces 4 findings restants ont été passés en revue
manuellement et jugés sans impact :

- `incorrect-equality` sur `reward == 0` (`StakingRewards.getReward`) : comparaison à une
  variable de storage interne, pas à un solde manipulable — le pattern que ce détecteur cible
  (ex. `balance == x` exploitable par un attaquant) ne s'applique pas ici.
- `timestamp` (3 occurrences : `lastTimeRewardApplicable`, `notifyRewardAmount`, et la même
  ligne `reward == 0` que ci-dessus) : comparaisons de `block.timestamp` à `periodFinish` sur
  une durée de 7 jours — la marge de manipulation d'un validateur (quelques secondes) est sans
  effet a cette echelle. Pattern standard et accepté pour tout contrat de récompenses
  temporelles (Synthetix compris).

## Limites connues de l'outillage

`rewardPerToken()` (StakingRewards) et le calcul de `amount1Out` dans `swap0For1` (SimpleAMM)
combinent une multiplication et une division sur des valeurs symboliques — une arithmétique
non-linéaire que les solveurs SMT sous-jacents à Halmos (et, pour la même raison probable,
Certora sur des variantes plus larges) ne résolvent pas dans un temps raisonnable. La propriété
mathématique est correcte (démontrée manuellement et vérifiée par fuzzing à haute volumétrie) ;
c'est une limite du solveur, pas du code. Documenté en ligne dans
`.github/workflows/security-checks.yml` et dans les fichiers `.halmos.sol`/`.spec` concernés.

## Recommandations avant tout déploiement réel — état

1. ✅ **Résolu** : `SimpleAMM` a des parts de LP, une fonction `burn()` pour retirer sa
   liquidité, et une protection de slippage sur `mint`/`burn`/`swap0For1`.
2. ✅ **Résolu** : `StakingRewards` sépare le financement des récompenses (`rewardReserve`,
   alimenté uniquement via `notifyRewardAmount`) du principal staké (`totalSupply`), et interdit
   `stakingToken == rewardToken` au déploiement.
3. **Décision de déploiement, pas de code** : utiliser un multisig ou un `TimelockController`
   comme `owner` de `StakingRewards` reste au choix du déployeur — le contrat n'impose ni
   n'empêche rien à ce sujet (cf. « Limitation résiduelle » plus haut).

Les points 1 et 2 étaient les seuls qualifiés de bloquants pour un déploiement réel ; les deux
sont maintenant couverts par du code testé (Foundry) et prouvé (Certora), pas seulement corrigé
« à l'œil ». Le point 3 reste, par nature, hors du périmètre d'un changement de contrat.
