/**
 * @title GamesManager
 *
 * @author @wafflemakr @karl @vikrammandal

 *
 */
//modifier class (DSAuth )
//Event class ( DSNote )
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.5.5;

import '../proxy/Proxied.sol';
import "../datetime/TimeFrame.sol";
import "../databases/EndowmentDB.sol";
import "../databases/GMSetterDB.sol";
import "../databases/GMGetterDB.sol";
import "../../GameVarAndFee.sol";
import "../endowment/EndowmentFund.sol";
import "./Scheduler.sol";
import "../../libs/SafeMath.sol";
import '../../authority/Guard.sol';
import "../../interfaces/IKittyCore.sol";
import "./GameStore.sol";
import "./GameManager.sol";
import "../../CronJob.sol";
import "./Forfeiter.sol";
import '../kittieHELL/KittieHell.sol';
import "../endowment/HoneypotAllocationAlgo.sol";
import '../endowment/KtyUniswap.sol';
import "../databases/GenericDB.sol";
import "../../withdrawPool/WithdrawPool.sol";
import "../databases/AccountingDB.sol";
import "./GameManagerHelper.sol";

contract GameCreation is Proxied, Guard {
    using SafeMath for uint256;

    //Contract Variables
    GMSetterDB public gmSetterDB;
    GMGetterDB public gmGetterDB;
    GameVarAndFee public gameVarAndFee;
    EndowmentFund public endowmentFund;
    Scheduler public scheduler;
    IKittyCore public cryptoKitties;
    GameStore public gameStore;
    CronJob public cronJob;
    KittieHell public kittieHELL;
    GenericDB public genericDB;
    WithdrawPool public withdrawPool;
    AccountingDB public accountingDB;
    GameManagerHelper public gameManagerHelper;


    //EVENTS
    event NewGame(uint indexed gameId, address playerBlack, uint kittieBlack, address playerRed, uint kittieRed, uint gameStartTime);
    event NewListing(uint indexed kittieId, address indexed owner, uint timeListed);
    // event Scheduled(uint indexed jobId, uint jobTime, uint indexed gameId, string job);

    //mapping(uint256 => uint256) public cronJobsForGames; //using gmGetterDB.getCronJobForGame()/gmSetterDB.setCronJobForGame() instead

    modifier onlyKittyOwner(address player, uint kittieId) {
        require(cryptoKitties.ownerOf(kittieId) == player, "Not the owner of this kittie");
        _;
    }

    /**
    * @dev Sets related contracts
    * @dev Can be called only by the owner of this contract
    */
    function initialize() external onlyOwner {
        gmSetterDB = GMSetterDB(proxy.getContract(CONTRACT_NAME_GM_SETTER_DB));
        gmGetterDB = GMGetterDB(proxy.getContract(CONTRACT_NAME_GM_GETTER_DB));
        endowmentFund = EndowmentFund(proxy.getContract(CONTRACT_NAME_ENDOWMENT_FUND));
        gameVarAndFee = GameVarAndFee(proxy.getContract(CONTRACT_NAME_GAMEVARANDFEE));
        scheduler = Scheduler(proxy.getContract(CONTRACT_NAME_SCHEDULER));
        cryptoKitties = IKittyCore(proxy.getContract(CONTRACT_NAME_CRYPTOKITTIES));
        gameStore = GameStore(proxy.getContract(CONTRACT_NAME_GAMESTORE));
        cronJob = CronJob(proxy.getContract(CONTRACT_NAME_CRONJOB));
        kittieHELL = KittieHell(proxy.getContract(CONTRACT_NAME_KITTIEHELL));
        genericDB = GenericDB(proxy.getContract(CONTRACT_NAME_GENERIC_DB));
        withdrawPool = WithdrawPool(proxy.getContract(CONTRACT_NAME_WITHDRAW_POOL));
        accountingDB = AccountingDB(proxy.getContract(CONTRACT_NAME_ACCOUNTING_DB));
        gameManagerHelper = GameManagerHelper(proxy.getContract(CONTRACT_NAME_GAMEMANAGER_HELPER));
    }

    // /**
    //  * @dev Checks and prevents unverified accounts, only accounts with available kitties can list
    //  */
    // function listKittie
    // (
    //     uint kittieId
    // )
    //     external
    //     payable
    //     onlyProxy onlyPlayer
    //     onlyKittyOwner(getOriginalSender(), kittieId) //currently doesKittieBelong is not used, better
    // {
    //     address player = getOriginalSender();

    //     //Pay Listing Fee
    //     // get listing fee in Dai
    //     (uint etherForListingFeeSwap, uint listingFeeKTY) = gameVarAndFee.getListingFee();

    //     require(endowmentFund.contributeKTY.value(msg.value)(player, etherForListingFeeSwap, listingFeeKTY), "Need to pay listing fee");
    //     //endowmentFund.contributeKTY(player, gameVarAndFee.getListingFee());

    //     require((gmGetterDB.getGameOfKittie(kittieId) == 0), "Kittie is already playing a game");

    //     scheduler.addKittyToList(kittieId, player);

    //     accountingDB.recordKittieListingFee(kittieId, msg.value, listingFeeKTY);

    //     emit NewListing(kittieId, player, now);
    // }

    // /**
    //  * @dev Check to make sure the only superADmin can list, Takes in two kittieID's and accounts as well as the jackpot ether and token number.
    //  */
    // function manualMatchKitties
    // (
    //     address playerRed, address playerBlack,
    //     uint256 kittyRed, uint256 kittyBlack,
    //     uint gameStartTime
    // )
    //     external
    //     onlyProxy onlySuperAdmin
    //     onlyKittyOwner(playerRed, kittyRed)
    //     onlyKittyOwner(playerBlack, kittyBlack)
    // {
    //     require(genericDB.getUintStorage(CONTRACT_NAME_TIMEFRAME, keccak256(abi.encodePacked(
    //         genericDB.getUintStorage(CONTRACT_NAME_TIMEFRAME, keccak256(abi.encode("activeEpoch"))),"endTimeForGames"))) > gameStartTime,
    //         "Wrong start time");

    //     require(!genericDB.getBoolStorage(CONTRACT_NAME_SCHEDULER, keccak256(abi.encode("schedulerMode"))), "No manual match mode");

    //     require(!scheduler.isKittyListedForMatching(kittyRed), "fighter already listed");
    //     require(!scheduler.isKittyListedForMatching(kittyBlack), "fighter already listed");

    //     require(kittieHELL.acquireKitty(kittyRed, playerRed));
    //     require(kittieHELL.acquireKitty(kittyBlack, playerBlack));

    //     emit NewListing(kittyRed, playerRed, now);
    //     emit NewListing(kittyBlack, playerBlack, now);

    //     generateFight(playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime);
    // }

    /**
     * @dev Creates game and generates gameId
     * @return gameId
     */
    function generateFight
    (
        address playerRed, address playerBlack,
        uint256 kittyRed, uint256 kittyBlack,
        uint gameStartTime
    )
        internal
    {
        uint256 gameId = gmSetterDB.createGame(
            playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime);
        
        gameStore.lockVars(gameId);

        (uint initialKTY, uint initialEth) = HoneypotAllocationAlgo(proxy.getContract(CONTRACT_NAME_HONEYPOT_ALLOCATION_ALGO)).generateHoneyPot(gameId);
        gmSetterDB.setHoneypotInfo(gameId, initialKTY, initialEth);

        uint poolId = TimeFrame(proxy.getContract(CONTRACT_NAME_TIMEFRAME)).getActiveEpochID();

        EndowmentDB(proxy.getContract(CONTRACT_NAME_ENDOWMENT_DB)).setPoolIDinGame(gameId, poolId);

        gameManagerHelper.updateKittiesGame(kittyBlack, kittyRed, gameId);

        // update ticket fee dynamically as a percentage of initial honeypot size
        gameStore.updateTicketFee(gameId);

        // update betting fee dynamically as a percentage of initial honeypot size
        gameStore.updateBettingFee(gameId);

        accountingDB.setListingFeeInGame(gameId, kittyRed, kittyBlack);

        emit NewGame(gameId, playerBlack, kittyBlack, playerRed, kittyRed, gameStartTime);
    }

    /**
     * @dev External function for Scheduler to call
     * @return gameId
     */
    function createFight
    (
        address playerRed, address playerBlack,
        uint256 kittyRed, uint256 kittyBlack,
        uint gameStartTime
    )
        external
        only2Contracts(CONTRACT_NAME_SCHEDULER, CONTRACT_NAME_LIST_KITTIES)
    {
        generateFight(playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime);
    }

    // function updateKitties(address winner, address loser, uint256 gameId)
    // external
    // onlyContract(CONTRACT_NAME_GAMEMANAGER)
    // {
    //     //Release winner's Kittie
    //     kittieHELL.releaseKittyGameManager(gmGetterDB.getKittieInGame(gameId, winner));

    //     //Kill losers's Kittie
    //     kittieHELL.killKitty(gmGetterDB.getKittieInGame(gameId, loser), gameId);

    //     if(genericDB.getBoolStorage(CONTRACT_NAME_SCHEDULER, keccak256(abi.encode("schedulerMode"))))
    //         scheduler.startGame();
    // }

    // ==== CRONJOBS FUNCTIONS

    function scheduleJobs(uint256 gameId, uint256 state)
    external
    onlyContract(CONTRACT_NAME_GM_SETTER_DB)
    {
        if(state == 0){
            (,uint preStartTime,) = gmGetterDB.getGameTimes(gameId);
            uint scheduledJob = cronJob.addCronJob(CONTRACT_NAME_GAMECREATION, preStartTime, abi.encodeWithSignature("updateGameStateCron(uint256)", gameId));
            // emit Scheduled(scheduledJob, preStartTime, gameId, "Change state to 1");
            gmSetterDB.setCronJobForGame(gameId, scheduledJob);
        }

        if(state == 1){
            //If it is PRE_GAME STATE, again, when the job is scheduled (startTime), it should start, as both players press start
            //So if state did not change we must cancelGame
            //If they both press start this job is cancelled (In start function of GameManager)
            (uint startTime,,) = gmGetterDB.getGameTimes(gameId);
            uint scheduledJob = cronJob.addCronJob(CONTRACT_NAME_GAMECREATION, startTime, abi.encodeWithSignature("callForfeiterCron(uint256)", gameId));
            // emit Scheduled(scheduledJob, startTime, gameId, "Change state to 2");
            gmSetterDB.setCronJobForGame(gameId, scheduledJob);
        }
        if(state == 2){
            //If it is MAIN_GAME we endgame immediately
            //We reschedule this Job if game extends (In checkPerformance of GameManager)
            (,,uint endTime) = gmGetterDB.getGameTimes(gameId);
            uint scheduledJob = cronJob.addCronJob(CONTRACT_NAME_GAMECREATION, endTime, abi.encodeWithSignature("callGameEndCron(uint256)", gameId));
            // emit Scheduled(scheduledJob, endTime, gameId, "Change state to 3");
            gmSetterDB.setCronJobForGame(gameId, scheduledJob);
        }
    }

    
    function updateGameStateCron(uint256 gameId)
        external
        onlyContract(CONTRACT_NAME_CRONJOB)
    {
        uint state = gmGetterDB.getGameState(gameId);
        //Check forfeiter before updating game state
        Forfeiter(proxy.getContract(CONTRACT_NAME_FORFEITER)).checkGameStatusCron(gameId, state);
        state = gmGetterDB.getGameState(gameId);
        if (state == 0) gmSetterDB.updateGameStateCron(gameId);
    }

    function callForfeiterCron(uint gameId)
        external
        onlyContract(CONTRACT_NAME_CRONJOB)
    {
        Forfeiter(proxy.getContract(CONTRACT_NAME_FORFEITER)).forfeitCron(gameId, "Did not hit start");
    }

    function callGameEndCron(uint gameId)
        external
        onlyContract(CONTRACT_NAME_CRONJOB)
    {
        uint state = gmGetterDB.getGameState(gameId);
        if (state == 2) GameManager(proxy.getContract(CONTRACT_NAME_GAMEMANAGER)).gameEndCron(gameId);
    }

    function rescheduleCronJob(uint gameId)
        external
        onlyContract(CONTRACT_NAME_GAMEMANAGER)
    {
        //Reschedule CronJob when more time added

        uint256 jobId = gmGetterDB.getCronJobForGame(gameId);
        (,,uint endTime) = gmGetterDB.getGameTimes(gameId);
        uint newJobId = cronJob.rescheduleCronJob(CONTRACT_NAME_GAMECREATION, jobId, endTime);
        uint activeEpoch = genericDB.getUintStorage(CONTRACT_NAME_TIMEFRAME, keccak256(abi.encode("activeEpoch")));
        if(endTime > genericDB.getUintStorage(CONTRACT_NAME_TIMEFRAME, keccak256(abi.encodePacked(activeEpoch,"restDayStart")))) {
            withdrawPool.addGamingDelay(endTime);
        }
        gmSetterDB.setCronJobForGame(gameId, newJobId);
    }

    function deleteCronjob(uint gameId)
        external
        only2Contracts(CONTRACT_NAME_GAMEMANAGER, CONTRACT_NAME_GAMEMANAGER_HELPER)
    {
        uint256 jobId = gmGetterDB.getCronJobForGame(gameId);
        cronJob.deleteCronJob(CONTRACT_NAME_GAMECREATION, jobId);
    }
}
