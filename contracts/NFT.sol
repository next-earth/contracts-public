// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
abstract contract ContextMixin {
  function msgSender()
  internal
  view
  returns (address payable sender)
  {
    if (msg.sender == address(this)) {
      bytes memory array = msg.data;
      uint256 index = msg.data.length;
      assembly {
        // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
        sender := and(
          mload(add(array, index)),
          0xffffffffffffffffffffffffffffffffffffffff
        )
      }
    } else {
      sender = payable(msg.sender);
    }
    return sender;
  }
}

contract NFT is ERC721Upgradeable, ERC721EnumerableUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ERC721BurnableUpgradeable, ContextMixin, ERC2771ContextUpgradeable {

  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  mapping ( uint256 => address ) public firstOwners;
  string private baseUri;
  address public merchant;
  address[] public operators;
  event TokenMint(address minter, uint256 tokenId);
  function initialize(string memory _baseUri, address _merchant) public initializer {
    __ERC721_init("NextEarth", "NE");
    __ERC2771Context_init(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE);
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(PAUSER_ROLE, _msgSender());
    _setupRole(MINTER_ROLE, _msgSender());
    baseUri = _baseUri;
    merchant = _merchant;
  }
  function pause() public {
    require(hasRole(PAUSER_ROLE, _msgSender()));
    _pause();
  }

  function unpause() public {
    require(hasRole(PAUSER_ROLE, _msgSender()));
    _unpause();
  }

  function safeMint(uint256[] calldata tokenIds, bytes calldata sig) public {
    bytes32 hash = keccak256(abi.encodePacked(_msgSender(), tokenIds));
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(hash);
    address signer = ECDSA.recover(prefixedHash, sig);
    require(signer == merchant, 'invalid merchant signature');
    uint256 i;
    // We don't have the usual DoS issue here as every operation
    // happens against a signle user... so you can only DoS yourself
    for(i=0; i<tokenIds.length; i++) {
      _safeMint(_msgSender(), tokenIds[i]);
      firstOwners[tokenIds[i]] = _msgSender();
    }
  }

  function safeMintTo(address to, uint256[] calldata tokenIds) public {
    require(hasRole(MINTER_ROLE, _msgSender()), 'Permission denied');
    uint256 i;
    // We don't have the usual DoS issue here as every operation
    // happens against a signle user... so you can only DoS yourself
    for(i=0; i<tokenIds.length; i++) {
      _safeMint(to, tokenIds[i]);
      firstOwners[tokenIds[i]] = to;
      emit TokenMint(to,tokenIds[i]);
    }
  }


  function firstOwnerOf(uint256 tokenId) public view returns (address) {
    return firstOwners[tokenId];
  }

  function baseURI() public view returns (string memory) {
    return baseUri;
  }


  function setBaseURI(string calldata _baseUri) public {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), 'Permission denied');
    baseUri = _baseUri;
  }

  function ownerOf(uint256 _tokenId) public view override(ERC721Upgradeable) returns (address) {
    bool exists = _exists(_tokenId);
    if (!exists) return address(0);
    else return super.ownerOf(_tokenId);
  }

  function split(uint256 tokenId, uint256[] calldata parcels, bytes calldata sig) public {
    require(ownerOf(tokenId) == _msgSender(), "only the token owner can split lands");
    require(parcels.length > 1, "you can only split into multiple lands");
    bytes32 hash = keccak256(abi.encodePacked(_msgSender(), tokenId, parcels));
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(hash);
    address signer = ECDSA.recover(prefixedHash, sig);
    require(signer == merchant, 'invalid merchant signature');
    uint i;
    for(i=0; i<parcels.length; i++) {
      require(_exists(parcels[i]) == false, "parcel already assigned to other address");
    }
    _burn(tokenId);
    for(i=0; i<parcels.length; i++) {
      _safeMint(_msgSender(), parcels[i]);
      firstOwners[parcels[i]] = _msgSender();
    }
  }

  function merge(uint256[] calldata parcels, uint256 tokenId, bytes calldata sig) public {
    require(parcels.length > 1, 'you can only merge multiple lands');
    bytes32 hash = keccak256(abi.encodePacked(_msgSender(), parcels, tokenId));
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(hash);
    address signer = ECDSA.recover(prefixedHash, sig);
    require(signer == merchant, 'invalid merchant signature');
    uint i;
    for(i=0; i<parcels.length; i++) {
      require(ownerOf(parcels[i]) == _msgSender(), "only the token owner can merge lands");
    }
    require(_exists(tokenId) == false, "token already assigned to other address");
    for(i=0; i<parcels.length; i++) {
      _burn(parcels[i]);
    }
    _safeMint(_msgSender(), tokenId);
    firstOwners[tokenId] = _msgSender();
  }

  function _beforeTokenTransfer(address from, address to, uint256 tokenId)
  internal
  whenNotPaused
  override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
  {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
  public
  view
  override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
  returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
  /**
  * Override isApprovedForAll to auto-approve OS's proxy contract
   */
  function isApprovedForAll(
    address _owner,
    address _operator
  ) public override view returns (bool isOperator) {
    // if OpenSea's ERC721 Proxy Address is detected, auto-return true
    isOperator = false;
    for(uint256 i=0; i<operators.length; i++) {
      if (_operator == operators[i]) {
        return true;
      }
    }

    // otherwise, use the default ERC721.isApprovedForAll()
    return ERC721Upgradeable.isApprovedForAll(_owner, _operator);
  }

  function setOperators(address[] calldata _ops) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), 'Permission Denied');
    operators = _ops;
  }

  function _msgData() internal view virtual override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
    return ERC2771ContextUpgradeable._msgData();
  }

  function _msgSender() internal override(ContextUpgradeable, ERC2771ContextUpgradeable) view returns (address sender) {
    return ContextMixin.msgSender();
  }

  function migrate(uint256[] calldata tokens, address[] calldata owners, address[] calldata first_owners) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), 'Permission denied');
    require(tokens.length == owners.length);
    require(owners.length == first_owners.length);
    for (uint256 i=0; i<tokens.length; i++) {
      _safeMint(owners[i], tokens[i]);
      firstOwners[tokens[i]] = first_owners[i];
    }
  }

  function version() external pure returns (uint256) {
    return 1;
  }
}
