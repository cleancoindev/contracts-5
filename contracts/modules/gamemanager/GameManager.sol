/**
 * @title GamesManager
 *
 * @author @wafflemakr @karl @vikrammandal @Xaleee

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
import "../databases/GMSetterDB.sol";
import "../databases/GMGetterDB.sol";
import "../endowment/EndowmentFund.sol";
import "./Forfeiter.sol";
import "../algorithm/Betting.sol";
import "../algorithm/HitsResolveAlgo.sol";
import "../algorithm/RarityCalculator.sol";
import "../databases/ProfileDB.sol";
import "../../libs/SafeMath.sol";
import '../../authority/Guard.sol';
import '../../mocks/MockERC721Token.sol';
import "./GameStore.sol";
import "./GameCreation.sol";
import "../endowment/KtyUniswap.sol";
import "./GameManagerHelper.sol";
import "../databases/AccountingDB.sol";
import "../databases/EndowmentDB.sol";

contract GameManager is Proxied, Guard {
    using SafeMath for uint256;

    //Contract Variables
    GMSetterDB public gmSetterDB;
    GMGetterDB public gmGetterDB;
    EndowmentFund public endowmentFund;
    Forfeiter public forfeiter;
    Betting public betting;
    GameStore public gameStore;
    GameCreation public gameCreation;
    GameManagerHelper public gameManagerHelper;
    AccountingDB public accountingDB;

    enum eGameState {WAITING, PRE_GAME, MAIN_GAME, GAME_OVER, CLAIMING, CANCELLED}

    //EVENTS
    event NewSupporter(uint indexed gameId, address supporter, address indexed playerSupported);
    event PressStart(uint indexed gameId, address player);
    event GameStateChanged(uint indexed gameId, eGameState old_state, eGameState new_state);
    event GameEnded(uint indexed gameId, address indexed winner, address indexed loser, uint pointsBlack, uint pointsRed);
    event GameExtended(uint indexed gameId, uint newEndTime);

    modifier onlyGamePlayer(uint gameId, address player) {
        require(ProfileDB(proxy.getContract(CONTRACT_NAME_PROFILE_DB)).getCivicId(player) > 0);
        require(gmGetterDB.isPlayer(gameId, player));
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
        forfeiter = Forfeiter(proxy.getContract(CONTRACT_NAME_FORFEITER));
        betting = Betting(proxy.getContract(CONTRACT_NAME_BETTING));
        gameStore = GameStore(proxy.getContract(CONTRACT_NAME_GAMESTORE));
        gameCreation = GameCreation(proxy.getContract(CONTRACT_NAME_GAMECREATION));
        gameManagerHelper = GameManagerHelper(proxy.getContract(CONTRACT_NAME_GAMEMANAGER_HELPER));
        accountingDB = AccountingDB(proxy.getContract(CONTRACT_NAME_ACCOUNTING_DB));
    }

    /**
     * @dev Betters pay a ticket fee to participate in betting .
     *      Betters can join before and even a live game.
     */
    function participate
    (
        uint gameId,
        address playerToSupport
    )
        public
        payable
        onlyProxy onlyBettor
        onlyGamePlayer(gameId, playerToSupport)
    {
        require(msg.value > 0);

        uint gameState = gmGetterDB.getGameState(gameId);

        address supporter = getOriginalSender();

        require(supporter != playerToSupport);

        //Before GAME_OVER
        require(gameState <= 2);

        //pay ticket fee
        (uint etherForSwap, uint ticketFeeKTY) = accountingDB.getTicketFee(gameId);
        require(endowmentFund.contributeKTY.value(msg.value)(supporter, etherForSwap, ticketFeeKTY));

        require(gmSetterDB.addBettor(gameId, supporter, playerToSupport));

        // add paid ticket fee to total spent in game
        accountingDB.setTotalSpentInGame(gameId, msg.value, ticketFeeKTY);

        (,uint preStartTime,) = gmGetterDB.getGameTimes(gameId);

        if (gameState == 0 || gameState == 1) forfeiter.checkGameStatus(gameId, gameState);
        //Check again to see if forfeited
        gameState = gmGetterDB.getGameState(gameId);

        //Update state if reached prestart time
        //Include check game state because it can be called from the bet function
        if ((gameState == uint(eGameState.WAITING)) && (preStartTime <= now)){
            gameCreation.deleteCronjob(gameId);
            gmSetterDB.updateGameState(gameId, uint(eGameState.PRE_GAME));
            emit GameStateChanged(gameId, eGameState.WAITING, eGameState.PRE_GAME);
        }

        emit NewSupporter(gameId, supporter, playerToSupport);
    }

    /**
     * @dev only both Actual players can call
     */
    function startGame
    (
        uint gameId,
        uint randomNum,
        uint genes
    )
        external
        onlyProxy onlyPlayer
        onlyGamePlayer(gameId, getOriginalSender())
    {
        uint gameState = gmGetterDB.getGameState(gameId);
        forfeiter.checkGameStatus(gameId, gameState);

        gameState = gmGetterDB.getGameState(gameId);

        if(gameState == uint(eGameState.PRE_GAME)){

            address player = getOriginalSender();
            uint kittieId = gmGetterDB.getKittieInGame(gameId, player);
            
            gameStore.start(gameId, player, randomNum);

            // (,,,,,,,,,uint genes) = MockERC721Token(proxy.getContract(CONTRACT_NAME_CRYPTOKITTIES)).getKitty(kittieId);
            // uint genes = MockERC721Token(proxy.getContract(CONTRACT_NAME_CRYPTOKITTIES)).getKitty(kittieId);
            betting.setOriginalDefenseLevel(gameId, player, RarityCalculator(proxy.getContract(CONTRACT_NAME_RARITYCALCULATOR)).getDefenseLevel(kittieId, genes));

            address opponentPlayer = gameManagerHelper.getOpponent(gameId, player);

            emit PressStart(gameId, player);

            //Both Players Hit start
            if (gameManagerHelper.didHitStart(gameId, opponentPlayer)){
                //Call betting to set fight map
                betting.startGame(gameId, randomNum, gameStore.getRandom(gameId, opponentPlayer));
                
                gameCreation.deleteCronjob(gameId);

                //GameStarts
                gmSetterDB.updateGameState(gameId, uint(eGameState.MAIN_GAME));
                gameManagerHelper.updateHoneyPotState(gameId, 3);
                emit GameStateChanged(gameId, eGameState.PRE_GAME, eGameState.MAIN_GAME);
            }
        }
    }

    /**
     * @dev checks to see if current jackpot is at least 10 times (10x)
     *  the amount of funds originally placed in jackpot
     */
    function checkPerformance(uint gameId) internal {
        (,,uint gameEndTime) = gmGetterDB.getGameTimes(gameId);
        uint timeExtension = gameManagerHelper.getTimeExtension(gameId);

        if(gameManagerHelper.checkPerformanceHelper(gameId, gameEndTime)){
            if(now <= gameEndTime)
                gmSetterDB.updateEndTime(gameId, gameEndTime.add(timeExtension));
            else
                gmSetterDB.updateEndTime(gameId, now.add(timeExtension));
            gameCreation.rescheduleCronJob(gameId);
            emit GameExtended(gameId, gameEndTime.add(timeExtension));
        }
    }

    /**
     * @dev KTY tokens are sent to endowment balance, Eth gets added to ongoing game honeypot
     * @author Felipe
     * @author Karl
     * @author Vikrammandal
     */
    function bet
    (
        uint gameId, uint randomNum
    )
        external payable
        onlyProxy onlyBettor
    {
        require(msg.value > 0);

        uint gameState = gmGetterDB.getGameState(gameId);

        address supportedPlayer;
        bool payedFee;
        
        require(gameState == uint(eGameState.MAIN_GAME));
        
        address sender = getOriginalSender();
        
        if(!(gmGetterDB.isPlayer(gameId, sender))){
            (, supportedPlayer, payedFee,) = gmGetterDB.getSupporterInfo(gameId, sender);
            require(payedFee); //Needs to call participate first if false
        }
        else{
            supportedPlayer = sender;
        }

        (uint etherForSwap, uint bettingFeeKTY) = accountingDB.getBettingFee(gameId);

        //Transfer Funds to endowment
        require(endowmentFund.contributeETH.value(msg.value.sub(etherForSwap))(gameId));
        //pay betting fee
        require(endowmentFund.contributeKTY.value(etherForSwap)(sender, etherForSwap, bettingFeeKTY));
        
        // add betting fee to total spent in game
        accountingDB.setTotalSpentInGame(gameId, etherForSwap, bettingFeeKTY);

        // Update Random
        HitsResolve(proxy.getContract(CONTRACT_NAME_HITSRESOLVE)).calculateCurrentRandom(gameId, randomNum);
        
        address opponentPlayer = gameManagerHelper.getOpponent(gameId, supportedPlayer);
        
        //Send bet to betting algo, to decide attacks
        betting.bet(gameId, sender, msg.value.sub(etherForSwap), supportedPlayer, opponentPlayer, randomNum);

        //Update bettor's total bet
        gmSetterDB.updateBettor(gameId, sender, msg.value.sub(etherForSwap), supportedPlayer);

        if (sender != supportedPlayer) gameStore.updateTopbettors(gameId, sender, supportedPlayer);

        // check underperforming game if one minut
        checkPerformance(gameId);

        //Check if game has ended
        gameEnd(gameId);
    }

    /**
     * @dev game comes to an end at time duration,continously check game time end
     */
    function gameEnd(uint gameId) internal {
        require(gmGetterDB.getGameState(gameId) == uint(eGameState.MAIN_GAME));

        (,,uint endTime) = gmGetterDB.getGameTimes(gameId);

        if ( endTime <= now){
            gameCreation.deleteCronjob(gameId);
            gmSetterDB.updateGameState(gameId, uint(eGameState.GAME_OVER));
            gameManagerHelper.removeKitties(gameId);
            emit GameStateChanged(gameId, eGameState.MAIN_GAME, eGameState.GAME_OVER);
        }
    }

    //Function to call gameEnd from Cronjob
    function gameEndCron(uint gameId) 
        external
        onlyContract(CONTRACT_NAME_GAMECREATION)
    {
        checkPerformance(gameId);
        gameEnd(gameId);
    }

    /**
     * @dev Determine winner of game based on  **HitResolver **
     */
    function finalize(uint gameId, uint randomNum) external onlyProxy {
        require(gmGetterDB.getGameState(gameId) == uint(eGameState.GAME_OVER));

        (address playerBlack, address playerRed,,) = gmGetterDB.getGamePlayers(gameId);

        (address winner, address loser, uint256 pointsBlack, uint256 pointsRed) = gameManagerHelper.calculateWinner(
            gameId, playerBlack, playerRed, randomNum
        );

        //Store Winners in DB
        gmSetterDB.setWinners(gameId, winner, gameStore.getTopBettor(gameId, winner),
            gameStore.getSecondTopBettor(gameId, winner));

        //Lock Honeypot Final Details
        gmSetterDB.storeHoneypotDetails(gameId);

        EndowmentDB(proxy.getContract(CONTRACT_NAME_ENDOWMENT_DB)).addETHtoPool(gameId, loser);

        //Set to claiming
        gameManagerHelper.updateHoneyPotState(gameId, 5);

        // update kittie redemption fee dynamically to a percentage of the final honey pot
        gameStore.updateKittieRedemptionFee(gameId); 

        //Send Finalize reward
        endowmentFund.sendFinalizeRewards(getOriginalSender());

        gmSetterDB.updateGameState(gameId, uint(eGameState.CLAIMING));

        gameManagerHelper.updateKitties(winner, loser, gameId);

        emit GameStateChanged(gameId, eGameState.MAIN_GAME, eGameState.CLAIMING);

        emit GameEnded(gameId, winner, loser, pointsBlack, pointsRed);
    }
}
