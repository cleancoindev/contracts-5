const GameManager = artifacts.require('GameManager')
const KFProxy = artifacts.require('KFProxy')
const GMGetterDB = artifacts.require('GMGetterDB')
const Register = artifacts.require('Register')
const EndowmentFund = artifacts.require('EndowmentFund')
const KittieFightToken = artifacts.require('KittieFightToken');

const KTY_ADDRESS = '0x8d05f69bd9e804eb467c7e1f2902ecd5e41a72da';
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

function setMessage(contract, funcName, argArray) {
    return web3.eth.abi.encodeFunctionCall(
      contract.abi.find((f) => { return f.name == funcName; }),
      argArray
    );
}

function randomValue() {
  return Math.floor(Math.random() * 1000) + 1; // (1-num) value
}

function randomBet(maxBet) {
    return (Math.random() * maxBet) + 0.1;
}

function timeout(s) {
// console.log(`~~~ Timeout for ${s} seconds`);
return new Promise(resolve => setTimeout(resolve, s * 1000));
}


//truffle exec scripts/BOTS/play.js <gameId> <accountIndex> <playerToSupport> <maxBetAmount> <timeBetweenBets> --network rinkeby

module.exports = async (callback) => {
	try{
        proxy = await KFProxy.deployed()
        gameManager = await GameManager.deployed()
        getterDB = await GMGetterDB.deployed();
        register = await Register.deployed()
        kittieFightToken = await KittieFightToken.at(KTY_ADDRESS);
        endowmentFund = await EndowmentFund.deployed();

        let gameId = process.argv[4];
        let accountIndex = process.argv[5];
        let playerToSupport = process.argv[6];
        let maxBetAmount = process.argv[7];
        let timeBetweenBets = process.argv[8];

        let allAccounts = await web3.eth.getAccounts();

        //Account to play with
        let account = allAccounts[accountIndex];

        // APPROVE KTY TO ENDOWMENT
        let KTYBalance = await kittieFightToken.balanceOf(account)
        await kittieFightToken.approve(endowmentFund.address, web3.utils.toWei(KTYBalance.toString()) , 
            { from: account })
        approvedTokens = await kittieFightToken.allowance(account, endowmentFund.address);
        if(approvedTokens) console.log(`\n${account} approved ${KTYBalance.toString()} KTY to endowment`);

        //REGISTER IF NOT ALREADY
        let isRegistered = await register.isRegistered(account);

        if(!isRegistered){
            await proxy.execute('Register', setMessage(register, 'register', 
                []), {from: account})
            
            let isRegistered = await register.isRegistered(account);

            if (isRegistered) console.log(`\nRegistered account ${account}!`);
            else console.log(`\nError registering account`);
        }

        //PARTICIPATE IF NOT ALREADY 
        let info = await getterDB.getSupporterInfo(gameId, account);

        let supported;

        //If no supported player yet
        if(info.supportedPlayer === ZERO_ADDRESS){
            let {playerBlack, playerRed} = await getterDB.getGamePlayers(gameId);

            if (playerToSupport === "RED") supported = playerRed;
            else if (playerToSupport === "BLACK") supported = playerBlack;
            else callback(new Error('Please choose a valid corner name'))

            //Participate choose random player
            console.log(`Supporting Player ${playerToSupport}...`)
            await proxy.execute('GameManager', setMessage(gameManager, 'participate',
                [gameId, supported]), { from: account }).should.be.fulfilled;
        }

        // BETTING
        //We assume the game has started
        while(true){

            let amountBet = randomBet(maxBetAmount);

            console.log(`Betting ${amountBet} ETH...`)
            await proxy.execute('GameManager', setMessage(gameManager, 'bet',
                [gameId, randomValue()]), { from: account, value: web3.utils.toWei(String(amountBet)) })            

            //IF lower than 50 KTY
            approvedTokens = await kittieFightToken.allowance(account, endowmentFund.address);
            if(approvedTokens < web3.utils.toWei('50')) callback(new Error('Low on approved KTY'))

            //If lower than 1 ETH
            balance = await web3.eth.getBalance(account);
            if(balance < web3.utils.toWei('1')) callback(new Error('Low on ETH'))

            await timeout(timeBetweenBets);
        }

		
	}
	catch(e){callback(e)}

}