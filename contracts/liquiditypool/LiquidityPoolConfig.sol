pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";

// LiquidityPoolConfig implements the internal configuration
// and management functionality for the LiquidityPoll contract.
contract LiquidityPoolConfig is Ownable {
    // poolVersion represents the version of the Liquidity Pool contract.
    // Through the version you can verify which source code is deployed
    // to specific address.
    // Current version is: 0.0.11
    uint256 public poolVersion = 0x00B;

    // tradeFee4dec represents the current value of the fee used
    // for trade operations (buy/sell) kept in 4 decimals.
    // E.g. value 25 => 0.0025 => 0.25%
    uint256 public tradeFee4dec = 25;

    // loanEntryFee4dec represents the current value of the entry fee used
    // for loan operations (borrow/repay) kept in 4 decimals.
    // E.g. value 25 => 0.0025 => 0.25%
    uint256 public loanEntryFee4dec = 25;

    // colLiquidationRatio4dec represents a ratio between collateral
    // value and debt value below which a liquidation of the collateral
    // should be executed. If the current real ratio drops below this
    // value, the user's position is liquidated.
    // The value is kept in 4 decimals, e.g. value 15000 => ratio 1.5x
    uint256 public colLiquidationRatio4dec = 15000;

    // colWarningRatio4dec represents a ratio between collateral
    // value and debt value below which a user should be warned about
    // the dangerous ratio zone. If the real ratio drops below this value
    // the liquidation condition will be closely observed by a watchdog.
    // The value is kept in 4 decimals, e.g. value 22500 => ratio 2.25x
    uint256 public colWarningRatio4dec = 22500;

    // colLowestRatio4dec represents the lowest ratio between collateral
    // value and debt value user can use to borrow tokens against the
    // collateral. Below this ratio a borrow request will be rejected
    // and user needs to increase their collateral to close the deal.
    // The value is kept in 4 decimals, e.g. value 25000 => ratio 3x
    uint256 public colLowestRatio4dec = 30000;

    // ratioDecimalsCorrection represents the value to be used to
    // adjust result decimals after applying ratio to a calculation.
    uint256 public ratioDecimalsCorrection = 10000;

    // nativeToken represents the address of the native FTM tokens pool.
    address public nativeToken = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // fUsdToken represents the address of the fUSD stable coin token ERC20 contract.
    address public fUsdToken = 0xf15Ff135dc437a2FD260476f31B3547b84F5dD0b;

    // priceOracle represents the address of the price oracle contract used
    // to obtain the current exchange rate between a specified token
    // and the referential fUSD.
    address public priceOracle = 0x03AFBD57cfbe0E964a1c4DBA03B7154A6391529b;

    // PriceOracleChanged is emitted on the change of the price oracle contract address.
    event PriceOracleChanged(address oracle, uint256 timestamp);

    // ----------------------------------------
    // management functions below this line
    // ----------------------------------------

    // setPriceOracleReferenceAggregate changes the link to the current version
    // of the Price Oracle Reference Aggregate. The oracle ref. aggregate is responsible
    // for providing current oracle price for a given token against the fUSD stable coin.
    function setPriceOracleReferenceAggregate(address oracle) onlyOwner external {
        priceOracle = oracle;
        emit PriceOracleChanged(oracle, now);
    }

    // transferBalance transfers the balance of this contract to the specified
    // target address moving the base liquidity pool of native tokens
    // to a new address.
    function transferBalance(address payable to) onlyOwner external {
        to.transfer(address(this).balance);
    }
}
