//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RST is ERC20Pausable, Ownable, ERC20Permit, ERC20Snapshot {

    address public teamAddress;
    address public lpAddress;

    mapping (address => bool) public canBurn;
    mapping (address => bool) public canSnapshot;
    mapping (address => bool) public canTradeBeforeTrading;

    bool public isTradingActive;

    event SetBurnCapability(address addr, bool val);
    event SetSnapshotCapability(address addr, bool val);
    event SetTradeBeforeTradingCapability(address addr, bool val);
    event EnableTrading();
    event WithdrawToken(address token, uint256 balance);
    event WithdrawMatic(uint256 balance);

    constructor(address _teamAddress, address _lpAddress) ERC20("Star Token", "STAR") ERC20Permit("Star Token") {
        teamAddress = _teamAddress;
        lpAddress = _lpAddress;

        isTradingActive = true; // Need to enable it for minting
        _mint(teamAddress, 38e9 * 10 ** decimals());
        _mint(lpAddress, 2e9 * 10 ** decimals());
        isTradingActive = false;

        _setTradeBeforeTradingCapability(msg.sender, true);
    }


    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Pausable, ERC20Snapshot)
    {
        require(isTradingActive || canTradeBeforeTrading[to] || canTradeBeforeTrading[from], "RSToken: Trading is not active");
        super._beforeTokenTransfer(from, to, amount);
    }

    function burn(uint256 amount) external {
      require(amount > 0, "RSToken: Cannot burn zero amount");
      require(canBurn[msg.sender], "RSToken: Sender cannot burn");
      _burn(msg.sender, amount);
    }

    function snapshot() public {
        require(canSnapshot[msg.sender], "RSToken: Sender cannot snapshot");
        _snapshot();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function enableTrading() public onlyOwner {
        isTradingActive = true;
        emit EnableTrading();
    }

    function setBurnCapability(address addr, bool val) external onlyOwner {
      require(addr != address(0), "RSToken: Address cannot be the zero address");
      canBurn[addr] = val;
      emit SetBurnCapability(addr, val);
    }

    function setSnapshotCapability(address addr, bool val) external onlyOwner {
      require(addr != address(0), "RSToken: Address cannot be the zero address");
      canSnapshot[addr] = val;
      emit SetSnapshotCapability(addr, val);
    }

    function setTradeBeforeTradingCapability(address addr, bool val) external onlyOwner {
        _setTradeBeforeTradingCapability(addr, val);
    }

    function _setTradeBeforeTradingCapability(address addr, bool val) internal {
        require(addr != address(0), "RSToken: Address cannot be the zero address");
        canTradeBeforeTrading[addr] = val;
        emit SetTradeBeforeTradingCapability(addr, val);
    }

    function withdrawMatic() external onlyOwner {
      uint256 balance = address(this).balance;
      require(balance > 0, "RSToken: Nothing to withdraw");
      (bool ok,) = msg.sender.call{value: balance}('');
      require(ok, 'RSToken: Withdraw transaction failed');
      emit WithdrawMatic(balance);
    }


    function withdrawToken(address token) external onlyOwner {
      require(token != address(0), "RSToken: Token cannot be the zero address");
      uint256 balance = IERC20(token).balanceOf(address(this));
      require(balance > 0, "RSToken: Nothing to withdraw");
      SafeERC20.safeTransfer(IERC20(token), msg.sender, balance);
      emit WithdrawToken(token, balance);
    }

    receive() external payable {}
}
