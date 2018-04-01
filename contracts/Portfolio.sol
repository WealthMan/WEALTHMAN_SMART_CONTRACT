pragma solidity ^0.4.21;


import "./Exchanger.sol";
import "./AbstractToken.sol";

contract Portfolio {
    address public owner;
    address public manager;
    address public exchangerAddr;
    uint public startTime;
    uint public endTime;
    uint public tradesMaxCount;
    uint public depositAmount;
    bool public isRunning = false;
    Exchanger public exchanger;

    bool public wasDeposit = false;
    uint public tradesWasCount = 0;
    bool public onTraiding = false;
    uint public ordersCountLeft;

    address[] public portfolioTokens;
    mapping (address => bool) public usedToken;

    bool public wasCriticalEnd;
    uint public withdrawAmount;
    bool public wasWithdraw = false;

    modifier inRunning { 
        require(isRunning); 
        _; 
    }
    modifier onlyOwner { 
        require(msg.sender == owner); 
        _;
    }
    modifier onlyManager {
        require(msg.sender == manager);
        _;
    }
    modifier onlyExchanger {
        require(msg.sender == exchangerAddr);
        _;
    }

    event Deposit(uint amount);
    event TradeStart(uint count);
    event TradeEnd();
    event OrderExpired(address fromToken, address toToken, uint amount);
    event Withdraw(uint amount);


    function Portfolio(address _owner, address _manager, address _exchanger, uint64 _endTime,
                       uint _tradesMaxCount) public {
        require(_owner != 0x0);

        owner = _owner;
        manager = _manager;
        exchangerAddr = _exchanger;
        startTime = now;
        endTime = _endTime;
        tradesMaxCount = _tradesMaxCount;
        exchanger = Exchanger(_exchanger);
    }


    function deposit() public onlyOwner payable {
        assert(!wasDeposit);

        depositAmount = msg.value;
        isRunning = true;
        wasDeposit = true;
        emit Deposit(msg.value);
    }


    mapping (address => uint) tokensAmountSum;

    function trade(address[] _fromTokens, address[] _toTokens, uint[] _amounts) public onlyManager inRunning {
        require(_fromTokens.length == _toTokens.length && _toTokens.length == _amounts.length && _fromTokens.length > 0);
        assert(tradesWasCount < tradesMaxCount && !onTraiding);
        assert(now < endTime);

        onTraiding = true;
        ordersCountLeft = _fromTokens.length;
        tradesWasCount++;

        address[] memory tokensList = new address[](16);
        uint sz = 0;
        for (uint i = 0; i < _fromTokens.length; i++) {
            require(_fromTokens[i] != _toTokens[i] && _amounts[i] > 0);

            if (!usedToken[_toTokens[i]]) {
                portfolioTokens.push(_toTokens[i]);
            }

            if (tokensAmountSum[_fromTokens[i]] == 0) {
                tokensList[sz++] = _fromTokens[i];
            }
            assert(tokensAmountSum[_fromTokens[i]] + _amounts[i] > _amounts[i]);
            tokensAmountSum[_fromTokens[i]] += _amounts[i];
        }

        for (i = 0; i < sz; i++) {
            if (tokensList[i] == 0) {
                assert(address(this).balance >= tokensAmountSum[tokensList[i]]);
            } else {
                AbstractToken token = AbstractToken(tokensList[i]);
                assert(token.balanceOf(address(this)) >= tokensAmountSum[tokensList[i]]);
                assert(token.approve(exchangerAddr, tokensAmountSum[tokensList[i]]));
            }
            tokensAmountSum[_fromTokens[i]] = 0;
        }

        exchanger.portfolioTrade(_fromTokens, _toTokens, _amounts);
        emit TradeStart(tradesWasCount);
    }

    function transferEth(uint _amount) public onlyExchanger {
        assert(exchangerAddr.send(_amount));
    }

    function transferCompleted() public onlyExchanger {
        ordersCountLeft--;
        if (ordersCountLeft == 0) {
            onTraiding = false;
            emit TradeEnd();
        }
    }

    function transferTimeExpired(address fromToken, address toToken, uint amount) public onlyExchanger {
        emit OrderExpired(fromToken, toToken, amount);
        ordersCountLeft--;
        if (ordersCountLeft == 0) {
            onTraiding = false;
            emit TradeEnd();
        }
    }

    function endPortfolio() public onlyOwner {
        assert(now >= endTime && !onTraiding);

        onTraiding = true;
        isRunning = false;

        transferAllToEth();
    }

    function CriticalEndPortfolio() public onlyOwner {
        assert(now < endTime && !onTraiding);

        wasCriticalEnd = true;
        onTraiding = true;
        isRunning = false;

        transferAllToEth();
    }

    function transferAllToEth() private {
        address[] memory tokensToTransfer = new address[](portfolioTokens.length);
        uint[] memory tokenBalances = new uint[](portfolioTokens.length);
        uint sz = 0;

        for (uint i = 0; i < portfolioTokens.length; i++) {
            AbstractToken token = AbstractToken(portfolioTokens[i]);
            uint balance = token.balanceOf(address(this));
            if (balance > 0) {
                tokensToTransfer[sz] = portfolioTokens[i];
                tokenBalances[sz] = balance;
                sz++;
            }
        }

        address[] memory fromTokens = new address[](sz);
        address[] memory toTokens = new address[](sz);
        uint[] memory amounts = new uint[](sz);
        for (i = 0; i < sz; i++) {
            fromTokens[i] = tokensToTransfer[i];
            toTokens[i] = 0;
            amounts[i] = tokenBalances[i];
        }

        exchanger.portfolioTrade(fromTokens, toTokens, amounts);
    }

    function withdraw() public onlyOwner {
        assert(!onTraiding && !wasWithdraw);

        withdrawAmount = address(this).balance;
        uint managerFee = 0;
        uint wealthManFee = 0;

        // any formulas
        if (!wasCriticalEnd) {
            if (withdrawAmount > depositAmount) {
                managerFee = (withdrawAmount - depositAmount) * 8 / 100;
            }
        } else {
            managerFee = withdrawAmount * 4 / 100;
        }
        wealthManFee = withdrawAmount * 2 / 100;

        assert(manager.send(managerFee));
        assert(exchangerAddr.send(wealthManFee));
        assert(owner.send(address(this).balance));

        wasWithdraw = true;
        emit Withdraw(withdrawAmount);
    }
}