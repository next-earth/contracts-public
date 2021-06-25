// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract Presale is Pausable, Ownable {
  struct purchase {
    uint32 packType;
    bytes32 landsRoot;
    uint256 purchasedPrice; // it has much more sense
    string comissionCode;
  }
  uint256 constant public ownerMaxAllowed = 36000000; // tiles count for the team (100 x packTypes[5])
  uint256 public ownerRemaining;
  address public merchant;
  mapping (uint32 => uint256) public packTypes;
  mapping (uint32 => uint256) public packPrices;
  mapping (address => purchase[]) public purchases;
  mapping (address => uint256) public balances;
  mapping (address => bool) public discounts;
  address public charityAddress;
  uint256 public charityBalance;
  uint256 public comissionPool;
  AggregatorV3Interface internal priceFeed;
  event CharityClaim(address payee, uint256 amount);
  event ComissionClaim(address payee, uint256 amount);
  event NewPurchase(address buyer, uint32 packType, bytes32 root, string code, uint256 price);
  constructor(address _merchant, address payable _charityAddress, 
             address _priceFeed) {
    merchant = _merchant;

    // tile count
    packTypes[1] = 15000;
    packTypes[2] = 30000;
    packTypes[3] = 60000;
    packTypes[4] = 120000;
    packTypes[5] = 360000;

    // in USDT
    packPrices[1] = 15000000;
    packPrices[2] = 30000000;
    packPrices[3] = 60000000;
    packPrices[4] = 120000000;
    packPrices[5] = 360000000;

    ownerRemaining += ownerMaxAllowed;
    charityAddress = _charityAddress;
    charityBalance = 0;
    comissionPool = 0;

    priceFeed = AggregatorV3Interface(_priceFeed);
  }

  function buyPack(uint32 packType, bytes32 landsRoot,
      uint16 comissionPercent, string calldata comissionCode, 
      uint16 discountPercent, bytes calldata sig)
    external payable returns (uint256) {
      {
        require(packType >= 1 && packType <= 5, "invalid pack type"); // we have 5 pack types from 1 to 5
        bytes32 hash = keccak256(abi.encodePacked(packType, landsRoot, msg.sender,
              comissionPercent, comissionCode, discountPercent));
        bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(hash);
        address signer = ECDSA.recover(prefixedHash, sig);
        require(signer == merchant, 'invalid merchant signature');
      }

      // because not all discount addresses can buy the ownerMaxAllowed amount,
      // but the discount addresses sum purchases can be maximum the ownerMaxAllowed amount
      if (discounts[msg.sender]) {
        require(packTypes[packType] <= ownerRemaining, "team already claimed all free packs");
        ownerRemaining -= packTypes[packType];
      }
      // becuase a discount address can purchase multiple packs
      require(discounts[msg.sender] || purchases[msg.sender].length == 0, "only one purchase per wallet");
      // here, a comissionPercent of 125 for eg means 12.5% as 125/1000 represents a
      // 0.125 multiplier
      uint256 fullBNBPrice = getBNBPrice(packPrices[packType])/100000; // because we need it to calculate the commission and charity
      uint256 discountPrice = fullBNBPrice - ((fullBNBPrice * discountPercent)/1000);
      require(msg.value >= discountPrice, "not enough funds");
      require(msg.value - discountPrice < 5000, "too much ethers/bnb sent");

      purchases[msg.sender].push(purchase(packType, landsRoot, discountPrice, comissionCode));
      balances[msg.sender] += packTypes[packType];

      uint256 comissionShare = ((fullBNBPrice * comissionPercent)/1000);
      uint256 charityShare = ((fullBNBPrice * 100)/1000);
      // uint256 contractShare = msg.value - charityShare - comissionShare; // not used, need to remove it

      charityBalance += charityShare;
      comissionPool += comissionShare;
      emit NewPurchase(msg.sender, packType, landsRoot, comissionCode, discountPrice);
      return balances[msg.sender];
    }

  function getPurchases() public view returns (purchase[] memory) {
    return purchases[msg.sender];
  }

  function getBalance() public view returns (uint256) {
    return balances[msg.sender];
  }

  function setDiscount(address _addr, bool _isDiscounted) external onlyOwner {
    discounts[_addr] = _isDiscounted;
  }

  function isDiscounted() public view returns (bool) {
    return discounts[msg.sender];
  }

  function pause() onlyOwner public {
    _pause();
  }

  function unpause() onlyOwner public {
    _unpause();
  }

  function setPackPrice(uint32 _type, uint256 price) external onlyOwner {
    packPrices[_type] = price;
  }


  // https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now
  function claimCharity() external {
    uint256 balanceToSend = charityBalance;
    require(msg.sender == charityAddress, 'reserved for charity');
    require(balanceToSend > 0, 'not eligible for claiming');
    charityBalance = 0;
    (bool success, ) = msg.sender.call{value: balanceToSend}('');
    require(success, "Transfer failed.");
    emit CharityClaim(msg.sender, balanceToSend);
  }

  // https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now
  function claimComission(string calldata code, uint256 amount, bytes calldata sig) external {
    bytes32 hash = keccak256(abi.encodePacked(code, amount, msg.sender));
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(hash);
    address signer = ECDSA.recover(prefixedHash, sig);
    require(signer == merchant, 'invalid merchant signature');
    require(comissionPool >= amount, 'not eligible for claiming'); // fixed check
    comissionPool -= amount;
    (bool success, ) = msg.sender.call{value: amount}('');
    require(success, "Transfer failed.");
    emit ComissionClaim(msg.sender, amount);
  }

  function claimSale() external onlyOwner {
    uint256 amount = address(this).balance - charityBalance - comissionPool;
    (bool success, ) = msg.sender.call{value: amount}('');
    require(success, "Transfer failed.");
  }
  
  function setCharityAddress(address payable _address) external onlyOwner {
    charityAddress = _address;
  }

  function getBNBPrice(uint256 dollarAmount) private returns (uint256) {
    (
      uint80 roundID, 
      int price,
      uint startedAt,
      uint timeStamp,
      uint80 answeredInRound
    ) = priceFeed.latestRoundData();
    require(price > 0 && uint(price)*dollarAmount > 0, 
            'Something went terribly wrong with chainlink feeds');
    return uint(price)*dollarAmount;
  }
  // we send back accidentally sent ethers
  receive() external payable { revert(); }
}

