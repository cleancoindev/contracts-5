pragma solidity ^0.5.5;


import "../ContractManager.sol";

contract FightListing is ContractManager {

    function FightListing() public {

    }

    /**
     * Fallback function
     */
    function () public payable {
        return;
    }
}
