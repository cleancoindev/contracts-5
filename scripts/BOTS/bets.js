const GameManager = artifacts.require('GameManager')
const KFProxy = artifacts.require('KFProxy')
const GMGetterDB = artifacts.require('GMGetterDB')

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


//truffle exec scripts/BOTS/bets.js <gameId> <accountIndex> <timesToBet> <maxBetAmount> --network rinkeby

module.exports = async (callback) => {
	try{
        proxy = await KFProxy.deployed()
        gameManager = await GameManager.deployed()
        getterDB = await GMGetterDB.deployed();

        let gameId = process.argv[4];
        let accountIndex = process.argv[5];
        let timesToBet = process.argv[6];
        let maxBetAmount = process.argv[7];

        let allAccounts = await web3.eth.getAccounts();

        let account = allAccounts[accountIndex];
        
        let j=0;

        for(i = 0 ; i < timesToBet; i++){

            let info = await getterDB.getSupporterInfo(gameId, account);
            let players = await getterDB.getGamePlayers(gameId);
    
            let supporting;
    
            if(info.supportedPlayer === players.playerBlack) supporting = 'BLACK';
            else supporting = 'RED';

            let amountBet = randomBet(maxBetAmount);

            console.log(`Betting ${amountBet} ETH...`)
            proxy.execute('GameManager', setMessage(gameManager, 'bet',
                [gameId, randomValue()]), { from: account, value: web3.utils.toWei(String(amountBet)) })            
            console.log(`Player ${account} placed a bet in game ${gameId} for ${supporting}!\n`)
                      

        }

		callback()
	}
	catch(e){callback(e)}

}