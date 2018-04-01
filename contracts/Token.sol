pragma solidity ^0.4.15;

import "./StandardToken.sol";

contract Token is StandardToken {
    function Token(address _user) public {
        balances[_user] = 100500 * 1 ether;
    }

    function addTo(address _user, uint _value) public {
        assert(balances[_user] + _value > balances[_user]);

        balances[_user] += _value;
    }
}