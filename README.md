# KipuBank V3 - Final Project (Module 4)

This repository contains the final project for the Web3 course, demonstrating the evolution of a smart contract bank (`KipuBank`) from a simple ETH/USDC vault (V2) to a DeFi-integrated protocol (V3) using Foundry.

KipuBank V3 is a decentralized bank that accepts user deposits of native ETH or any ERC20 token. It automatically swaps these assets into USDC using **Uniswap V2** and credits the user's internal USDC balance. The contract enforces a global deposit limit (`BANKCAP`) and a per-transaction withdrawal limit.

## 1. Key Features & V3 Upgrades

- **Uniswap V2 Integration:** Replaced the Chainlink price feed (V2) Oracle with the Uniswap V2 Router. All non-USDC deposits are now swapped for USDC.
- **Multi-Asset Deposits:**
  - `depositEther()`: Accepts native ETH, swaps it for USDC.
  - `depositToken()`: Accepts any ERC20 token. If it's USDC, it's deposited directly. If it's another token, it's swapped (`Token -> WETH -> USDC`) for USDC.
- **USDC-Centric Accounting:** All internal accounting (`balances` mapping) is now denominated _only_ in USDC, simplifying the contract's state.
- **Immutable Risk Parameters:** Critical risk parameters (`BANKCAP`, `MAXIMUM_WITHDRAWAL_IN_USD`, `SLIPPAGE_TOLERANCE_BPS`) are set in the constructor. This makes the contract's behavior predictable and allows different "flavors" of the bank to be deployed with different risk policies.
- **Security First:** Implements the **Checks-Effects-Interactions (CEI)** pattern and `ReentrancyGuard` on withdrawals.

## 2. Core Design Decisions

- **Slippage Control:** The slippage tolerance is an `immutable` variable (`SLIPPAGE_TOLERANCE_BPS`) set at deployment.
  - **Trade-off:** This provides a much safer user experience (UX) as users cannot be "sandwiched" by setting a high slippage. It abstracts complexity away from the end-user. The cost is flexibility, as the slippage cannot be changed per-transaction.
- **Swap Path:** Swaps for arbitrary ERC20 tokens are hardcoded to the path `Token -> WETH -> USDC`.
  - **Trade-off:** This provides a reliable path for most assets. It is not the most gas-efficient path if a direct `Token -> USDC` liquidity pool exists, but it guarantees broad compatibility.
- **Security & Optimizations:**
  - Uses OpenZeppelin's `SafeERC20` for all token transfers.
  - Uses `unchecked` blocks for simple counters (`...Operations`) where overflow is impossible, saving gas.
  - Refactored logic into private helper functions (`_getPath`, `_previewSwap`, `_calculateAmountOutMin`) to adhere to the DRY (Don't Repeat Yourself) principle.

## 3. How to Use (Compile, Test, Deploy)

### Requirements

- [Foundry](https://getfoundry.sh/)
- `.env` file with `SEPOLIA_RPC_URL`, `SEPOLIA_USER_PRIVATE_KEY`, and `ETHERSCAN_API_KEY`.`

This file is used to store secret keys and API endpoints.
NEVER SHARE OR EXPOSE THE CONTENT OF YOUR .env!

```bash
# 1. Get from Alchemy or Infura (https://www.alchemy.com/)
SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_API_KEY"

# 2. Get from Etherscan (https://etherscan.io/myapikey)
ETHERSCAN_API_KEY="YOUR_ETHERSCAN_API_KEY"

# 3. Export from MetaMask (Account Details -> Show Private Key)
# Make sure this account has Sepolia ETH from a faucet.
SEPOLIA_USER_PRIVATE_KEY="0xYOUR_WALLET_PRIVATE_KEY"
```

### Compile

```bash
forge build
```

### Test

This project uses mainnet forking to test real interactions with the Uniswap V2 Router.
Make sure your .env has a valid RPC url.

```bash
source .env
```

```bash
 forge test
```

Check test coverage

```bash
 forge coverage
```

### Deployment

#### Deploy to Sepolia Testnet

### Deploy to Sepolia Testnet

1.  Ensure your `.env` variables are set (RPC, Private Key, Etherscan Key).
2.  Ensure your wallet has Sepolia ETH for gas.

Run the script, which will broadcast, deploy, and verify all in one step:

```bash
forge script script/DeployKipuBankV3.s.sol:DeployKipuBankV3 \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain-id 11155111
```

(Optional) If auto-verification fails, you can run it manually:

```bash
forge verify-contract --chain-id 11155111 <CONTRACT_ADDRESS> src/KipuBankV3.sol:KipuBankV3 --etherscan-api-key $ETHERSCAN_API_KEY
```

## 4. Threat Analysis & Security Report

### Weaknesses & Missing Features

Owner Risk: The contract is Ownable. The owner (a single EOA) is a single point of failure. In a production environment, the owner should be a MultiSig wallet or a DAO-controlled Governance contract.

Protocol Risk: The contract's core functionality is entirely dependent on the Uniswap V2 Router. If the router contract were ever compromised (extremely unlikely) or paused, all swap-related deposits would fail.

Liquidity Risk: depositToken and depositEther will revert if the corresponding Uniswap V2 pool (Token/WETH or WETH/USDC) does not exist or has insufficient liquidity. This is handled by the \_previewSwap check.

No Emergency Stop: The contract lacks a Pausable mechanism. If a critical bug were found, the owner could not halt deposits or withdrawals to protect user funds.

Slippage Configuration Risk: While the immutable SLIPPAGE_TOLERANCE_BPS protects users from setting bad values, it introduces a risk from the deployer. If the owner sets this value too low (e.g., 0.1%), most swaps will fail during volatile markets. If set too high (e.g., 5%), it re-enables the sandwich attack risk that the contract was designed to prevent.

### Test Coverage

You can check the `index.html` file at `coverage/` folder or you can check the following a snapshot of the resultant coverage

#### 🧪 Test Coverage Report

| File                            |      % Lines       |    % Statements     |  % Branches   |      % Funcs       |
| ------------------------------- | :----------------: | :-----------------: | :-----------: | :----------------: |
| `script/DeployKipuBankV3.s.sol` |    0.00% (0/11)    |    0.00% (0/13)     | 100.00% (0/0) |    0.00% (0/1)     |
| `src/KipuBankV3.sol`            | **79.27% (65/82)** | **67.31% (70/104)** | 21.05% (4/19) | **91.67% (11/12)** |
| **Total**                       | **69.89% (65/93)** | **59.83% (70/117)** | 21.05% (4/19) | **84.62% (11/13)** |

## Deployed contract

Address
0x078dEbfbFC8C2764c561Bd636D833Cc569FDb3B2

Etherscan link
https://sepolia.etherscan.io/address/0x078dEbfbFC8C2764c561Bd636D833Cc569FDb3B2#code
