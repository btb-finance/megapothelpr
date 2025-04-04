# Megapot Helper

A set of helper tools and scripts for interacting with the MegaPot smart contract ecosystem on Base.

## Overview

This repository contains utility scripts and tools for:
- Creating and managing subscriptions
- Batch operations
- Testing and simulation tools
- Helper functions for interacting with the JackpotCashback contract

## Installation

```bash
# Clone the repository
git clone https://github.com/btb-finance/megapothelpr.git
cd megapothelpr

# Install dependencies
forge install
```

## Usage

### Environment Setup

Create a `.env` file with the following variables:
```
private_key=YOUR_PRIVATE_KEY
usdc_address=USDC_ADDRESS
jackpotcashback_address=JACKPOT_CASHBACK_ADDRESS
```

### Running Scripts

```bash
# Create batch subscriptions
source .env && forge script script/BatchSubscriptionTest.s.sol:BatchSubscriptionTestScript --rpc-url https://sepolia.base.org --broadcast --skip-simulation -vvv
```
## Deployment

Before deploying, ensure you have created a `.env` file with the following variables:

```
private_key=YOUR_PRIVATE_KEY
usdc_address=USDC_TOKEN_ADDRESS
jackpot_address=JACKPOT_CONTRACT_ADDRESS
referral_address=REFERRAL_CONTRACT_ADDRESS
cashback_percentage=CASHBACK_PERCENTAGE_NUMBER
```

Replace the placeholders with your actual deployment values.

To deploy the `JackpotCashback` contract, run:

```bash
source .env && forge script script/Deploy.s.sol:DeployScript --rpc-url YOUR_RPC_URL --broadcast -vvv
```

- Replace `YOUR_RPC_URL` with your Ethereum node RPC endpoint.
- The script will deploy the contract using the provided environment variables.

## License

MIT
MIT
