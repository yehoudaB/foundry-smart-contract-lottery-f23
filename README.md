# Proveably Random Lottery Contract

## Description

This repository contains the source code for a proveably random lottery contract.

## Fonctionalities

1. User can buy tickets for a raffle
   1. The ticket fees are going to the winner during the draw
2. After X periode of time, the lottery will automatically draw a winner
   1. And this will be done automatically
3. Using Chainlink VRF and Chanlink Automation
   1. Chainlink VRF will be used to generate a random number
   2. Chainlink Automation will be used to trigger the draw based on the time

## Important

when writting the code always use CEI (Check-Effect-Interaction) pattern
Interaction is with external contracts

## Tests

1. Write some deploy scripts
2. Write our tests
3. run on local blockchain
4. run on forked Testnet
5. run on forked Mainnet

## fund subscription contract

```bash

forge script script/Interaction.s.sol:FundSubscription --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

```

## deployement command example for seploia network

```
   make deploy ARGS="--network sepolia"
```
