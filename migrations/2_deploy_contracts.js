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
        var nextThen = Token.new(exchanger.address).then(t => {
            tokens.push(t);
            exchanger.allowToken(t.address, transact={from:admin});
        });
        
        for (var i = 0; i < 3; i++) {
            nextThen = nextThen.then( () => Token.new(exchanger.address) ).then( t => {
                tokens.push(t);
                exchanger.allowToken(t.address, transact={from:admin});
            });
        }
        
        return nextThen;
    }

    deployer.deploy(Exchanger, admin)
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

            exchanger.addPortfolio(_portfolio.address, transact={from:admin});
            exchanger.allowToken('0x0', transact={from:admin});

            var configObject = {
                exchangerAddr : exchanger.address,
                portfolioAddr: portfolio.address,
                tokenAddrs: tokens.map(t => t.address),
                // portfolioAbi: portfolio.abi,
                // tokenAbi: Token.abi,
            };
            
            fs.writeFileSync('../afterDeployConfig.js', 'var deploy_data = ' + JSON.stringify(configObject) + ';');
        });
}