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
import "../databases/GMSetterDB.sol";
import "../databases/GMGetterDB.sol";
import "../databases/EndowmentDB.sol";
import "../../GameVarAndFee.sol";
import "../endowment/EndowmentFund.sol";
import "./Forfeiter.sol";
import "./Scheduler.sol";
import "../algorithm/Betting.sol";
import "../algorithm/HitsResolveAlgo.sol";
import "../algorithm/RarityCalculator.sol";
import "../databases/ProfileDB.sol";
import "../../libs/SafeMath.sol";
import '../kittieHELL/KittieHELL.sol';
import '../../authority/Guard.sol';
import "../../interfaces/IKittyCore.sol";

contract GameManager is Proxied, Guard {
    using SafeMath for uint256;

    //Contract Variables
    GMSetterDB public gmSetterDB;
    GMGetterDB public gmGetterDB;
    GameVarAndFee public gameVarAndFee;
    EndowmentFund public endowmentFund;
    EndowmentDB public endowmentDB;
    Forfeiter public forfeiter;
    Scheduler public scheduler;
    Betting public betting;
    HitsResolve public hitsResolve;
    RarityCalculator public rarityCalculator;
    ProfileDB public profileDB;
    KittieHELL public kittieHELL;
    IKittyCore public cryptoKitties;
 
    enum eGameState {WAITING, PRE_GAME, MAIN_GAME, KITTIE_HELL, WITHDREW_EARNINGS, CANCELLED}

    enum HoneypotState {
        created,
        assigned,
        gameScheduled,
        gameStarted,
        forefeited,
        claimed
    }

    struct Player{
        uint random;
        bool hitStart;
        uint defenseLevel;
    }

    // struct Bettor{
    //     bool payedTicketFee;
    // }

    mapping(address => mapping(uint => Player)) public players;
    // mapping(address => mapping(uint => Bettor)) public bettors;

    //TODO: check to add more states (expired, claiming gains)

    modifier onlyKittyOwner(address player, uint kittieId) {
        require(cryptoKitties.ownerOf(kittieId) == player);
        _;
    }

    modifier onlyGamePlayer(uint gameId, address player) {
        // TODO: Is this the check?
        require(profileDB.getCivicId(player) > 0);
        require(gmGetterDB.isPlayer(gameId, player));
        _;
    }

    /**
    * @dev Sets related contracts
    * @dev Can be called only by the owner of this contract
    */
    function initialize() external onlyOwner {

        //TODO: Check what other contracts do we need
        gmSetterDB = GMSetterDB(proxy.getContract(CONTRACT_NAME_GM_SETTER_DB));
        gmGetterDB = GMGetterDB(proxy.getContract(CONTRACT_NAME_GM_GETTER_DB));
        endowmentFund = EndowmentFund(proxy.getContract(CONTRACT_NAME_ENDOWMENT_FUND));
        endowmentDB = EndowmentDB(proxy.getContract(CONTRACT_NAME_ENDOWMENT_DB));
        gameVarAndFee = GameVarAndFee(proxy.getContract(CONTRACT_NAME_GAMEVARANDFEE));
        forfeiter = Forfeiter(proxy.getContract(CONTRACT_NAME_FORFEITER));
        scheduler = Scheduler(proxy.getContract(CONTRACT_NAME_SCHEDULER));
        betting = Betting(proxy.getContract(CONTRACT_NAME_BETTING));
        hitsResolve = HitsResolve(proxy.getContract(CONTRACT_NAME_HITSRESOLVE));
        rarityCalculator = RarityCalculator(proxy.getContract(CONTRACT_NAME_RARITYCALCULATOR));
        profileDB = ProfileDB(proxy.getContract(CONTRACT_NAME_PROFILE_DB));
        // kittieHELL = KittieHELL(proxy.getContract(CONTRACT_NAME_KITTIEHELL));
        cryptoKitties = IKittyCore(proxy.getContract(CONTRACT_NAME_CRYPTOKITTIES));
    }


    /**
     * @dev Checks and prevents unverified accounts, only accounts with available kitties can list
     */
    function listKittie
    (
        uint kittieId
    )
        external
        onlyProxy onlyPlayer
        onlyKittyOwner(getOriginalSender(), kittieId) //currently doesKittieBelong is not used, better
    {
        address player = getOriginalSender();

        //Pay Listing Fee
        // endowmentFund.contributeKTY(player, gameVarAndFee.getListingFee());
        require(endowmentFund.contributeKTY(player, 100));

        // When creating the game, set to true, then we set it to false when game cancels or ends
        require((gmGetterDB.getKittieState(kittieId) == false));

        scheduler.addKittyToList(kittieId, player);
    }

    /**
     * @dev Check to make sure the only superADmin can list, Takes in two kittieID's and accounts as well as the jackpot ether and token number.
     */
    function manualMatchKitties
    (
        address playerRed, address playerBlack,
        uint256 kittyRed, uint256 kittyBlack,
        uint gameStartTime
    )
        external
        onlyProxy onlySuperAdmin
        onlyKittyOwner(playerRed, kittyRed)
        onlyKittyOwner(playerBlack, kittyBlack)
    {
        require(!scheduler.isKittyListedForMatching(kittyRed));
        require(!scheduler.isKittyListedForMatching(kittyBlack));

        generateFight(playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime);
    }

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
        uint256 preStartTime = gameStartTime.sub(gameVarAndFee.getGamePrestart());
        uint256 endTime = gameStartTime.add(gameVarAndFee.getGameDuration());

        uint256 gameId = gmSetterDB.createGame(
            playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime, preStartTime, endTime);

        (uint honeyPotId, uint initialEth) = endowmentFund.generateHoneyPot();
        gmSetterDB.setHoneypotInfo(gameId, honeyPotId, initialEth);

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
        onlyContract(CONTRACT_NAME_SCHEDULER)
    {
        generateFight(playerRed, playerBlack, kittyRed, kittyBlack, gameStartTime);
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
        onlyProxy onlyBettor
        onlyGamePlayer(gameId, playerToSupport)
        returns(bool)
    {
        uint gameState = gmGetterDB.getGameState(gameId);

        address supporter = getOriginalSender();

        require(gameState == uint(eGameState.MAIN_GAME) ||
                gameState == uint(eGameState.PRE_GAME));

        //pay ticket fee
        endowmentFund.contributeKTY(supporter, gameVarAndFee.getTicketFee());
        
        //Add a check to see if ticket fee went through
        gmSetterDB.addBettor(gameId, supporter, playerToSupport);

        if (gameState == 1) forfeiter.checkGameStatus(gameId, gameState);

        (,uint preStartTime,) = gmGetterDB.getGameTimes(gameId);

        //Update state if reached prestart time
        //Include check game state because it can be called from the bet function
        if (gameState == uint(eGameState.WAITING) && preStartTime >= now)
            gmSetterDB.updateGameState(gameId, uint(eGameState.PRE_GAME));
        
        return true;
    }

    /**
     * @dev only both Actual players can call
     */
    function startGame
    (
        uint gameId,
        uint randomNum
    )
        external
        onlyProxy onlyPlayer
        onlyGamePlayer(gameId, getOriginalSender())
        returns(bool)
    {
        uint gameState = gmGetterDB.getGameState(gameId);
        forfeiter.checkGameStatus(gameId, gameState);

        require(gameState == uint(eGameState.PRE_GAME));

        address player = getOriginalSender();
        uint kittieId = gmGetterDB.getKittieInGame(gameId, player);
        // (,,,,,,,,,uint genes) = cryptoKitties.getKitty(kittieId);

        address opponentPlayer = getOpponent(gameId, player);

        //Both Players Hit start
        if (players[opponentPlayer][gameId].hitStart){
            //Call betting to set fight map
            betting.startGame(gameId, players[opponentPlayer][gameId].random, randomNum);
            players[opponentPlayer][gameId].defenseLevel = rarityCalculator.getDefenseLevel(kittieId);
            gmSetterDB.updateGameState(gameId, uint(eGameState.MAIN_GAME));
            (uint honeyPotId,) = gmGetterDB.getHoneypotInfo(gameId);
            endowmentFund.updateHoneyPotState(honeyPotId, uint(HoneypotState.gameStarted));

        }
        //
        else{
            players[player][gameId].hitStart = true;
            players[player][gameId].random = randomNum;
            
            players[player][gameId].defenseLevel = rarityCalculator.getDefenseLevel(kittieId);
        }

        require(kittieHELL.acquireKitty(kittieId, player));
    }

    function getOpponent(uint gameId, address player) internal view returns(address){
        (address playerBlack, address playerRed,,,,) = gmGetterDB.getGame(gameId);
        if(playerBlack == player) return playerRed;
        return playerBlack;
    }

    /**
     * @dev Extend time of underperforming game indefinitely, each time 1 minute before game ends, by checking at everybet
     */
    function extendTime(uint gameId) internal {
        // check if underperforming
        (,,uint gameEndTime) = gmGetterDB.getGameTimes(gameId);

        //each time 1 minute before game ends
        if(gameEndTime - now <= 60) {
            if(!checkPerformance(gameId)) gmSetterDB.updateEndTime(gameId, gameEndTime.add(60));
        }
    }

    /**
     * @dev checks to see if current jackpot is at least 10 times (10x)
     *  the amount of funds originally placed in jackpot
     */
    function checkPerformance(uint gameId) internal view returns(bool) {
        //get initial jackpot, need endowment to send this when creating honeypot
        (,uint initialEth) = gmGetterDB.getHoneypotInfo(gameId);
        uint currentJackpotEth = endowmentDB.getHoneypotTotalETH(gameId);

        if(currentJackpotEth > initialEth.mul(10)) return true;

        return false;
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
        
        require(gameState == uint(eGameState.MAIN_GAME));
        
        address sender = getOriginalSender();
        (, address supportedPlayer, bool payedFee) = gmGetterDB.getBettor(gameId, sender);

        require(payedFee); //Needs to call participate First
        
        //Transfer Funds to endowment
        require(endowmentFund.contributeETH.value(msg.value)(gameId));
        require(endowmentFund.contributeKTY(sender, gameVarAndFee.getBettingFee()));

        //Update bettor's total bet
        gmSetterDB.updateBettor(gameId, sender, msg.value, supportedPlayer);

        // Update Random
        hitsResolve.calculateCurrentRandom(gameId, randomNum);
        
        address opponentPlayer = getOpponent(gameId, supportedPlayer);        
        
        (,,uint256 defenseLevel) = betting.bet(gameId, msg.value, supportedPlayer, opponentPlayer, randomNum);

        // update opposite corner kittie defense level if changed
        if (players[opponentPlayer][gameId].defenseLevel != defenseLevel)
            players[opponentPlayer][gameId].defenseLevel = defenseLevel;

        // update game variables
        calculateBettorStats(gameId, sender, msg.value, supportedPlayer);

        // check underperforming game if one minut
        extendTime(gameId);

        //Check if game has ended
        gameEnd(gameId);
    }

    /**
    * set lastBet, topBettor, secondTopBettor
    * @author vikrammandal
    */
    function calculateBettorStats(
        uint256 _gameId, address _account, uint256 _amountEth, address _supportedPlayer
    ) private {

        ( ,uint256 topBettorEth) = gmGetterDB.getTopBettor(_gameId, _supportedPlayer);

        if (_amountEth > topBettorEth){
            gmSetterDB.setTopBettor(_gameId, _account, _supportedPlayer, _amountEth);
        } else {
            ( ,uint256 secondTopBettorEth) = gmGetterDB.getSecondTopBettor(_gameId, _supportedPlayer);
            if (_amountEth > secondTopBettorEth){
                gmSetterDB.setSecondTopBettor(_gameId, _account, _supportedPlayer, _amountEth);
    }   }   }


    /**
     * @dev game comes to an end at time duration,continously check game time end
     */
    function gameEnd(uint gameId) internal {
        require(gmGetterDB.getGameState(gameId) == uint(eGameState.MAIN_GAME));

        (,,uint endTime) = gmGetterDB.getGameTimes(gameId);

        if ( endTime >= now)
            gmSetterDB.updateGameState(gameId, uint(eGameState.KITTIE_HELL));

        updateKitties(gameId);
    }

    /**
     * @dev Determine winner of game based on  **HitResolver **
     */
    function finalize(uint gameId, uint randomNum) external {
        require(gmGetterDB.getGameState(gameId) == uint(eGameState.KITTIE_HELL));

        (address playerBlack, address playerRed, , , ,) = gmGetterDB.getGame(gameId);

        uint256 playerBlackPoints = hitsResolve.calculateFinalPoints(gameId, playerBlack, randomNum);
        uint256 playerRedPoints = hitsResolve.calculateFinalPoints(gameId, playerRed, randomNum);

        address winner = playerBlackPoints > playerRedPoints ? playerBlack : playerRed;
        gmSetterDB.setWinner(gameId, winner);
    }
    

    /**
     * @dev Cancels the game before the game starts
     */
    function cancelGame(uint gameId, string calldata reason) external onlyContract(CONTRACT_NAME_FORFEITER) {
        require(gmGetterDB.getGameState(gameId) == uint(eGameState.WAITING) ||
                gmGetterDB.getGameState(gameId) == uint(eGameState.PRE_GAME));

        gmSetterDB.updateGameState(gameId, uint(eGameState.CANCELLED));

        updateKitties(gameId);

    }

    function updateKitties(uint gameId) internal {
        // When creating the game, set to true, then we set it to false when game cancels or ends
        ( , , uint256 kittyBlack, uint256 kittyRed, , ) = gmGetterDB.getGame(gameId);
        gmSetterDB.updateKittieState(kittyRed, false);
        gmSetterDB.updateKittieState(kittyBlack, false);
    }

    // /**
    //  * @dev ?
    //  */
    // function claim(uint kittieId) external {

    // }

    // /**
    //  * @dev ?
    //  */
    // function winnersClaim() external {

    // }

    // /**
    //  * @dev ?
    //  */
    // function winnersGroupClaim() external {

    // }
}
