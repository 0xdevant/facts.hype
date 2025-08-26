## facts.hype

facts.hype is a crowd-sourced truth-seeking engine that's maximally-aligned with the HyperLiquid ecosystem.

Users can ask any question and attach a bounty(truth-seeker), researchers can submit their answers after depositing $HYPE into facts(hunter), others can vouch for that answer by staking $HYPE on top(voucher) - the answer with most vouches gets selected to be the “most-truthful” answer and hunter and vouchers will share the bounty.

facts.hype introduces a challenge mechanism where after the hunting period is over, anyone can challenge the answer by paying $HYPE(or other tokens valuable enough to not make Challenge a DOS) and if it gets accepted by the DAO - part of the hunter’s stake will be slashed to challenger, part of vouchers’ stake will be slashed to the DAO.

More importantly in order to avoid the truth being manipulated by the DAO, facts also introduces a mechanism to allow an external party i.e. the Council to override the final settlement from DAO, and slash the DAO voters’ $HYPE to prevent them being malicious.

With this mechanism facts.hype can be a plug-and-play truth-seeking engine for any kinds of protocols to build on top of e.g. Prediction Market, Insurance, RWA and pretty much any protocols that require a robust, reliable and decentralized way to verify any real-world event.

## Features

1. Ask any questions w/ or w/o a bounty
2. Submit answer by providing reliable sources
3. Vouch for answer by staking $HYPE on top of it
4. Challenge the most vouched answer - slash its staked $HYPE if challenge succeeded
5. Get your most truthful answer evaluated by the crowd, and by the DAO or Council if necessary

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
$ forge test
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
