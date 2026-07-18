[README.md](https://github.com/user-attachments/files/30144571/README.md)
# Metric contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Base, HyperEVM
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Any standard ERC-20 — no token whitelist at the contract level. Pool creation is permissionless for any token0 < token1 pair. Curation is at the pool level (classification tiers + optional per-pool address allowlist extensions), not a token allowlist.

Standard: ERC-20 only. USDC and USDT should be considered in scope. If the users create a pool with non-standard ERC20 tokens, the issues related to these are out of scope
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
Factory Owner — trusted. Sets protocol fee defaults and fee caps, poolDeployer (once), protocol-level pause, treasury sweeps.
Pool Admin — semi-trusted, bounded. Sets admin fees (capped), proposes PP changes (timelock-gated), pauses own pool (level 1), configures bin/extension params. Cannot exceed caps or bypass timelocks. If they can exceed caps or bypass timelocks and it leads to Medium or higher severity issue, then it can be valid.
Oracle ADMIN_ROLE (providers/OracleBase) — trusted. Blacklist, integrators, approved factories, registration fee, withdrawEth.
PriceProvider / AnchoredProvider factory (AccessControl) — trusted, but provider params are bounded (below).
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No — we trust the governance of the protocols we integrate with and impose no limitations on their admin-set values
___

### Q: Is the codebase expected to comply with any specific EIPs?
A few examples used within codebase:
ERC-20 — all pool tokens, fees, and transfers (via SafeERC20). Intention: standard token compatibility. Alignment: the protocol trades arbitrary ERC-20 pairs (majors/RWAs). Note: LP positions are NOT tokenized — they're internal salt/share accounting, so the pool itself isn't an ERC-20/721.
EIP-2612 + EIP-712 (Permit) — the router exposes selfPermit / selfPermitAllowed (DAI-style) / selfPermitIfNecessary. Intention: gasless / single-transaction approvals (permit + swap batched via multicall). Alignment: better UX for wallets/aggregators (a core flow-partner audience), no separate approve tx.
EIP-1153 (transient storage) — the pool's transient reentrancy guard (MetricReentrancyGuardTransient) and transient swap/callback context. Intention: cheap per-tx reentrancy protection + callback routing without persistent storage. Alignment: gas efficiency and safety on the swap-callback path; requires Cancun+ (foundry evm_version = prague).
EIP-1014 (CREATE2) → CREATE3 deployment — the router (and the deterministic deploy) use CREATE3. Intention: identical contract addresses across chains. Alignment: one address set for ETH + Base (confirmed in the live deployment), simplifying multi-chain integration.

Issues related to EIP violations can be considered valid if they lead to Medium or higher impact and qualify for Medium or higher severity definition.
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
Price updates in many cases can happen off-chain and get sent to the oracle. Especially for compressed oracles. It's considered that these price updates and oracles will always be correct, and not stale.
___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
Solvency: pool token balances always cover all LP claims + owed fees; every LP can withdraw their proportional share. Withdraw (remove-liquidity) must work even when the pool is paused (pause only blocks swaps).
Swap conservation: exact settlement — the pool receives the owed input (else IncorrectDelta revert) and never creates/leaks value; a trader never receives more than the bin curve allows.
Quote sanity: bid > 0 and bid < ask always (hard invariant; BidIsZero / BidGreaterThanAsk).
Anchored band: every AnchoredPriceProvider quote — including source mode — stays within mid ± (u + floor); an unreviewed source can never push price outside the band.
No trade on bad oracle: swaps revert on stale price (maxTimeDelta/maxRefStaleness), excessive Chainlink deviation, or (L2) sequencer down.

Issues related to Invariant violations can be considered valid if they lead to Medium or higher impact and qualify for Medium or higher severity definition.

___

### Q: Please discuss any design choices you made.
Pure oracle-anchored pricing — no internal price discovery. Price follows the oracle, not reserves; there's no DEX cross-check (the only sanity guard is the Chainlink deviation check). Trade-off: manipulation risk shifts entirely to the oracle/price-provider layer; mitigated by the deviation guard, staleness checks, and the per-swap drift cap. If those guards are mis-tuned, bad-price execution is possible.

Rounding always favors the pool. Fees/baseFee/band edges use ceil; share math rounds against the user. Deliberate (no dust drain on the pool), but creates intentional rounding asymmetry — worth checking it can't be amplified. If rounding is not in favour of the protocol and qualifies for Medium or higher severity impact, it can be considered a valid issue.

Anchored band clipping: AnchoredPriceProvider lets a curator supply arbitrary bid/ask but clips it into mid ± (u + floor). Deliberate: "the band bounds how wrong a source can be." The band math (floor/uMax, ceil rounding) is the entire safety boundary — an error there is the high-impact case. If the band math is incorrect and can lead to Medium or higher severity impact, it can be considered a valid issue.

___

### Q: Please provide links to previous audits (if any) and all the known issues or acceptable risks.
- https://ams3.digitaloceanspaces.com/sherlock-files/additional_resources/Metric%20OMM%20-%20Zellic%20Audit%20Report%20Draft.pdf
- https://ams3.digitaloceanspaces.com/sherlock-files/additional_resources/contest-known-issues.pdf
- https://ams3.digitaloceanspaces.com/sherlock-files/additional_resources/2026-07-06_Metric-Collaborative_Audit_Report.pdf
___

### Q: Please list any relevant protocol resources.
https://oracle-based-omm.gitbook.io/metric/RSm94m71kqtGICv4iKRj
___

### Q: Additional audit information.
This contest will use the following severity definitions:

#### Critical severity:
**Direct loss of funds without limitations of external conditions, and the issue can be exploited at any moment. The loss of the affected party must exceed 20% and 100 USD.** This excludes loss of to-be-claimed yield/rewards by users.

Examples:
- Users lose more than 20% and more than $100 of their principal.
- The protocol loses more than 20% and more than $100 of the fees.

#### High severity:
**Direct loss of funds without (extensive) limitations of external conditions. The loss of the affected party must exceed 1% and 10 USD.** 

**Causes a loss of to-be-claimed yield/rewards exceeding 20% and 100 USD of lost rewards of the affected party.**

Examples:
- Users lose more than 1% and more than $10 of their principal.
- Users lose more than 20% and more than $100 of their yield/rewards.
- The protocol loses more than 1% and more than $10 of the fees.

#### Medium severity:
**Causes a loss of funds but requires certain external conditions or specific states, or a loss is highly constrained. The loss of the affected part must exceed 0.01% and 10 USD.**

**Causes a loss of to-be-claimed yield/rewards exceeding 1% and 10 USD of lost rewards of the affected party.**

**Breaks core contract functionality, rendering the contract useless or leading to loss of funds of the affected party that exceeds 0.01% and 10 USD.**

Note: If a single attack can cause a 0.01% loss but can be replayed indefinitely, it may be considered a 100% loss and can be medium or high, depending on the constraints.

Examples:
- Users lose more than 0.01% and more than $10 of their principal.
- Users lose more than 1% and more than $10 of their yield/rewards.
- The protocol loses more than 0.01% and more than $10 of the fees.

**Severity weights:**

- Critical - 10 points
- High - 5 points
- Medium - 1 points


# Audit scope

[metric-core @ 7b9ab567631a234ba5d467c646a1da9cbfb25479](https://github.com/Metric-OMM/metric-core/tree/7b9ab567631a234ba5d467c646a1da9cbfb25479)
- [metric-core/contracts/interfaces/callbacks/IMetricOmmModifyLiquidityCallback.sol](metric-core/contracts/interfaces/callbacks/IMetricOmmModifyLiquidityCallback.sol)
- [metric-core/contracts/interfaces/callbacks/IMetricOmmSwapCallback.sol](metric-core/contracts/interfaces/callbacks/IMetricOmmSwapCallback.sol)
- [metric-core/contracts/interfaces/extensions/IMetricOmmExtensions.sol](metric-core/contracts/interfaces/extensions/IMetricOmmExtensions.sol)
- [metric-core/contracts/interfaces/IExtsload.sol](metric-core/contracts/interfaces/IExtsload.sol)
- [metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactoryOwner.sol](metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactoryOwner.sol)
- [metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactoryPoolAdmin.sol](metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactoryPoolAdmin.sol)
- [metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactory.sol](metric-core/contracts/interfaces/IMetricOmmPoolFactory/IMetricOmmPoolFactory.sol)
- [metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolActions.sol](metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolActions.sol)
- [metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolCollectFees.sol](metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolCollectFees.sol)
- [metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolFactoryActions.sol](metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPoolFactoryActions.sol)
- [metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPool.sol](metric-core/contracts/interfaces/IMetricOmmPool/IMetricOmmPool.sol)
- [metric-core/contracts/interfaces/IPriceProvider/IPriceProvider.sol](metric-core/contracts/interfaces/IPriceProvider/IPriceProvider.sol)
- [metric-core/contracts/libraries/BinDataLibrary.sol](metric-core/contracts/libraries/BinDataLibrary.sol)
- [metric-core/contracts/libraries/CallExtension.sol](metric-core/contracts/libraries/CallExtension.sol)
- [metric-core/contracts/libraries/LiquidityLib.sol](metric-core/contracts/libraries/LiquidityLib.sol)
- [metric-core/contracts/libraries/PoolActions.sol](metric-core/contracts/libraries/PoolActions.sol)
- [metric-core/contracts/libraries/PoolStateLibrary.sol](metric-core/contracts/libraries/PoolStateLibrary.sol)
- [metric-core/contracts/libraries/SignedMath.sol](metric-core/contracts/libraries/SignedMath.sol)
- [metric-core/contracts/libraries/Slot0Library.sol](metric-core/contracts/libraries/Slot0Library.sol)
- [metric-core/contracts/libraries/SwapMath.sol](metric-core/contracts/libraries/SwapMath.sol)
- [metric-core/contracts/libraries/ValidateExtensionsConfig.sol](metric-core/contracts/libraries/ValidateExtensionsConfig.sol)
- [metric-core/contracts/MetricOmmPoolDeployer.sol](metric-core/contracts/MetricOmmPoolDeployer.sol)
- [metric-core/contracts/MetricOmmPoolFactory.sol](metric-core/contracts/MetricOmmPoolFactory.sol)
- [metric-core/contracts/MetricOmmPool.sol](metric-core/contracts/MetricOmmPool.sol)
- [metric-core/contracts/types/FactoryOperation.sol](metric-core/contracts/types/FactoryOperation.sol)
- [metric-core/contracts/types/FactoryStorage.sol](metric-core/contracts/types/FactoryStorage.sol)
- [metric-core/contracts/types/PoolExtensionsConfig.sol](metric-core/contracts/types/PoolExtensionsConfig.sol)
- [metric-core/contracts/types/PoolOperation.sol](metric-core/contracts/types/PoolOperation.sol)
- [metric-core/contracts/types/PoolStorage.sol](metric-core/contracts/types/PoolStorage.sol)
- [metric-core/contracts/types/Slot0.sol](metric-core/contracts/types/Slot0.sol)
- [metric-core/contracts/utils/MetricReentrancyGuardTransient.sol](metric-core/contracts/utils/MetricReentrancyGuardTransient.sol)

[metric-periphery @ d210a84daf694c52a591d371ceb9b82cece0f79f](https://github.com/Metric-OMM/metric-periphery/tree/d210a84daf694c52a591d371ceb9b82cece0f79f)
- [metric-periphery/contracts/base/MetricOmmSwapRouterBase.sol](metric-periphery/contracts/base/MetricOmmSwapRouterBase.sol)
- [metric-periphery/contracts/base/PeripheryPayments.sol](metric-periphery/contracts/base/PeripheryPayments.sol)
- [metric-periphery/contracts/base/SelfPermit.sol](metric-periphery/contracts/base/SelfPermit.sol)
- [metric-periphery/contracts/common/MetricOmmPoolStateView.sol](metric-periphery/contracts/common/MetricOmmPoolStateView.sol)
- [metric-periphery/contracts/extensions/base/BaseMetricExtension.sol](metric-periphery/contracts/extensions/base/BaseMetricExtension.sol)
- [metric-periphery/contracts/extensions/DepositAllowlistExtension.sol](metric-periphery/contracts/extensions/DepositAllowlistExtension.sol)
- [metric-periphery/contracts/extensions/OracleValueStopLossExtension.sol](metric-periphery/contracts/extensions/OracleValueStopLossExtension.sol)
- [metric-periphery/contracts/extensions/PriceVelocityGuardExtension.sol](metric-periphery/contracts/extensions/PriceVelocityGuardExtension.sol)
- [metric-periphery/contracts/extensions/SwapAllowlistExtension.sol](metric-periphery/contracts/extensions/SwapAllowlistExtension.sol)
- [metric-periphery/contracts/interfaces/extensions/IDepositAllowlistExtension.sol](metric-periphery/contracts/interfaces/extensions/IDepositAllowlistExtension.sol)
- [metric-periphery/contracts/interfaces/extensions/IOracleValueStopLossExtension.sol](metric-periphery/contracts/interfaces/extensions/IOracleValueStopLossExtension.sol)
- [metric-periphery/contracts/interfaces/extensions/IPriceVelocityGuardExtension.sol](metric-periphery/contracts/interfaces/extensions/IPriceVelocityGuardExtension.sol)
- [metric-periphery/contracts/interfaces/extensions/ISwapAllowlistExtension.sol](metric-periphery/contracts/interfaces/extensions/ISwapAllowlistExtension.sol)
- [metric-periphery/contracts/interfaces/external/IERC20PermitAllowed.sol](metric-periphery/contracts/interfaces/external/IERC20PermitAllowed.sol)
- [metric-periphery/contracts/interfaces/IMetricOmmPoolLiquidityAdder.sol](metric-periphery/contracts/interfaces/IMetricOmmPoolLiquidityAdder.sol)
- [metric-periphery/contracts/interfaces/IMetricOmmSimpleRouter.sol](metric-periphery/contracts/interfaces/IMetricOmmSimpleRouter.sol)
- [metric-periphery/contracts/interfaces/IMetricOmmSwapQuoter.sol](metric-periphery/contracts/interfaces/IMetricOmmSwapQuoter.sol)
- [metric-periphery/contracts/interfaces/IMulticall.sol](metric-periphery/contracts/interfaces/IMulticall.sol)
- [metric-periphery/contracts/interfaces/IPeripheryPayments.sol](metric-periphery/contracts/interfaces/IPeripheryPayments.sol)
- [metric-periphery/contracts/interfaces/ISelfPermit.sol](metric-periphery/contracts/interfaces/ISelfPermit.sol)
- [metric-periphery/contracts/interfaces/IWETH9.sol](metric-periphery/contracts/interfaces/IWETH9.sol)
- [metric-periphery/contracts/libraries/MetricOmmSwapInputs.sol](metric-periphery/contracts/libraries/MetricOmmSwapInputs.sol)
- [metric-periphery/contracts/libraries/MetricOmmSwapPath.sol](metric-periphery/contracts/libraries/MetricOmmSwapPath.sol)
- [metric-periphery/contracts/libraries/MetricOmmSwapQuoteDecode.sol](metric-periphery/contracts/libraries/MetricOmmSwapQuoteDecode.sol)
- [metric-periphery/contracts/libraries/MetricOmmSwapResults.sol](metric-periphery/contracts/libraries/MetricOmmSwapResults.sol)
- [metric-periphery/contracts/libraries/TransientCallbackPool.sol](metric-periphery/contracts/libraries/TransientCallbackPool.sol)
- [metric-periphery/contracts/MetricOmmPoolLiquidityAdder.sol](metric-periphery/contracts/MetricOmmPoolLiquidityAdder.sol)
- [metric-periphery/contracts/MetricOmmSimpleRouter.sol](metric-periphery/contracts/MetricOmmSimpleRouter.sol)

[smart-contracts-poc @ 056c20454dd867e388986f83b78d05809b921e49](https://github.com/Oracle-Based-Pool/smart-contracts-poc/tree/056c20454dd867e388986f83b78d05809b921e49)
- [smart-contracts-poc/contracts/AnchoredPriceProvider.sol](smart-contracts-poc/contracts/AnchoredPriceProvider.sol)
- [smart-contracts-poc/contracts/AnchoredProviderFactory.sol](smart-contracts-poc/contracts/AnchoredProviderFactory.sol)
- [smart-contracts-poc/contracts/interfaces/IAnchoredProviderFactory.sol](smart-contracts-poc/contracts/interfaces/IAnchoredProviderFactory.sol)
- [smart-contracts-poc/contracts/interfaces/IAnchorSource.sol](smart-contracts-poc/contracts/interfaces/IAnchorSource.sol)
- [smart-contracts-poc/contracts/interfaces/ICompressedOracleV1.sol](smart-contracts-poc/contracts/interfaces/ICompressedOracleV1.sol)
- [smart-contracts-poc/contracts/oracles/compressed/CompressedOracle.sol](smart-contracts-poc/contracts/oracles/compressed/CompressedOracle.sol)
- [smart-contracts-poc/contracts/oracles/compressed/OracleBase.sol](smart-contracts-poc/contracts/oracles/compressed/OracleBase.sol)
- [smart-contracts-poc/contracts/oracles/providers/ChainlinkOracle.sol](smart-contracts-poc/contracts/oracles/providers/ChainlinkOracle.sol)
- [smart-contracts-poc/contracts/oracles/providers/docs/en/abuse-protection-integration.md](smart-contracts-poc/contracts/oracles/providers/docs/en/abuse-protection-integration.md)
- [smart-contracts-poc/contracts/oracles/providers/docs/ru/abuse-protection-integration.md](smart-contracts-poc/contracts/oracles/providers/docs/ru/abuse-protection-integration.md)
- [smart-contracts-poc/contracts/oracles/providers/OracleBase.sol](smart-contracts-poc/contracts/oracles/providers/OracleBase.sol)
- [smart-contracts-poc/contracts/oracles/providers/PythOracle.sol](smart-contracts-poc/contracts/oracles/providers/PythOracle.sol)
- [smart-contracts-poc/contracts/oracles/utils/Codebook256.sol](smart-contracts-poc/contracts/oracles/utils/Codebook256.sol)
- [smart-contracts-poc/contracts/oracles/utils/LazerConsumer.sol](smart-contracts-poc/contracts/oracles/utils/LazerConsumer.sol)
- [smart-contracts-poc/contracts/oracles/utils/TimeMs.sol](smart-contracts-poc/contracts/oracles/utils/TimeMs.sol)
- [smart-contracts-poc/contracts/oracles/utils/U64x32.sol](smart-contracts-poc/contracts/oracles/utils/U64x32.sol)
- [smart-contracts-poc/contracts/PriceProviderFactory.sol](smart-contracts-poc/contracts/PriceProviderFactory.sol)
- [smart-contracts-poc/contracts/PriceProvider.sol](smart-contracts-poc/contracts/PriceProvider.sol)
- [smart-contracts-poc/contracts/ProtectedPriceProviderL2.sol](smart-contracts-poc/contracts/ProtectedPriceProviderL2.sol)
- [smart-contracts-poc/contracts/ProtectedPriceProvider.sol](smart-contracts-poc/contracts/ProtectedPriceProvider.sol)


