pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TeamVestingWallet {
  mapping (address => uint256) public vestingPaces;
  mapping (address => uint256) public vestingGroups;
  mapping (address => uint256) public vestingDurations;
  mapping (address => uint256) public releasedTokens;
  mapping (address => uint256) public unlockedTokens;
  mapping (address => bool) public unlockedClaimed;
  mapping (address => uint256) public shares;
  uint256 public vestingStart;
  event TokensReleased(IERC20 indexed token, address indexed to, uint256 indexed amount);

  constructor(address[] memory payees, uint256[] memory _shares) {
    require(payees.length == 7, "invalid number of payees");
    require(_shares.length == 7, "invalid number of shares");
    vestingPaces[payees[0]] = 25; // IT
    vestingPaces[payees[1]] = 10; // Team
    vestingPaces[payees[2]] = 25; // Marketing
    vestingPaces[payees[3]] = 20; // BD
    vestingPaces[payees[4]] = 20; // Launchpad
    vestingPaces[payees[5]] = 1000; // Liquidity
    vestingPaces[payees[6]] = 20; // Legal

    vestingGroups[payees[0]] = 0;
    vestingGroups[payees[1]] = 1;
    vestingGroups[payees[2]] = 2;
    vestingGroups[payees[3]] = 3;
    vestingGroups[payees[4]] = 4;
    vestingGroups[payees[5]] = 5;
    vestingGroups[payees[6]] = 6;

    vestingDurations[payees[0]] = 40;
    vestingDurations[payees[1]] = 100;
    vestingDurations[payees[2]] = 40;
    vestingDurations[payees[3]] = 50;
    vestingDurations[payees[4]] = 50;
    vestingDurations[payees[5]] = 0;
    vestingDurations[payees[6]] = 50;

    shares[payees[0]] = _shares[0];
    shares[payees[1]] = _shares[1];
    shares[payees[2]] = _shares[2];
    shares[payees[3]] = _shares[3];
    shares[payees[4]] = _shares[4];
    shares[payees[5]] = _shares[5];
    shares[payees[6]] = _shares[6];
  
    uint256 total = 60 * 1e9 * 1e18;
    unlockedTokens[payees[0]] = total * 25 / 1000;
    unlockedTokens[payees[1]] = 0;
    unlockedTokens[payees[2]] = total * 45 / 1000;
    unlockedTokens[payees[3]] = total * 20 / 1000;
    unlockedTokens[payees[4]] = total * 25 / 1000;
    unlockedTokens[payees[5]] = total * 60 / 1000;
    unlockedTokens[payees[6]] = total * 15 / 1000;

    vestingStart = block.timestamp;
  }

  function releaseLocked(IERC20 token) public {
    require(shares[msg.sender] > 0, "PaymentSplitter: account has no shares");
    uint256 weeksSince = (block.timestamp - vestingStart) / 1 weeks;
    uint256 vestedAmount = 0;
    uint256 unlocked = unlockedTokens[msg.sender];
    if (weeksSince <= vestingDurations[msg.sender] && vestingDurations[msg.sender] > 0) {
      vestedAmount = ((shares[msg.sender] - unlocked) * weeksSince * vestingPaces[msg.sender] / 1000);
    } else {
      vestedAmount = shares[msg.sender] - unlocked;
    }
    uint256 payment = 0;
    if(!unlockedClaimed[msg.sender]) {
      require(vestedAmount > releasedTokens[msg.sender], 'no nxtt available');
      payment = vestedAmount - releasedTokens[msg.sender];
    } else {
      require(vestedAmount + unlocked > releasedTokens[msg.sender], 'no nxtt available');
      payment = vestedAmount + unlocked - releasedTokens[msg.sender];
    }
    releasedTokens[msg.sender] += payment;
    SafeERC20.safeTransfer(token, msg.sender, payment);
    emit TokensReleased(token, msg.sender, payment);
  }

  function releaseUnlocked(IERC20 token) public {
    require(shares[msg.sender] > 0, "PaymentSplitter: msg.sender has no shares");
    require(unlockedTokens[msg.sender] > 0);
    require(!unlockedClaimed[msg.sender], "unlocked tokens already claimed");
    unlockedClaimed[msg.sender] = true;
    uint256 payment = unlockedTokens[msg.sender];
    releasedTokens[msg.sender] += payment;
    SafeERC20.safeTransfer(token, msg.sender, payment);
    emit TokensReleased(token, msg.sender, payment);

  }

}
