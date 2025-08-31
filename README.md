## facts.hype

facts.hype is a **decentralized and actually fair market resolution system to provide crowd-sourced verification of real-world events for DApps to build on top of** i.e. an open-source alternative to UMA on HyperLiquid.

## How it works

```bash
# Phases
Ask > Hunt & Vouch > Challenge > Settle > Review > Finalize
```

1. Users can ask any question and choose to attach a bounty (Truth-seeker asks)

2. Others can submit different answers after depositing $HYPE to be a hunter (Hunter hunts)

3. Others can vouch for the answer they believe to be true by staking $HYPE on top (Voucher vouches)

4. The answer with the most vouched gets selected to be the “most-truthful” answer

   > Note 1: Hunter and vouchers of the selected answer will share the bounty

   > Note 2: If there is no submission, or no answer gets more vouched than the others, the result can be settled immediately and no bounty will be distributed

5. Anyone can submit a challenge after the hunting period by paying $HYPE (Challenger challenges)

6. If it gets accepted by the DAO - part of the hunter's stake will be slashed to challenger, part of vouchers' stake will be slashed to the DAO (DAO settles)

7. In order to avoid the truth being manipulated by the DAO there is an external party in facts i.e. the Council to override DAO's decision and slash the DAO's $HYPE if needed (Council reviews)

8. Anyone can then finalize the question to automatically distribute the bounty and slash related parties

With such mechanism facts.hype can be a plug-and-play truth-seeking engine for any protocols that rely on verification of real-world events to build on top of e.g. Prediction Market, Insurance, RWA and pretty much any protocols that require a robust, reliable and decentralized way to verify any real-world event.

## Getting Started

```
$ git clone https://github.com/0xdevant/facts.hype
$ cd facts.hype
$ forge install
```

## Project Structure

```
├── script
│   ├── Deploy.s.sol
│   ├── DeployMainnet.s.sol
│   └── DeployTestnet.s.sol
├── src
│   ├── Facts.sol
│   ├── interfaces
│   │   └── IFacts.sol
│   └── types
│       └── DataTypes.sol
└── test
    ├── Constants.sol
    ├── Facts.t.sol
    └── shared
        └── BaseTest.sol
```

## Usage

### Test

```shell
$ forge test # >80% coverage for now
```

### Deploy

```shell
# deploy to testnet, remove --broadcast to simulate deployment
$ forge script script/DeployTestnet.s.sol --rpc-url $HYPEREVM_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast

# verify contract
$ forge verify-contract <deployed_contract_address> src/Facts.sol:Facts \
  --chain-id 998 \
  --verifier sourcify \
  --verifier-url https://sourcify.parsec.finance/verify
```

## Future Improvements

- Develop SDK for easy integration and avoid writing the getters in contract to minimize deployment gas cost
- Gitbook on how to integrate as developers
- Mainnet & Crosschain Deployment
- Better UI

## Contributing

This repository serves as an open source alternative of market resolution system like UMA on HyperLiquid.

Feel free to make a pull request.

## Safety

This software is **experimental** and is provided "as is" and "as available".

**No warranties are provided** and **no liability will be accepted for any loss** incurred through the use of this codebase.

Always include thorough tests when using the Euler Vault Kit to ensure it interacts correctly with your code.

## License

MIT. See [LICENSE](./LICENSE) for more details.

## Acknowledgements

The implementation is not referenced but this idea is inspired by [reality.eth](https://github.com/RealityETH/reality-eth-monorepo) which I really appreciate its existence as an open-source project.
