
const GameVarAndFee = artifacts.require('GameVarAndFee')
const RoleDB = artifacts.require('RoleDB')
const Escrow = artifacts.require('Escrow')
const KFProxy = artifacts.require('KFProxy')
const DateTime = artifacts.require('DateTime')
const GameManager = artifacts.require('GameManager')
const Scheduler = artifacts.require('Scheduler')
const GameCreation = artifacts.require('GameCreation')

function formatDate(timestamp) {
  let date = new Date(null);
  date.setSeconds(timestamp);
  return date.toTimeString().replace(/.*(\d{2}:\d{2}:\d{2}).*/, "$1");
}

// truffle exec scripts/check.js --network rinkeby

module.exports = async (callback) => {
	try{
		gameManager = await GameManager.deployed()
		gameVarAndFee = await GameVarAndFee.deployed()
		roleDB = await RoleDB.deployed();
		escrow = await Escrow.deployed();
		proxy = await KFProxy.deployed()
		dateTime = await DateTime.deployed()
		scheduler = await Scheduler.deployed()
		gameCreation = await GameCreation.deployed();

		accounts = await web3.eth.getAccounts();

		let numMatches = await gameVarAndFee.getRequiredNumberMatches();
		let minSupporters = await gameVarAndFee.getMinimumContributors();
		let balanceKTY = await escrow.getBalanceKTY();
		let balanceETH = await escrow.getBalanceETH();
		let isSuperAdmin = await roleDB.hasRole("super_admin", accounts[0])
		let isAdmin = await roleDB.hasRole("admin", accounts[0])
		let addressOfGameManager = await proxy.getContract("GameManager");
		let blockchainTime = await dateTime.getBlockTimeStamp();
		let listedKitties = await scheduler.getListedKitties()

		console.log(' Blockchain Time:', blockchainTime.toString(), formatDate(blockchainTime));
		console.log(' Game Manager Address in json file:', gameManager.address);
		console.log(' Game Manager Address stored in Proxy:', addressOfGameManager);
		console.log(' Required Number of Matches:', numMatches.toString());
		console.log(' Min amount of supporters:', minSupporters.toString());
		console.log(' Endowment/Escrow balance :', String(web3.utils.fromWei(balanceETH)), "ETH");
		console.log(' Endowment/Escrow balance :', String(web3.utils.fromWei(balanceKTY)), "KTY");
		console.log('', accounts[0], isSuperAdmin ? "IS":"IS NOT", "super admin");
		console.log('', accounts[0], isAdmin ? "IS":"IS NOT", "admin");

		console.log(' Kitties Listed and waiting to be matched:');
		listedKitties = listedKitties.map(k => k.toString());
		let listEvents = await gameCreation.getPastEvents('NewListing');
		listEvents.map(e => {
			console.log(`   Kittie ${e.returnValues.kittieId}`);
			console.log(`   Listed at ${formatDate(e.returnValues.timeListed)}`)
		})

		// NewListing event
		

		callback()
	}
	catch(e){callback(e)}

}