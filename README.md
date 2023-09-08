# ckicp-ethereum-contracts
Ethereum contracts for ckICP

## Description
Ethereum contracts to be owned by the ckICP main canister on ICP via tECDSA.

## Functionalities
- [x] ERC20 tokens of ICP on Ethereum
- [x] Only the ckICP canister can mint
- [x] Anyone can burn ckICP on ETH to get ICP on the IC blockchain
- [x] EIP-2612

## Toolchain
https://github.com/foundry-rs/foundry

## Goerli deployed contract
https://goerli.etherscan.io/address/

## Deploy
```
forge create --private-key $DEVT0 src/CkIcp.sol:CkIcp
```
