pragma solidity ^0.5.0;

// IPriceOracle defines the interface of the price oracle contract
// used to provide up-to-date information about the value
// of stable coins and synthetic tokes handled by the DeFi contract.
interface IPriceOracle {
    // getPrice implements the oracle for getting a specified token value
    // compared to the underlying stable denomination (USD is used initially).
    function getPrice(address _token) external view returns (uint256);
}
