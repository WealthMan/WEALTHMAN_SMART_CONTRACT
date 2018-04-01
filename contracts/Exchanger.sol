pragma solidity ^0.4.21;

import "./AbstractToken.sol";
import "./PortfolioInterface.sol";

contract Exchanger {
    address public admin;
    address public oracle;

    uint public constant BASE = 1000000000000000000;
    uint public forCurrenciesAllowableTime = 30 minutes;
    uint public forOrderAllowableTime = 3 hours;

    mapping (address => bool) public isTokenAllowed;
    mapping (address => bool) public isPortfolio;

    struct Currency {
        uint ratio; // * BASE
        uint timestamp;
    }
    struct Order {
        address portfolioFrom;
        address fromToken;
        address toToken;
        uint amount;
        uint timestamp;
    }

    mapping (address => mapping (address => Currency)) public currencies;

    Order[] public orders;
    bool private lockOrders = false;
    
    modifier onlyAdmin() { 
        require(msg.sender == admin); 
        _; 
    }
    modifier onlyOracle() {
        require(msg.sender == oracle);
        _;
    }
    modifier onlyPortfoilio() {
        require(isPortfolio[msg.sender]);
        _;
    }

    event NeedCurrency(address _from, address _to);
    event NewTrade(address portfolio);


    function Exchanger(address _admin, address _oracle) public {
        admin = _admin;
        oracle = _oracle;
    }

    function changeForCurrienciesAllowableTime(uint _time) public onlyAdmin {
        forCurrenciesAllowableTime = _time;
    }
    function changeForOrderAllowableTime(uint _time) public onlyAdmin {
        forOrderAllowableTime = _time;
    }

    function allowToken(address _token) public onlyAdmin {
        isTokenAllowed[_token] = true;
    }
    function rejectToken(address _token) public onlyAdmin {
        isTokenAllowed[_token] = false;
    }

    function addPortfolio(address _portfolio) public onlyAdmin {
        isPortfolio[_portfolio] = true;
    }

    function updateCurrencies(address[] _fromTokens, address[] _toTokens, uint[] _rates) public onlyOracle {
        require(_fromTokens.length == _toTokens.length && _toTokens.length == _rates.length && _fromTokens.length > 0);

        for (uint i = 0; i < _fromTokens.length; i++) {
            require (_rates[i] != 0);
            currencies[_fromTokens[i]][_toTokens[i]] = Currency({ratio:_rates[i], timestamp:now});
        }
    }


    function portfolioTrade(address[] _fromTokens, address[] _toTokens, uint[] _amounts) public onlyPortfoilio {
        assert (!lockOrders);
        lockOrders = true;

        for (uint i = 0; i < _fromTokens.length; i++) {
            assert(isTokenAllowed[_fromTokens[i]] && isTokenAllowed[_toTokens[i]]);

            if (!doTransfer(msg.sender, _fromTokens[i], _toTokens[i], _amounts[i])) {
                orders.push(Order({
                    portfolioFrom: msg.sender,
                    fromToken: _fromTokens[i],
                    toToken: _toTokens[i],
                    amount: _amounts[i],
                    timestamp: now
                    }));
            }
        }

        lockOrders = false;
        emit NewTrade(msg.sender);
    }

    function doTransfer(address _portfolio, address _fromToken, address _toToken, uint _amount) private returns (bool) {
        if (_fromToken == 0) {
            return transferFromEth(_portfolio, _fromToken, _toToken, _amount);
        }
        if (_toToken == 0) {
            return transferToEth(_portfolio, _fromToken, _toToken, _amount);
        }
        return transferTokens(_portfolio, _fromToken, _toToken, _amount);
    }

    function transferFromEth(address _portfolio, address _fromToken, address _toToken, uint _amount) private returns (bool) {
        if (now - currencies[_fromToken][_toToken].timestamp > forCurrenciesAllowableTime) {
            emit NeedCurrency(_fromToken, _toToken);
            return false;
        }

        uint needAmount = calcNeedAmount(_amount, currencies[_fromToken][_toToken].ratio);
        AbstractToken token = AbstractToken(_toToken);
        if (token.balanceOf(address(this)) < needAmount) {
            return false;
        }

        PortfolioInterface portfolioContact = PortfolioInterface(_portfolio);
        portfolioContact.transferEth(_amount);
        assert(token.transfer(_portfolio, needAmount));

        portfolioContact.transferCompleted();
        return true;
    }

    function transferToEth(address _portfolio, address _fromToken, address _toToken, uint _amount) private returns (bool) {
        if (now - currencies[_fromToken][_toToken].timestamp > forCurrenciesAllowableTime) {
            emit NeedCurrency(_fromToken, _toToken);
            return false;
        }

        uint needAmount = calcNeedAmount(_amount, currencies[_fromToken][_toToken].ratio);
        AbstractToken token = AbstractToken(_fromToken);
        if (address(this).balance <= needAmount) {
            return false;
        }

        assert(token.transferFrom(_portfolio, address(this), _amount));
        assert(_portfolio.send(needAmount));

        PortfolioInterface portfolioContact = PortfolioInterface(_portfolio);
        portfolioContact.transferCompleted();
        return true;
    }

    function transferTokens(address _portfolio, address _fromToken, address _toToken, uint _amount) private returns (bool) {
        if (now - currencies[_fromToken][_toToken].timestamp > forCurrenciesAllowableTime) {
            emit NeedCurrency(_fromToken, _toToken);
            return false;
        }

        uint needAmount = calcNeedAmount(_amount, currencies[_fromToken][_toToken].ratio);
        AbstractToken fromToken = AbstractToken(_fromToken);
        AbstractToken toToken = AbstractToken(_toToken);
        if (toToken.balanceOf(address(this)) < needAmount) {
            return false;
        }

        assert(fromToken.transferFrom(_portfolio, address(this), _amount));
        assert(toToken.transfer(_portfolio, needAmount));

        PortfolioInterface portfolioContact = PortfolioInterface(_portfolio);
        portfolioContact.transferCompleted();
        return true;
    }

    function calcNeedAmount(uint _amount, uint _cur) private pure returns (uint) {
        uint res = _amount * _cur;
        assert (res / _amount == _cur);
        return res / BASE;
    }

    function transferOrders() public onlyAdmin {
        assert(!lockOrders);
        lockOrders = true;

        Order[] memory newOrders = new Order[](orders.length);
        uint sz = 0;

        for (uint i = 0; i < orders.length; i++) {
            PortfolioInterface portfolioContact = PortfolioInterface(orders[i].portfolioFrom);

            if (now - orders[i].timestamp > forOrderAllowableTime) {
                portfolioContact.transferTimeExpired(orders[i].fromToken, orders[i].toToken, orders[i].amount);
            } else {

                if (doTransfer(orders[i].portfolioFrom, orders[i].fromToken, orders[i].toToken, orders[i].amount)) {
                    portfolioContact.transferCompleted();
                } else {
                    newOrders[sz++] = orders[i];
                }
            }
        }
        delete(orders);
        for (i = 0; i < sz; i++) {
            orders.push(newOrders[i]);
        }

        lockOrders = false;
    }

    function sendTokens(address _tokenAddr, uint _amount) public onlyAdmin {
        AbstractToken token = AbstractToken(_tokenAddr);
        assert(token.transfer(admin, _amount));
    }

    function sendEth(uint _amount) public onlyAdmin {
        assert(admin.send(_amount));
    }
}