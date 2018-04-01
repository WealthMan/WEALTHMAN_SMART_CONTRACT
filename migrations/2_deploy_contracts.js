var fs = require('fs');
eval(fs.readFileSync('../deploy-config.js')+'');

var Token = artifacts.require("./Token.sol");
var Exchanger = artifacts.require("./Exchanger.sol");
var Portfolio = artifacts.require("./Portfolio.sol");

module.exports = function (deployer) {
    var exchanger;
    var portfolio;
    var tokens = [];

    function deployTokens() {
        var nextThen = Token.new(admin).then(t => { tokens.push(t) });
        
        for (var i = 0; i < 3; i++) {
            nextThen = nextThen.then( () => Token.new(admin) ).then( t => { tokens.push(t) } );
        }
        
        return nextThen;
    }

    deployer.deploy(Exchanger, admin, oracle)
        .then( () => Exchanger.deployed() )
        .then(function (_exchanger) {
            exchanger = _exchanger;
            // test Portfolio
            return deployer.deploy(Portfolio, owner, manager, exchanger.address, endTime, tradesMaxCount);
        })
        .then( deployTokens )
        .then( () => Portfolio.deployed() )
        .then( (_portfolio) => {
            portfolio = _portfolio;
            
            var configObject = {
                exchangerAddr : exchanger.address,
                portfolioAddr: portfolio.address,
                tokenAddrs: tokens.map(t => t.address),
                portfolioAbi: portfolio.abi,
                tokenAbi: Token.abi,
            };
            
            fs.writeFileSync('./afterDeployConfig.js', 'const CONFIG = ' + JSON.stringify(configObject) + ';');
        });
}