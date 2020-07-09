pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";

// LiquidityPoolConfig implements the internal configuration
// and management functionality for the LiquidityPoll contract.
contract LiquidityPoolConfig is Ownable {
    // tradeFee4dec represents the current value of the fee used
    // for trade operations (buy/sell) kept in 4 decimals.
    // E.g. value 25 => 0.0025 => 0.25%
    uint256 tradeFee4dec = 25;

    // loanEntryFee4dec represents the current value of the entry fee used
    // for loan operations (borrow/repay) kept in 4 decimals.
    // E.g. value 25 => 0.0025 => 0.25%
    uint256 loanEntryFee4dec = 25;

    // colLiquidationRatio4dec represents a ratio between collateral
    // value and debt value below which a liquidation of the collateral
    // should be executed. If the current real ratio drops below this
    // value, the user's position is liquidated.
    // The value is kept in 4 decimals, e.g. value 15000 => ratio 1.5x
    uint256 public colLiquidationRatio4dec = 15000;

    // colLowestRatio4dec represents the lowest ratio between collateral
    // value and debt value user can use to borrow tokens against the
    // collateral. Below this ratio a borrow request will be rejected
    // and user needs to increase their collateral to close the deal.
    // The value is kept in 4 decimals, e.g. value 25000 => ratio 2.5x
    uint256 public colLowestRatio4dec = 25000;

    // ratioDecimalsCorrection represents the value to be used to
    // adjust result decimals after applying ratio to a calculation.
    uint256 public ratioDecimalsCorrection = 10000;

    // nativeToken represents the address of the native FTM tokens pool.
    address public nativeToken = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // fUsdToken represents the address of the fUSD stable coin token ERC20 contract.
    address public fUsdToken = 0xC17518AE5dAD82B8fc8b56Fe0295881c30848829;

    // priceOracle represents the address of the price oracle contract used
    // to obtain the current exchange rate between a specified token
    // and the referential fUSD.
    address public priceOracle = 0xC17518AE5dAD82B8fc8b56Fe0295881c30848829;

    // TradeFeeChanged is emitted on the trade fee change.
    event TradeFeeChanged(uint256 fee, uint256 timestamp);

    // LoanEntryFeeChanged is emitted on the loan fee change.
    event LoanEntryFeeChanged(uint256 fee, uint256 timestamp);

    // CollateralLiquidationRatioChanged is emitted on collateral to debt
    // liquidation ratio changes.
    event CollateralLiquidationRatioChanged(uint256 rate, uint256 timestamp);

    // CollateralLowestRatioChanged is emitted on the collateral to debt
    // lowest accepted ratio changes.
    event CollateralLowestRatioChanged(uint256 ratio, uint256 timestamp);

    // PriceOracleChanged is emitted on the change of the price oracle contract address.
    event PriceOracleChanged(address oracle, uint256 timestamp);

    // ----------------------------------------
    // management functions below this line
    // ----------------------------------------

    // setTradeFee changes the current trade fee value.
    // Please make sure to use 4 decimals value to represent the fee,
    // e.g. value 25 is applied as 0.0025 => 0.25%
    function setTradeFee(uint256 fee) onlyOwner external {
        tradeFee4dec = fee;
        emit TradeFeeChanged(fee, now);
    }

    // setLoanEntryFee changes the current loan entry fee value.
    // Please make sure to use 4 decimals value to represent the fee,
    // e.g. value 25 is applied as 0.0025 => 0.25%
    function setLoanEntryFee(uint256 fee) onlyOwner external {
        loanEntryFee4dec = fee;
        emit LoanEntryFeeChanged(fee, now);
    }

    // setCollateralLiquidationRatio changes the current ratio
    // between the collateral and debt below which the debt position
    // should be liquidated.
    function setCollateralLiquidationRatio(uint256 ratio) onlyOwner external {
        colLiquidationRatio4dec = ratio;
        emit CollateralLiquidationRatioChanged(ratio, now);
    }

    // setCollateralLowestRatio changes the current ratio
    // between the collateral and debt below which a borrow request against
    // the collateral will be rejected.
    function setCollateralLowestRatio(uint256 ratio) onlyOwner external {
        colLowestRatio4dec = ratio;
        emit CollateralLowestRatioChanged(ratio, now);
    }

    // setCollateralLowestRatio changes the current ratio
    // between the collateral and debt below which a borrow request against
    // the collateral will be rejected.
    function setPriceOracle(address oracle) onlyOwner external {
        priceOracle = oracle;
        emit PriceOracleChanged(oracle, now);
    }
}
