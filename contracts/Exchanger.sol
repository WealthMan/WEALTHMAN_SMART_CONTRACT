pragma solidity ^0.4.21;

import "./AbstractToken.sol";
import "./PortfolioInterface.sol";

contract Exchanger {
    address public admin;

    uint public constant BASE = 1000000000000000000;
    uint public forOrderAllowableTime = 3 hours;

    mapping (address => bool) public isTokenAllowed;
    mapping (address => bool) public isPortfolio;

    struct Order {
        address portfolioFrom;
        address fromToken;
        address toToken;
        uint amount;
        uint timestamp;
        bool isActive;
    }

    Order[] public orders;
    bool private lockOrders = false;
    
    modifier onlyAdmin() { 
        require(msg.sender == admin); 
        _; 
    }
    modifier onlyPortfoilio() {
        require(isPortfolio[msg.sender]);
        _;
    }

    event NewTrade(address portfolio);


    function Exchanger(address _admin) public {
        admin = _admin;
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

    function portfolioTrade(address[] _fromTokens, address[] _toTokens, uint[] _amounts) public onlyPortfoilio {
        assert (!lockOrders);
        lockOrders = true;

        for (uint i = 0; i < _fromTokens.length; i++) {
            assert(isTokenAllowed[_fromTokens[i]] && isTokenAllowed[_toTokens[i]]);

            orders.push(Order({
                portfolioFrom: msg.sender,
                fromToken: _fromTokens[i],
                toToken: _toTokens[i],
                amount: _amounts[i],
                timestamp: now,
                isActive: true
                }));
        }

        lockOrders = false;
        emit NewTrade(msg.sender);
    }

    function doTransfer(address _portfolio, address _fromToken, address _toToken, uint _amount, uint _rate) private returns (bool) {
        if (_fromToken == 0) {
            return transferFromEth(_portfolio, _fromToken, _toToken, _amount, _rate);
        }
        if (_toToken == 0) {
            return transferToEth(_portfolio, _fromToken, _toToken, _amount, _rate);
        }
        return transferTokens(_portfolio, _fromToken, _toToken, _amount, _rate);
    }

    function transferFromEth(address _portfolio, address _fromToken, address _toToken, uint _amount, uint _rate) private returns (bool) {
        require(_fromToken == 0);

        uint needAmount = calcNeedAmount(_amount, _rate);
        AbstractToken token = AbstractToken(_toToken);
        if (token.balanceOf(address(this)) < needAmount) {
            return false;
        }

        PortfolioInterface portfolioContact = PortfolioInterface(_portfolio);
        portfolioContact.transferEth(_amount);
        assert(token.transfer(_portfolio, needAmount));

        return true;
    }

    function transferToEth(address _portfolio, address _fromToken, address _toToken, uint _amount, uint _rate) private returns (bool) {
        require(_toToken == 0);

        uint needAmount = calcNeedAmount(_amount, _rate);
        AbstractToken token = AbstractToken(_fromToken);
        if (address(this).balance <= needAmount) {
            return false;
        }

        assert(token.transferFrom(_portfolio, address(this), _amount));
        assert(_portfolio.send(needAmount));

        return true;
    }

    function transferTokens(address _portfolio, address _fromToken, address _toToken, uint _amount, uint _rate) private returns (bool) {
        uint needAmount = calcNeedAmount(_amount, _rate);
        AbstractToken fromToken = AbstractToken(_fromToken);
        AbstractToken toToken = AbstractToken(_toToken);
        if (toToken.balanceOf(address(this)) < needAmount) {
            return false;
        }

        assert(fromToken.transferFrom(_portfolio, address(this), _amount));
        assert(toToken.transfer(_portfolio, needAmount));

        return true;
    }

    function calcNeedAmount(uint _amount, uint _cur) private pure returns (uint) {
        uint res = _amount * _cur;
        assert (res / _amount == _cur);
        return res / BASE;
    }

    function completeOrders(uint[] indices, uint[] rates) public onlyAdmin {
        require(indices.length == rates.length && indices.length > 0);

        assert(!lockOrders);
        lockOrders = true;

        for (uint i = 0; i < indices.length; i++) {
            if (!orders[indices[i]].isActive) {
                continue;
            }

            if (doTransfer(orders[indices[i]].portfolioFrom, orders[indices[i]].fromToken, orders[indices[i]].toToken,
                           orders[indices[i]].amount, rates[i])) {
                PortfolioInterface(orders[indices[i]].portfolioFrom).transferCompleted(orders[indices[i]].fromToken,
                                   orders[indices[i]].toToken, orders[indices[i]].amount, rates[i]);
                orders[indices[i]].isActive = false;
            }
        }

        lockOrders = false;
    }

    function cleanOrders() public onlyAdmin {
        assert(!lockOrders);
        lockOrders = true;

        Order[] memory newOrders = new Order[](orders.length);
        uint sz = 0;

        for (uint i = 0; i < orders.length; i++) {
            if (now - orders[i].timestamp > forOrderAllowableTime && orders[i].isActive) {
                PortfolioInterface(orders[i].portfolioFrom).transferTimeExpired(orders[i].fromToken, orders[i].toToken, orders[i].amount);
                orders[i].isActive = false;
            }

            if (orders[i].isActive) {
                newOrders[sz++] = orders[i];
            }
        }

        delete(orders);
        for (i = 0; i < sz; i++) {
            orders.push(newOrders[i]);
        }

        lockOrders = false;
    }

    function cancelOrder(uint i) public onlyAdmin {
        assert(!lockOrders);
        lockOrders = true;

        PortfolioInterface(orders[i].portfolioFrom).transferCanceled(orders[i].fromToken, orders[i].toToken, orders[i].amount);
        orders[i].isActive = false;

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