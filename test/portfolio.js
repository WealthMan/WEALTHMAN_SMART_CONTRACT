var fs = require('fs');
eval(fs.readFileSync('../deploy-config.js')+'');
eval(fs.readFileSync('../afterDeployConfig.js')+'');

const Token = artifacts.require("./Token.sol");
const Exchanger = artifacts.require("./Exchanger.sol");
const Portfolio = artifacts.require("./Portfolio.sol");

let exchanger;
let portfolio;
let token1;
let token2;


contract('Portfolio and Exchanger', async (accounts) => {
	it("should run portfolio", async() => {
		portfolio = await Portfolio.deployed();
		await portfolio.deposit(transact={from: owner, value: '1000'});
		let isRunning = await portfolio.isRunning();
		assert.equal(isRunning, true, "Portfolio is not running after deposit");
	});


	it("should transfer Eth to token", async() => {
		await portfolio.trade(['0x0'], [deploy_data.tokenAddrs[0]], [1000], transact={from: manager});

		exchanger = await Exchanger.deployed();
		await exchanger.completeOrders([0], [2000000000000000000], transact={from: admin});

		token1 = await Token.at(deploy_data.tokenAddrs[0]);

		let portfolioTokenBalance = await token1.balanceOf(portfolio.address);
		assert.equal(portfolioTokenBalance, '2000', "Portfolio Token1 Balance is incorrect");

		let exchangerEthBalance = await web3.eth.getBalance(exchanger.address);
		assert.equal(exchangerEthBalance, '1000', "Exchanger Eth Balance is incorrect");
	});


	it("should transfer token to token", async() => {
		await portfolio.trade([deploy_data.tokenAddrs[0]], [deploy_data.tokenAddrs[1]], [1500], transact={from: manager});

		await exchanger.completeOrders([1], [100000000000000000], transact={from: admin});

		let portfolioToken1Balance = await token1.balanceOf(portfolio.address);
		assert.equal(portfolioToken1Balance, '500', "Portfolio Token1 Balance is incorrect");

		token2 = await Token.at(deploy_data.tokenAddrs[1]);
		let portfolioToken2Balance = await token2.balanceOf(portfolio.address);
		assert.equal(portfolioToken2Balance, '150', "Portfolio Token2 Balance is incorrect");
	});


	it("should transfer token to eth", async() => {
		await portfolio.trade([deploy_data.tokenAddrs[0]], ['0x0'], [500], transact={from: manager});

		await exchanger.cleanOrders(transact={from: admin});
		await exchanger.completeOrders([0], [500000000000000000], transact={from: admin});

		let portfolioToken1Balance = await token1.balanceOf(portfolio.address);
		assert.equal(portfolioToken1Balance, '0', "Portfolio Token1 Balance is incorrect");


		let portfolioEthBalance = await web3.eth.getBalance(portfolio.address);
		assert.equal(portfolioEthBalance, '250', "Portfolio Eth Balance is incorrect");
	})
});