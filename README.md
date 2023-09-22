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

## Deterministic Deployment
1. Replace the `0x04` with the minter's Ethereum address in script/CkIcp.s.sol in line `new CkIcp{salt: bytes32(uint256(1))}(address(0x04));`.
2. Run `forge script script/CkIcp.s.sol -v --private-key $DEVT0 --rpc-url https://ethereum-goerli.publicnode.com --broadcast` (for mainnet deployment, replace the RPC url).
3. The Airdrop.sol does not need a deterministic address and can be deployed using `forge create --private-key $DEVT0 src/Airdrop.sol:Airdrop`.
4. Verify the contracts on Ethereum following steps [here](https://book.getfoundry.sh/forge/deploying#verifying-a-pre-existing-contract).
