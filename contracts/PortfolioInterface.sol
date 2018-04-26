pragma solidity ^0.4.21;

contract PortfolioInterface {
    function transferEth(uint _amount) public;
    function transferCompleted(address fromToken, address toToken, uint amount, uint rate) public;
    function transferTimeExpired(address fromToken, address toToken, uint amount) public;
    function transferCanceled(address fromToken, address toToken, uint amount) public;
}