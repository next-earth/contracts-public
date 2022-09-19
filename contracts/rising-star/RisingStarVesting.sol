//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * PayeeTypes:
 * 1 - IT / 18,5% / 7_400_000_000
 * 2 - Marketing / 18% / 7_200_000_000
 * 3 - BD / 17,5% / 7_000_000_000
 * 4 - Team / 17% / 6_800_000_000
 * 5 - NE / 10% / 4_000_000_000
 * 6 - LP / 4% / 1_600_000_000
 * 7 - Land / 10% / 4_000_000_000
 */
contract RisingStarVesting {

    uint256 public constant totalSupply = 40 * 1e9 * 1e18; // Total Supply of STAR Token (40_000_000_000)

    // Every percent value multiplied by 10, so 175 means 17,5%
    // Every percent means the percent of the total supply, so 20 means the 2 percentage of the total supply (totalSupply * 20 / 1000 = 800_000_000)
    uint8[7] public unlockedPercent = [20, 15, 10, 0 , 10, 40, 100]; // Immediately available after vesting started
    uint8[12] public departmentPeriodPercent = [20, 25, 20, 15, 15, 10, 10, 10, 10, 10, 10, 10]; // Quarterly (1 quarter = 13 weeks)
    uint8[5] public nePeriodPercent = [20, 20, 20, 20, 10]; // Yearly ( 1 year = 52 weeks)
    uint8[7] public maxAvailableForPayeeType = [185, 180, 175, 170, 100, 40, 100]; // All available tokens for a payeeType in the percent of the total supply

    address public starTokenAddress; // IERC20

    address[] public payees; // 7 element array in fix order
    mapping (address => uint8) public typeOfPayee; // payee => payeeType (0 means it's not a payee)
    mapping (uint8 => uint256) public releasedAmount; // payeeType => amount
    uint256 public vestingStartedAt;

    address[] public owners;
    mapping(address => bool) public isOwner;

    // Use to store a request to change the owners or the payees address array
    struct ChangeRequest {
        address requester;
        address[] changeTo;
    }

    ChangeRequest public ownersChangeRequest; // The currently submitted request to change the owners
    ChangeRequest public payeesChangeRequest; // The currently submitted request to change the payees

    event PayeesChangeRequestSubmitted(ChangeRequest request);
    event OwnersChangeRequestSubmitted(ChangeRequest request);
    event PayeesChangeRequestConfirmed(ChangeRequest request, address confirmer);
    event OwnersChangeRequestConfirmed(ChangeRequest request, address confirmer);

    event OwnersChanged(address[] owners);
    event PayeesChanged(address[] payees);
    event TokenReleased(address payee, uint256 amount, uint8 payeeType);

    // Restrict access of a function for only the {owners}
    modifier onlyOwner() {
        require(isOwner[msg.sender], "RSV: Not owner");
        _;
    }

    // Enable to call a function only after the vesting started
    modifier afterStart() {
        require(vestingStartedAt != 0, "RSV: Vesting is not started yet");
        _;
    }

    /**
     * Sets the initial {owners} and {payees}.
     *
     * The deployer will not be an owner!
     */
    constructor(address[] memory _owners, address[] memory _payees) {
        _setOwners(_owners);
        _setPayees(_payees);
    }

    /**
     * @dev Set the {payees} and emit a {PayeesChanged} event
     *
     * The payees number must be 7 and has a fix order (see in the contract's description)
     */
    function _setPayees(address[] memory _payees) private {
        require(_payees.length == 7, "RSV: Invalid number of payees");
        for (uint8 i = 0; i < payees.length; i++) {
            typeOfPayee[payees[i]] = 0;
        }
        for (uint8 i = 0; i < _payees.length; i++) {
            typeOfPayee[_payees[i]] = i + 1;
        }
        payees = _payees;
        emit PayeesChanged(_payees);
    }

    /**
     * @dev Set the {owners} and emit a {OwnersChanged} event
     *
     * The payees number must be 3.
     * To change the owners or payees two of the three owners.
     */
    function _setOwners(address[] memory _owners) private {
        require(_owners.length == 3, "RSV: Invalid number of owners");
        for (uint8 i = 0; i < owners.length; i++) {
            isOwner[owners[i]] = false;
        }
        for (uint8 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        emit OwnersChanged(_owners);
    }

    /**
     * @dev Create a payees change request to change the {payees} to the {newPayees}
     *
     * Any new request override the previous one if that is not confirmed.
     */
    function submitPayeesChangeRequest(address[] memory newPayees) onlyOwner external {
        require(newPayees.length == 7, "RSV: Invalid number of payees");
        payeesChangeRequest = ChangeRequest({requester: msg.sender, changeTo: newPayees});
        emit PayeesChangeRequestSubmitted(payeesChangeRequest);
    }

    /**
     * @dev Confirm the current payees change request
     */
    function confirmPayeesChangeRequest(address[] memory newPayees) onlyOwner external {
        require(payeesChangeRequest.requester != address(0), "RSV: There is nothing to confirm");
        require(payeesChangeRequest.requester != msg.sender, "RSV: Requester cannot confirm own request");
        require(newPayees.length == 7, "RSV: Invalid number of payees");
        for (uint8 i = 0; i < newPayees.length; i++) {
            require(payeesChangeRequest.changeTo[i] == newPayees[i], "RSV: Confirm address mismatch");
        }
        _setPayees(payeesChangeRequest.changeTo);
        emit PayeesChangeRequestConfirmed(payeesChangeRequest, msg.sender);
        payeesChangeRequest.requester = address(0);
        delete payeesChangeRequest.changeTo;
    }

    /**
     * @dev Create an owners change request to change the {owners} to the {newOwners}
     *
     * Any new request override the previous one if that is not confirmed.
     */
    function submitOwnersChangeRequest(address[] memory newOwners) onlyOwner external {
        require(newOwners.length == 3, "RSV: Invalid number of owners");
        ownersChangeRequest = ChangeRequest({requester: msg.sender, changeTo: newOwners});
        emit OwnersChangeRequestSubmitted(ownersChangeRequest);
    }

    /**
     * @dev Confirm the current owners change request
     */
    function confirmOwnersChangeRequest(address[] memory newOwners) onlyOwner external {
        require(ownersChangeRequest.requester != address(0), "RSV: There is nothing to confirm");
        require(ownersChangeRequest.requester != msg.sender, "RSV: Requester cannot confirm own request");
        require(newOwners.length == 3, "RSV: Invalid number of owners");
        for (uint8 i = 0; i < newOwners.length; i++) {
            require(ownersChangeRequest.changeTo[i] == newOwners[i], "RSV: Confirm address mismatch");
        }
        _setOwners(ownersChangeRequest.changeTo);
        emit OwnersChangeRequestConfirmed(ownersChangeRequest, msg.sender);
        ownersChangeRequest.requester = address(0);
        delete ownersChangeRequest.changeTo;
    }

    // Can only be called once
    function startVesting() external onlyOwner {
        require(vestingStartedAt == 0, "RSV: Vesting already started");
        require(starTokenAddress != address(0), "RSV: STAR Token address must be set");
        require(IERC20(starTokenAddress).balanceOf(address(this)) == totalSupply * 950 / 1000, "RSV: Contract not funded");
        vestingStartedAt = block.timestamp;
    }

    // Can only be called once
    function setStarTokenAddress(address _tokenAddress) external onlyOwner {
        require(starTokenAddress == address(0), "RSV: STAR Token address already set");
        require(_tokenAddress != address(0), "RSV: Star Token address cannot be the zero address");
        starTokenAddress = _tokenAddress;
    }


    /**
     * @dev Release the specified {amount} from the available tokens for a payee.
     */
    function release(uint256 amount) afterStart public {
        uint8 payeeType = typeOfPayee[msg.sender];
        require(payeeType != 0, "RSV: Sender is not payee");

        uint256 availableAmount = _getAvailableAmount(payeeType);
        require(availableAmount > 0, "RSV: No available tokens");
        require(amount <= availableAmount, "RSV: Not enough tokens available");
        if (amount == 0) amount = availableAmount; // When amount is not specified, release all available

        releasedAmount[payeeType] += amount;
        SafeERC20.safeTransfer(IERC20(starTokenAddress), msg.sender, amount);
        emit TokenReleased(msg.sender, amount, payeeType);
    }

    /**
     * @dev Returns the available token amount for a {payeeType}
     */
    function _getAvailableAmount(uint8 payeeType) private view returns (uint256) {
        require(payeeType >= 1 && payeeType <= 7, "RSV: Invalid Payee Type");
        uint256 availableAmount = totalSupply * unlockedPercent[payeeType - 1] / 1000; // The unlocked amount is always available

        if (payeeType >= 1 && payeeType <= 3) { // Department
            uint256 quarterSince = ((block.timestamp - vestingStartedAt) / 1 weeks) / 13; // Number of quarters since the vesting started
            if (quarterSince > departmentPeriodPercent.length) quarterSince = departmentPeriodPercent.length; // No need to calculate after the last period has passed
            
            for (uint256 i = 0; i < quarterSince; i++) {
                availableAmount += totalSupply * departmentPeriodPercent[i] / 1000;
            }
        } else if (payeeType == 4) { // Team
            uint256 weekSince = (block.timestamp - vestingStartedAt) / 1 weeks; // Number of weeks since the vesting started
            if (weekSince > 52 * 4) { // Vesting period starts after 4 years
                if (weekSince > 52 * 4 + 17 * 4) { // After the 17 months vesting period passed
                    availableAmount += totalSupply * 170 / 1000;
                } else { // During the 17 months vesting period
                    availableAmount += totalSupply * (((weekSince - 52 * 4) / 4) * 10) / 1000;
                }
            }
        } else if (payeeType == 5) { // NE
            uint256 yearSince = ((block.timestamp - vestingStartedAt) / 1 weeks) / 52; // Number of years since the vesting started
            if (yearSince > nePeriodPercent.length) yearSince = nePeriodPercent.length; // No need to calculate after the last period has passed
            for (uint256 i = 0; i < yearSince; i++) {
                availableAmount += totalSupply * nePeriodPercent[i] / 1000;
            }
        }   // else if (payeeType == 6 || payeeType == 7) { // LP & Land
            // Nothing to do, there is only the unlocked amount
            // }

        if (availableAmount > totalSupply * maxAvailableForPayeeType[payeeType - 1] / 1000)
            availableAmount = totalSupply * maxAvailableForPayeeType[payeeType - 1] / 1000; // Just for sure
        availableAmount -= releasedAmount[payeeType]; // Always substruct the already released amount
        return availableAmount;
    }

    /**
     * @dev Returns the vesting status for a {payeeType}
     *
     * {payee}: the current address of the payee
     * {available}: the currently available token amount to release
     * {released}: the amount of the already released tokens
     * {vested}: the amount of the currently not available (still vested) tokens
     */
    function getPayeeCurrentStatus(uint8 payeeType) afterStart public view returns (
            address payee,
            uint256 available,
            uint256 released,
            uint256 vested
            )
    {
        require(payeeType >= 1 && payeeType <= 7, "RSV: Invalid Payee Type");
        payee = payees[payeeType - 1];
        available = _getAvailableAmount(payeeType);
        released = releasedAmount[payeeType];
        vested = (totalSupply * maxAvailableForPayeeType[payeeType - 1] / 1000) - available - released;
    }

    // Send back the accidentally sent matic
    receive() external payable { revert(); }

}
