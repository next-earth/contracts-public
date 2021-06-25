// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract PriceFeed is AggregatorV3Interface {

  function decimals() external view override returns (uint8) {
    return 18;
  }

  function description() external view override returns (string memory) {
    return "Mock bnb feed";
  }

  function getRoundData(uint80 _roundId) external view 
  override returns (
    uint80 roundId, 
    int256 answer, 
    uint256 startedAt, 
    uint256 updatedAt, 
    uint80 answeredInRound
  ) {
    roundId = _roundId;
    answer = 2759200000000000;
    startedAt = 1623405948;
    updatedAt = 1623405948;
    answeredInRound = _roundId;
  }

  function latestRoundData() external view 
  override returns (
    uint80 roundId, 
    int256 answer, 
    uint256 startedAt, 
    uint256 updatedAt, 
    uint80 answeredInRound
  ) {
    roundId = 1;
    answer = 2759200000000000;
    startedAt = 1623405948;
    updatedAt = 1623405948;
    answeredInRound = 1;
  }

  function version() external view override returns (uint256) {
    return 1;
  }

}
