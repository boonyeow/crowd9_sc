# IS483 AY 2023-24T1 - Team Tacos (24)

Members

- Alvin Ling Wei Chow (alvin.ling.2021@scis.smu.edu.sg)
- Ng Kang Ting (kangting.ng.2021@scis.smu.edu.sg)
- Sebastian Ong Chin Poh (cpong.2021@scis.smu.edu.sg)
- Tan Boon Yeow (bytan.2021@scis.smu.edu.sg)

# Final Year Project - Project Fund - Backend (Smart Contract) Repository

The primary objective of this project is to establish a safer crowdfunding experience, addressing these challenges for
both our project sponsor, and the broader investing community in crypto space.

The smart contracts are written in the Move language, and deployed onto the SUI Blockchain.

A full list of Sui's Client CLI commands can be found [here](https://docs.sui.io/references/cli/client)

# Setup Instructions

## Pre-requisites

1. Ensure that you have Sui installed. Install
   it [here](https://docs.sui.io/guides/developer/getting-started/sui-install)
2. Ensure that the active Sui account tied to your machine has enough tokens to deploy the smart contracts. If you are
   on the Testnet/Devnet, request for tokens from the official Sui Discord server [here](https://discord.gg/sui)

## Deploying the smart contracts to the Sui blockchain

Ensure that you are on your desired network. Check your currently active environment using the following
command: `sui client active-env`

Switch to a different environment using this command: `sui client switch --env [mainnet | testnet | devnet]`

Run the following command to publish the smart contracts onto your active
environment: `sui client publish --gas-budget <GAS BUDGET>`

## Running unit tests

To run the unit tests and view the code coverage, use the following command (on Windows):
```sui move test --coverage && sui move coverage summary && sui move coverage source --module governance```

