pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./LiquidityPoolConfig.sol";
import "../interface/IPriceOracle.sol";

// LiquidityPool implements the contract for handling stable coin
// and synthetic tokens liquidity pools and providing core DeFi
// function for tokens minting, trading and lending.
// NOTE: We use ChainLink compatible oracles to compare token values.
// ChainLink oracles provide all USD pairs with 8 digits shift currently.
// E.g. value 100,000,000 = 1 USD.
contract LiquidityPool is Ownable, ReentrancyGuard, LiquidityPoolConfig {
    // define used libs
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // -------------------------------------------------------------
    // Collateral data set keeps information about the locked
    // collateral against which the token borrowing is available.
    // -------------------------------------------------------------

    // _collateral tracks token => user => collateral amount relationship
    mapping(address => mapping(address => uint256)) public _collateral;

    // _collateralTokens tracks user => token => collateral amount relationship
    mapping(address => mapping(address => uint256)) public _collateralTokens;

    // _collateralList tracks user => collateral tokens list
    mapping(address => address[]) public _collateralList;

    // _collateralValue tracks user => collateral value in ref. denomination (fUSD)
    // please note this is a stored value from the last collateral calculation
    // and may not be accurate due to the ref. denomination exchange rate change.
    // NOTE: We use ChainLink compatible ref. oracles which provide all USD pairs
    // with 8 digits shift. fUSD is kept in 18 digits.
    mapping(address => uint256) public _collateralValue;

    // -------------------------------------------------------------
    // Debt data set keeps information about the borrowed
    // tokens value.
    // -------------------------------------------------------------

    // _debt tracks token => user => debt amount relationship
    mapping(address => mapping(address => uint256)) public _debt;

    // _debtTokens tracks user => token => debt amount relationship
    mapping(address => mapping(address => uint256)) public _debtTokens;

    // _debtList tracks user => debt tokens list
    mapping(address => address[]) public _debtList;

    // _debtValue tracks user => debt value in ref. denomination (fUSD)
    // please note this is a stored value from the last debt calculation
    // and may not be accurate due to the ref. denomination exchange
    // rate change.
    // NOTE: We use ChainLink compatible ref. oracles which provide all USD pairs
    // with 8 digits shift. The fUSD is kept in 18 digits.
    mapping(address => uint256) public _debtValue;

    // -------------------------------------------------------------
    // Minting data keeps information about the amount of tokens
    // minted for particular user.
    // -------------------------------------------------------------

    // _debt tracks token => user => minted amount relationship
    mapping(address => mapping(address => uint256)) public _minted;

    // _debtTokens tracks user => token => minted amount relationship
    mapping(address => mapping(address => uint256)) public _mintedTokens;

    // -------------------------------------------------------------
    // Containers and pools.
    // -------------------------------------------------------------

    // feePool keeps information about the fee collected from
    // internal operations, especially buy/sell and borrow/repay in fUSD.
    // NOTE: We use ChainLink compatible ref. oracles which provide all USD pairs
    // with 8 digits shift. The fUSD is kept in 18 digits.
    uint256 public feePool;

    // -------------------------------------------------------------
    // Emitted events.
    // -------------------------------------------------------------

    // Deposit is emitted on token received to deposit
    // increasing user's collateral value.
    event Deposit(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // Withdraw is emitted on confirmed token withdraw
    // from the deposit decreasing user's collateral value.
    event Withdraw(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // Borrow is emitted on confirmed token loan against user's collateral value.
    event Borrow(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // Repay is emitted on confirmed token repay of user's debt of the token.
    event Repay(address indexed token, address indexed user, uint256 amount, uint256 timestamp);

    // Buy is emitted on confirmed token purchase towards user's token balance.
    event Buy(address indexed token, address indexed user, uint256 amount, uint256 exchangeRate, uint256 timestamp);

    // Sell is emitted on confirmed token sale from user's token balance.
    event Sell(address indexed token, address indexed user, uint256 amount, uint256 exchangeRate, uint256 timestamp);

    // -------------------------------------------------------------
    // Token lists management and utility functions
    // -------------------------------------------------------------

    // addCollateralToList ensures the specified token is in user's list of collateral tokens.
    function addCollateralToList(address _token, address _owner) internal {
        bool found = false;
        address[] memory list = _collateralList[_owner];

        // loop the current list and try to find the token
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            _collateralList[_owner].push(_token);
        }
    }

    // addDebtToList ensures the specified token is in user's list of debt tokens.
    function addDebtToList(address _token, address _owner) internal {
        bool found = false;
        address[] memory list = _debtList[_owner];

        // loop the list and try to find the token
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _token) {
                found = true;
                break;
            }
        }

        // add the token to the list if not found
        if (!found) {
            _debtList[_owner].push(_token);
        }
    }

    // readyBalance is used to assert we have enough <tokens> to cover
    // specified <amount>. The token is minted, if needed to be replenished.
    function readyBalance(address _token, uint256 _amount, address _user) internal {
        // do we have enough ERC20 tokens locally to satisfy the withdrawal?
        uint256 balance = ERC20(_token).balanceOf(address(this));
        if (balance < _amount) {
            // mint the missing balance for the ERC20 tokens to cover the transfer
            // the local address has to have the minter privilege
            ERC20Mintable(_token).mint(address(this), _amount.sub(balance));

            // register the amount of minted tokens
            _minted[_token][_user].add(_amount.sub(balance));
            _mintedTokens[_user][_token].add(_amount.sub(balance));
        }
    }

    // collateralListCount returns the number of tokens registered
    // for the given user on collateral list.
    function collateralListCount(address _owner) public view returns (uint256) {
        // any collateral at all?
        if (_collateralValue[_owner] == 0) {
            return 0;
        }

        // return the current collateral array length
        return _collateralList[_owner].length;
    }

    // debtListCount returns the number of tokens registered
    // for the given user on debt list.
    function debtListCount(address _owner) public view returns (uint256) {
        // any debt at all?
        if (_debtValue[_owner] == 0) {
            return 0;
        }

        // return the current debt tokens array length
        return _debtValue[_owner].length;
    }

    // priceDigitsCorrection returns the correction required
    // for FTM/ERC20 (18 digits) to another 18 digits number exchange
    // through an 8 digits USD (ChainLink compatible) price oracle.
    function priceDigitsCorrection() public pure returns (uint256) {
        // 10 ^ (srcDigits - (dstDigits - priceDigits))
        // return 10 ** (18 - (18 - 8));
        return 100000000;
    }

    // ------------------------------------------------------------------------
    // Collateral and debt value calculation.
    // Note: We need to make sure to calculate with the same decimals here.
    //       Verify the price oracle decimals setup!
    // ------------------------------------------------------------------------

    // collateralValue calculates the current value of all collateral assets
    // of a user in the ref. denomination (fUSD).
    function collateralValue(address _user) public view returns (uint256 cValue)
    {
        // loop all registered collateral tokens of the user
        for (uint i = 0; i < _collateralList[_user].length; i++) {
            // get the current exchange rate of the specific token
            uint256 rate = IPriceOracle(priceOracle).getPrice(_collateralList[_user][i]);

            // add the asset token value to the total <asset value> = <asset amount> * <rate>
            // the range is corrected for the FUSD digits.
            // where the asset amount is taken from the mapping
            // _collateral: token address => owner address => amount
            cValue = cValue.add(_collateral[_collateralList[_user][i]][_user].mul(rate).div(priceDigitsCorrection()));
        }

        return cValue;
    }

    // debtValue calculates the current value of all collateral assets
    // of a user in the ref. denomination (fUSD).
    function debtValue(address _user) public view returns (uint256 dValue)
    {
        // loop all registered debt tokens of the user
        for (uint i = 0; i < _debtList[_user].length; i++) {
            // get the current exchange rate of the specific token
            uint256 rate = IPriceOracle(priceOracle).getPrice(_debtList[_user][i]);

            // add the token debt value to the total <asset value> = <asset amount> * <rate>
            // the range is corrected for the FUSD digits.
            // where the asset amount is taken from the mapping
            // _collateral: token address => owner address => amount
            dValue = dValue.add(_debt[_debtList[_user][i]][_user].mul(rate).div(priceDigitsCorrection()));
        }

        return dValue;
    }

    // ------------------------------------------------------------------------
    // Collateral assets management section
    // ------------------------------------------------------------------------

    // deposit receives assets (any token including native FTM and fUSD) to build up
    // the collateral value. The collateral can be used later to borrow tokens.
    // The call does not subtract any fee. No interest is granted.
    function deposit(address _token, uint256 _amount) external payable nonReentrant
    {
        // make sure a non-zero value is being deposited
        require(_amount > 0, "non-zero amount required");

        // if this is a non-native token, verify that the user has enough balance
        // of the ERC20 token to send the designated amount to the deposit
        if (_token != nativeToken) {
            require(msg.value == 0, "only ERC20 token expected, native token received");
            require(_amount <= ERC20(_token).balanceOf(msg.sender), "token balance too low");
        } else {
            // on native tokens, the designated amount deposited must match
            // the native tokens attached to this transaction
            require(msg.value == _amount, "invalid native tokens amount received");
        }

        // update the collateral value storage
        _collateral[_token][msg.sender] = _collateral[_token][msg.sender].add(_amount);
        _collateralTokens[msg.sender][_token] = _collateralTokens[msg.sender][_token].add(_amount);

        // make sure the token is on the list of collateral tokens for the sender
        addCollateralToList(_token, msg.sender);

        // re-calculate the current value of the whole collateral deposit
        // across all assets kept
        _collateralValue[msg.sender] = collateralValue(msg.sender);

        // is this an ERC20 token?
        // if it's a native token, we already received the balance along with the trx
        if (_token != nativeToken) {
            // ERC20 tokens must be transferred from the sender to this contract
            // address by ERC20 safe transfer call
            ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // emit the event signaling a successful deposit
        emit Deposit(_token, msg.sender, _amount, block.timestamp);
    }

    // withdraw subtracts any deposited collateral token, including native FTM,
    // that has a value, from the contract. The remaining collateral value is compared
    // to the minimal required collateral to debt ratio and the transfer is rejected
    // if the ratio is lower than the enforced one.
    function withdraw(address _token, uint256 _amount) external nonReentrant {
        // make sure the requested withdraw amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // update collateral value of the token to a new value
        // we don't need to check the current balance against the requested withdrawal
        // the SafeMath does that validation for us inside the <.sub> call.
        _collateral[_token][msg.sender] = _collateral[_token][msg.sender].sub(_amount, "withdraw amount exceeds balance");
        _collateralTokens[msg.sender][_token] = _collateralTokens[msg.sender][_token].sub(_amount, "withdraw amount exceeds balance");

        // calculate the collateral and debt values in ref. denomination
        // for the current exchange rate and balance amounts
        uint256 cDebtValue = debtValue(msg.sender);
        uint256 cCollateralValue = collateralValue(msg.sender);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue.mul(colLowestRatio4dec).div(ratioDecimalsCorrection);

        // does the new state complain with the enforced minimal collateral to debt ratio?
        // if the check fails, the collateral state change above is reverted by EVM
        require(cCollateralValue >= minCollateralValue, "collateral value below allowed ratio");

        // the new state is ok; update the state values
        _collateralValue[msg.sender] = cCollateralValue;
        _debtValue[msg.sender] = cDebtValue;

        // is this a native token or ERC20 withdrawal?
        if (_token != nativeToken) {
            // do we have enough ERC20 tokens to satisfy the withdrawal?
            readyBalance(_token, _amount, msg.sender);

            // transfer the requested amount of ERC20 tokens to the caller
            ERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            // native tokens are being withdrawn; transfer the requested amount
            // we transfer control to the recipient here, so we have to mittigate re-entrancy
            // solhint-disable-next-line avoid-call-value
            (bool success,) = msg.sender.call.value(_amount)("");
            require(success, "unable to send withdraw");
        }

        // signal the successful asset withdrawal
        emit Withdraw(_token, msg.sender, _amount, block.timestamp);
    }

    // ------------------------------------------------------------------------
    // FTrade - ERC20 tokens direct exchange (buy/sell) for fUSD tokens section
    // ------------------------------------------------------------------------

    // buy allows user to buy a token for fUSD directly
    // A configured trade fee is applied to the purchase.
    // Native tokens and fUSD tokens can not be directly purchased here.
    function buy(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the purchased amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // buyer can not trade native FTM tokens and fUSD here
        require(_token != nativeToken, "native token trading prohibited");
        require(_token != fUsdToken, "fUSD token trading prohibited");

        // get the token to the fUSD exchange rate
        // we use fUSD as the ref. denomination
        uint256 exRate = IPriceOracle(priceOracle).getPrice(_token);
        require(exRate > 0, "token has no value");

        // calculate the purchase value with the corresponding fee
        // e.g. how much fUSD should I pay to get the <amount> of tokens
        // NOTE: the exRate decimals need to be taken into consideration here!
        uint256 buyValue = _amount.mul(exRate).div(priceDigitsCorrection());
        uint256 fee = buyValue.mul(tradeFee4dec).div(ratioDecimalsCorrection);
        uint256 buyValueIncFee = buyValue.add(fee);

        // verify the buyer has enough balance to pay the price and fee
        uint256 balance = ERC20(fUsdToken).balanceOf(msg.sender);
        require(balance >= buyValueIncFee, "insufficient funds");

        // claim fUSD value of the purchase including the fee from the trader
        ERC20(fUsdToken).safeTransferFrom(msg.sender, address(this), buyValueIncFee);

        // make sure we have enough tokens in the pool
        readyBalance(_token, _amount, msg.sender);

        // transfer the purchased token amount to the buyer
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // remember how much we gained from the fee
        feePool = feePool.add(fee);

        // notify successful purchase
        emit Buy(_token, msg.sender, _amount, exRate, block.timestamp);
    }

    // sell allows user to sell a token for fUSD directly
    // A configured trade fee is applied to the sale.
    // Native tokens and fUSD tokens can not be directly sold here.
    function sell(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the purchased amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // buyer can not trade native FTM tokens and fUSD here
        require(_token != nativeToken, "native token trading prohibited");
        require(_token != fUsdToken, "fUSD token trading prohibited");

        // does the seller have enough balance to cover the sale?
        uint256 balance = ERC20(_token).balanceOf(msg.sender);
        require(balance >= _amount, "insufficient funds");

        // get the exchange rate of the token to fUSD
        uint256 exRate = IPriceOracle(priceOracle).getPrice(_token);
        require(exRate > 0, "token has no value");

        // what's the value of the token being sold in fUSD
        // e.g. how much fUSD should I get selling the <amount> of tokens
        uint256 sellValue = _amount.mul(exRate).div(priceDigitsCorrection());

        // what is the fee of the sale? and how much of the fUSD the seller actually gets
        uint256 fee = sellValue.mul(tradeFee4dec).div(ratioDecimalsCorrection);
        uint256 sellValueExFee = sellValue.sub(fee);

        // claim sold token
        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // make sure we have enough fUSD tokens to cover the sale
        // what is the practical meaning of minting fUSD here
        // if the pool is depleted?
        readyBalance(fUsdToken, sellValueExFee, msg.sender);

        // transfer fUSD tokens to the seller
        ERC20(fUsdToken).safeTransfer(msg.sender, sellValueExFee);

        // remember the fee we gained from this trade
        feePool = feePool.add(fee);

        // notify successful sale
        emit Sell(_token, msg.sender, _amount, exRate, block.timestamp);
    }

    // trade executes a direct exchange trade from source token
    // to destination token using subsequent sell and buy operations.
    // The trade always goes through the fUSD as the only allowed
    // trade value reference.
    function trade(address _fromToken, address _toToken, uint256 _amount) external nonReentrant {
        // make sure the purchased amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // native token can not be used in trades
        require(_fromToken != nativeToken, "native token trading prohibited");
        require(_toToken != nativeToken, "native token trading prohibited");

        // two different tokens must be used here
        require(_toToken != _fromToken, "different tokens expected");

        // does the seller have enough balance to cover the sale?
        uint256 balance = ERC20(_fromToken).balanceOf(msg.sender);
        require(balance >= _amount, "insufficient funds");

        // what is the sell value of the source token in fUSD
        uint256 sellValue = _amount;
        if (_fromToken != fUsdToken) {
            // get the exchange rate of the token to fUSD
            uint256 fromRate = IPriceOracle(priceOracle).getPrice(_fromToken);
            require(fromRate > 0, "token has no value");

            // what's the value of the token being sold in fUSD
            // e.g. how much fUSD should I get selling the <amount> of tokens
            sellValue = _amount.mul(fromRate).div(priceDigitsCorrection());

            // notify about the selling of the source token
            emit Sell(_fromToken, msg.sender, _amount, fromRate, block.timestamp);
        }

        // what is the fee of the sale? how much fUSD is left for the trade?
        uint256 fee = sellValue.mul(tradeFee4dec).div(ratioDecimalsCorrection);
        uint256 sellValueExFee = sellValue.sub(fee);

        // what is the buy amount
        uint256 buyAmount = sellValueExFee;
        if (_toToken != fUsdToken) {
            // get the exchange rate of the token to fUSD
            uint256 toRate = IPriceOracle(priceOracle).getPrice(_toToken);
            require(toRate > 0, "token has no value");

            // how much target tokens can I get for the gained fUSD ex. fee
            buyAmount = sellValueExFee.mul(priceDigitsCorrection()).div(toRate);

            // notify about the purchase of the target token
            emit Buy(_toToken, msg.sender, buyAmount, toRate, block.timestamp);
        }

        // claim sold token
        ERC20(_fromToken).safeTransferFrom(msg.sender, address(this), _amount);

        // remember the fee we gained from this trade
        feePool = feePool.add(fee);

        // make sure we have enough target tokens to cover the trade
        readyBalance(_toToken, buyAmount, msg.sender);

        // transfer target tokens to the buyer
        ERC20(_toToken).safeTransfer(msg.sender, buyAmount);
    }

    // ------------------------------------------------------------------------
    // FLend - ERC20 tokens lending (borrow/repay) section
    // ------------------------------------------------------------------------

    // borrow allows user to borrow a specified token against already established
    // collateral. The value of the collateral must be in at least <colLowestRatio4dec>
    // ratio to the total user's debt value on borrowing.
    function borrow(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the debt amount makes sense
        require(_amount > 0, "non-zero amount expected");

        // native tokens can not be borrowed through this contract
        require(_token != nativeToken, "native token not borrowable");

        // make sure there is some collateral established by this user
        // we still need to re-calculate the current value though, since the value
        // could have changed due to exchange rate fluctuation
        require(_collateralValue[msg.sender] > 0, "collateral must be greater than 0");

        // what is the value of the borrowed token?
        uint256 tokenValue = IPriceOracle(priceOracle).getPrice(_token);
        require(tokenValue > 0, "debt token has no value");

        // calculate the entry fee and remember the value we gained
        uint256 fee = _amount.mul(tokenValue).div(priceDigitsCorrection()).mul(loanEntryFee4dec).div(ratioDecimalsCorrection);
        feePool = feePool.add(fee);

        // register the debt of fee in fUSD so we can calculate the new state
        _debt[fUsdToken][msg.sender] = _debt[fUsdToken][msg.sender].add(fee);
        _debtTokens[msg.sender][fUsdToken] = _debtTokens[msg.sender][fUsdToken].add(fee);
        addDebtToList(fUsdToken, msg.sender);

        // register the debt of borrowed token so we can calculate the new state
        _debt[_token][msg.sender] = _debt[_token][msg.sender].add(_amount);
        _debtTokens[msg.sender][_token] = _debtTokens[msg.sender][_token].add(_amount);
        addDebtToList(_token, msg.sender);

        // recalculate current collateral and debt values in fUSD
        uint256 cCollateralValue = collateralValue(msg.sender);
        uint256 cDebtValue = debtValue(msg.sender);

        // minCollateralValue is the minimal collateral value required for the current debt
        // to be within the minimal allowed collateral to debt ratio
        uint256 minCollateralValue = cDebtValue.mul(colLowestRatio4dec).div(ratioDecimalsCorrection);

        // does the new state complain with the enforced minimal collateral to debt ratio?
        // if the check fails, the debt state change above is reverted by EVM
        require(cCollateralValue >= minCollateralValue, "insufficient collateral");

        // update the current collateral and debt value
        _collateralValue[msg.sender] = cCollateralValue;
        _debtValue[msg.sender] = cDebtValue;

        // make sure we have enough of the target tokens to lend
        readyBalance(_token, _amount, msg.sender);

        // transfer borrowed tokens to the user's address
        ERC20(_token).safeTransfer(msg.sender, _amount);

        // emit the borrow notification
        emit Borrow(_token, msg.sender, _amount, block.timestamp);
    }

    // repay allows user to return some of the debt of the specified token
    // the repay does not collect any fees and is not validating the user's total
    // collateral to debt position.
    function repay(address _token, uint256 _amount) external nonReentrant
    {
        // make sure the amount repaid makes sense
        require(_amount > 0, "non-zero amount expected");

        // native tokens can not be borrowed through this contract
        // so there is no debt to be repaid on it
        require(_token != nativeToken, "native token not borrowable");

        // subtract the returned amount from the user's debt
        _debt[_token][msg.sender] = _debt[_token][msg.sender].sub(_amount, "insufficient debt outstanding");
        _debtTokens[msg.sender][_token] = _debtTokens[msg.sender][_token].sub(_amount, "insufficient debt outstanding");

        // update current collateral and debt amount state
        _collateralValue[msg.sender] = collateralValue(msg.sender);
        _debtValue[msg.sender] = debtValue(msg.sender);

        // collect the tokens to be returned
        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // emit the repay notification
        emit Repay(_token, msg.sender, _amount, block.timestamp);
    }

    // -------------------------------------------------------------------------
    // FLend - liquidation section
    // -------------------------------------------------------------------------
    // The liquidation must be monitored off-chain and is executed on an account
    // if the collateral value to debt value ratio drops below pre-configured
    // liquidation ratio. The user's collateral and debt position is
    // cleared and all the remaining collateral assets are collected.
    //
    // NOTE: Shouldn't this function be under an access control?
    // -------------------------------------------------------------------------
    function liquidate(address _owner) external nonReentrant
    {
        // recalculate the collateral and debt values so we have the most recent
        // picture of the whole situation
        _collateralValue[_owner] = collateralValue(_owner);
        _debtValue[_owner] = debtValue(_owner);

        // criCollateralValue is the critical collateral value required for the current debt
        // to be above the liquidation border line; if the actual collateral value drops
        // below this critical line, the position is liquidated and all the remaining collateral
        // assets are collected.
        uint256 criCollateralValue = _debtValue[_owner].mul(colLiquidationRatio4dec).div(ratioDecimalsCorrection);

        // is the owner below critical line?
        require(_collateralValue[_owner] < criCollateralValue, "insufficient debt to liquidate");

        // we are on the liquidation; let's drop the collateral
        // we use math here to make sure the value didn't change from our last look
        for (uint i = 0; i < _collateralList[_owner].length; i++) {
            _collateral[_collateralList[_owner][i]][_owner] = _collateral[_collateralList[_owner][i]][_owner].sub(_collateralTokens[_owner][_collateralList[_owner][i]], "liquidation exceeds balance");
            _collateralTokens[_owner][_collateralList[_owner][i]] = _collateralTokens[_owner][_collateralList[_owner][i]].sub(_collateralTokens[_owner][_collateralList[_owner][i]], "liquidation exceeds balance");
        }

        // drop the debt as well
        for (uint i = 0; i < _debtList[_owner].length; i++) {
            _debt[_debtList[_owner][i]][_owner] = _debt[_debtList[_owner][i]][_owner].sub(_debt[_owner][_debtList[_owner][i]], "liquidation exceeds balance");
            _debtTokens[_owner][_debtList[_owner][i]] = _debtTokens[_owner][_debtList[_owner][i]].sub(_debtTokens[_owner][_debtList[_owner][i]], "liquidation exceeds balance");
        }

        // update the values of collateral and debt to reflect the changed state
        _collateralValue[_owner] = collateralValue(_owner);
        _debtValue[_owner] = debtValue(_owner);
    }
}
