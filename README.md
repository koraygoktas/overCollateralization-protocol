# Reputation Ledger: Over-Collateralization Protocol

[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Framework-Foundry-orange.svg)](https://book.getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An advanced DeFi over-collateralized lending protocol featuring dynamic borrowing limits and collateralization ratios powered by a decentralized reputation ledger. Instead of locking borrowers to a rigid, high over-collateralization tier (e.g., a static 150%), this protocol rewards positive repayment history by progressively lowering their required collateral ratio down to a secure floor of 120% and expanding their borrowing limits.

---

## 📖 Table of Contents
- [Reputation Ledger: Over-Collateralization Protocol](#reputation-ledger-over-collateralization-protocol)
  - [📖 Table of Contents](#-table-of-contents)
  - [🚀 Project Overview](#-project-overview)
  - [🛡️ Key Features](#️-key-features)
  - [📐 Mathematical Model](#-mathematical-model)
    - [1. Reputation Level Calculation](#1-reputation-level-calculation)
    - [2. Dynamic Collateral Ratio](#2-dynamic-collateral-ratio)
    - [3. Dynamic Borrow Limit](#3-dynamic-borrow-limit)
    - [4. Position Health Verification](#4-position-health-verification)
    - [5. Liquidation and Seizure](#5-liquidation-and-seizure)
  - [🏗️ Architectural Architecture](#️-architectural-architecture)
    - [Core Flow Diagram](#core-flow-diagram)
  - [📂 Smart Contracts Structure](#-smart-contracts-structure)
  - [💻 Tech Stack](#-tech-stack)
  - [⚙️ Installation \& Setup](#️-installation--setup)
  - [🧪 Testing Suite](#-testing-suite)
    - [Key Test Coverage](#key-test-coverage)
  - [🚀 Deployment Guide](#-deployment-guide)
  - [🖥️ Web Interface (Demo)](#️-web-interface-demo)
  - [📄 License](#-license)

---

## 🚀 Project Overview

Most lending protocols suffer from capital inefficiency due to static, highly conservative over-collateralization requirements. Borrowers with excellent repayment histories are subjected to the exact same capital constraints as new or risky participants.

**Reputation Ledger** solves this by establishing an on-chain credit-like framework:
*   **Good behavior is incentivized**: Successfully repaying debt in full increases your on-chain reputation score.
*   **Collateral requirements drop**: High-reputation borrowers can unlock capital using smaller collateral reserves (from 150% down to a secure floor of 120%).
*   **Borrow limits grow**: Trusted borrowers can mint or borrow higher absolute limits of debt tokens.
*   **Strict Liquidations remain**: Any drop in collateral price or rise in debt price that breaks the user's custom required collateral threshold subjects them to immediate liquidation, resetting their reputation back to zero.

---

## 🛡️ Key Features

*   **Progressive Leveling System**: Incorporates logarithmic leveling $Level = \lfloor\log_2(Score+1)\rfloor$, preventing users from gaming the system via rapid micro-transactions.
*   **Custom Risk Profiles**: A user's required collateral ratio is tailored directly to their current reputation level.
*   **Dynamic Limits**: Max borrow limit starts at 100 mDEBT and scales by +25% per reputation level.
*   **Liquidation Incentive (10% Bonus)**: High-performance liquidators are rewarded with a 10% bonus when buying out under-collateralized positions.
*   **Decentralized Price Oracles**: Connects with configurable mock oracles to simulate volatile market movements and test liquidated states.
*   **Beautiful Front-End Interface**: Includes a modern, fully functional, English-translated web UI for seamless user interactions and simulations.

---

## 📐 Mathematical Model

The smart contract executes several strict mathematical definitions using 18-decimal precision:

### 1. Reputation Level Calculation
To prevent reputation manipulation via spam transactions, a user's reputation score is converted into levels using a logarithmic base-2 floor logic:

$$\text{Level} = \lfloor \log_2(\text{ReputationScore} + 1) \rfloor$$

This ensures that advancing to subsequent levels requires exponentially more full debt repayments:
*   **Level 0**: $0$ to $0$ score
*   **Level 1**: $1$ to $2$ score
*   **Level 2**: $3$ to $6$ score
*   **Level 3**: $7$ to $14$ score, etc.

### 2. Dynamic Collateral Ratio
The required collateral ratio drops by **6% (0.06e18)** per level, starting from **150% (1.5e18)** down to a hard floor of **120% (1.2e18)**:

$$\text{RequiredRatio} = \max\left(\text{INITIAL\_RATIO} - \text{Level} \times \text{RATIO\_DROP\_PER\_LEVEL}, \ \text{FLOOR\_RATIO}\right)$$

### 3. Dynamic Borrow Limit
Borrowers start with a base borrow limit of **100 mDEBT** which scales by **+25%** per level:

$$\text{MaxLimit} = \text{BASE\_BORROW\_LIMIT} \times \left(1 + \text{Level} \times 0.25\right)$$

### 4. Position Health Verification
A borrowing position is considered healthy if the value of its deposited collateral is greater than or equal to the required over-collateralized value of its debt:

$$\text{CollateralAmount} \times \text{Price}_{\text{Collateral}} \geq \text{DebtAmount} \times \text{Price}_{\text{Debt}} \times \text{RequiredRatio}$$

### 5. Liquidation and Seizure
When a position becomes unhealthy, liquidators can pay off a portion of the borrower's debt to seize an equivalent value of collateral plus a **10% Liquidation Bonus**:

$$\text{CollateralToSeize} = \frac{\text{DebtToCover} \times \text{Price}_{\text{Debt}} \times (1 + \text{LIQUIDATION\_BONUS})}{\text{Price}_{\text{Collateral}}}$$

*Note: Liquidations automatically reset the borrower's reputation score back to 0.*

---

## 🏗️ Architectural Architecture

The protocol involves three main actors: **Borrowers**, **Liquidators**, and the **Price Oracle**.

### Core Flow Diagram

```
   +----------+                +-------------+                +---------------+
   | Borrower |                | LendingPool |                |  Price Oracle |
   +----+-----+                +------+------+                +-------+-------+
        |                             |                               |
        |---- 1. deposit(mCOL) ------>|                               |
        |                             |                               |
        |---- 2. borrow(mDEBT) ------>|---- Get prices -------------->|
        |                             |<--- Return prices ------------|
        |                             |                               |
        |                             |--[Check collateral ratio]     |
        |                             |--[Check borrow limits]        |
        |<--- Transfer mDEBT ---------|                               |
        |                             |                               |
        |                             |                               |
        |---- 3. repay(mDEBT) ------->|                               |
        |                             |--[If full repayment:    ]     |
        |                             |  [Reputation score +1   ]     |
        |                             |  [Required ratio drops  ]     |
        |                             |  [Max limit increases   ]     |
        |                             |                               |
```

---

## 📂 Smart Contracts Structure

*   **`src/LendingPool.sol`**: The core lending engine containing deposit, withdraw, borrow, repay, and liquidate logic. It computes dynamic ratios, limits, and handles state mutations.
*   **`src/mocks/MockERC20.sol`**: An ERC-20 compliant mock token used to represent the Collateral Token (`mCOL`) and Debt Token (`mDEBT`).
*   **`src/mocks/MockPriceOracle.sol`**: Configurable mock price oracles to query asset valuation during health factor checks.
*   **`script/Deploy.s.sol`**: An automated deployment script for seamless local and testnet deployments.

---

## 💻 Tech Stack

*   **Smart Contracts**: Solidity `^0.8.20`, OpenZeppelin Contracts v5.0.
*   **Development Framework**: Foundry (Forge, Cast, Anvil).
*   **Frontend Interface**: Pure HTML5, CSS3 (Modern, responsive, glassmorphic UI layout), Vanilla JavaScript, and Ethers.js v6.

---

## ⚙️ Installation & Setup

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/koraygoktas/overCollateralization-protocol.git
    cd overCollateralization-protocol
    ```

2.  **Install Dependencies**:
    ```bash
    forge install
    ```

3.  **Compile Smart Contracts**:
    ```bash
    forge build
    ```

---

## 🧪 Testing Suite

The protocol comes with a comprehensive testing suite in `test/LendingPool.t.sol` verifying all invariant configurations, limits, reputation upgrades, and liquidation scenarios.

To execute the tests:
```bash
forge test
```

To run tests with gas reports or detailed logs:
```bash
# Detailed execution traces
forge test -vvvv

# View gas snapshots
forge snapshot
```

### Key Test Coverage
*   **Deposits & Withdrawals**: Tests zero-amount prevention, balance updates, and health compliance checks.
*   **Borrow limits**: Verifies maximum limit calculation per level and blocks excessive borrowing.
*   **Reputation Logic**: Confirms reputation gains on full repayment and checks logarithmic level boundaries.
*   **Collateral Ratios**: Confirms the stepwise reduction of required ratios as users climb reputation levels.
*   **Liquidation Invariants**: Simulates collateral price crashes and debt price spikes, verifying correct bonus payouts and reputation resets.

---

## 🚀 Deployment Guide

You can easily deploy these contracts on a local development network (Anvil) or any EVM testnet (e.g., Sepolia).

1.  **Setup Environment Variables**:
    Create a `.env` file in the root directory:
    ```env
    PRIVATE_KEY=your_private_key_here
    SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
    ```

2.  **Start a Local Chain (Optional)**:
    ```bash
    anvil
    ```

3.  **Deploy Contracts**:
    ```bash
    # To deploy on Sepolia Network
    source .env
    forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
    ```

---

## 🖥️ Web Interface (Demo)

The project includes an elegant, high-fidelity Web3 client located inside the `demo/` folder, allowing you to test and simulate all functions live in your browser.

*   **Responsive Panels**: Highlighting your custom required collateral ratio, current position health, reputation score, and max borrow capacity.
*   **Live Oracle Simulator**: Modify oracle prices directly from the dashboard to trigger mock liquidations.
*   **Interactive Log**: Real-time event logging capturing all incoming block actions and transaction confirmations.

### To Run the Demo Locally:
1.  Open `demo/index.html` directly in your browser or run a simple local web server:
    ```bash
    # If using Python
    python -m http.server 8000
    ```
2.  Open `http://localhost:8000/demo/` in your browser.
3.  Connect your MetaMask wallet on the **Sepolia Network** and start exploring!

---

## 📄 License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.
