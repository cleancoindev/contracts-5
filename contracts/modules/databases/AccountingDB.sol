pragma solidity ^0.5.5;

import "../proxy/Proxied.sol";
import "./GenericDB.sol";
import "../../libs/SafeMath.sol";
import '../../GameVarAndFee.sol';
import './GMGetterDB.sol';
import "./EndowmentDB.sol";

contract AccountingDB is Proxied {
    using SafeMath for uint256;

    GenericDB public genericDB;
    GameVarAndFee public gameVarAndFee;
    GMGetterDB public gmGetterDB;
    EndowmentDB public endowmentDB;

    bytes32 internal constant TABLE_KEY_HONEYPOT = keccak256(abi.encodePacked("HoneypotTable"));

    constructor(GenericDB _genericDB) public {
        setGenericDB(_genericDB);
    }

    function setGenericDB(GenericDB _genericDB) public onlyOwner {
        genericDB = _genericDB;
    }

    /**
    * @dev Sets related contracts
    * @dev Can be called only by the owner of this contract
    */
    function initialize() external onlyOwner {
        gameVarAndFee = GameVarAndFee(proxy.getContract(CONTRACT_NAME_GAMEVARANDFEE));
        gmGetterDB = GMGetterDB(proxy.getContract(CONTRACT_NAME_GM_GETTER_DB));
        endowmentDB = EndowmentDB(proxy.getContract(CONTRACT_NAME_ENDOWMENT_DB));
    }

    modifier onlyExistingHoneypot(uint gameId) {
        require(genericDB.doesNodeExist(CONTRACT_NAME_ENDOWMENT_DB, TABLE_KEY_HONEYPOT, gameId), "Honeypot Not exists");
        _;
    }

    /**
    * @dev record actual kittie listing fee in ether and in uniswap swapped kty for each kittie listed
    */
    function recordKittieListingFee(uint256 kittieId, uint256 listingFeeEther, uint256 listingFeeKty)
        external
        onlyContract(CONTRACT_NAME_GAMECREATION)
    {
        genericDB.setUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(kittieId, "kittieListingFeeEther")),
            listingFeeEther);

        genericDB.setUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(kittieId, "kittieListingFeeKty")),
            listingFeeKty);
    }

    /**
     * @dev set total spent "ether" and total uniswap auto-swapped KTY for each game
    */
    function setTotalSpentInGame(uint256 gameId, uint256 etherAmount, uint256 ktyAmount)
        external
        only3Contracts(CONTRACT_NAME_GAMECREATION, CONTRACT_NAME_GAMEMANAGER, CONTRACT_NAME_KITTIEHELL)
    {
        _setTotalSpentInGame(gameId, etherAmount, ktyAmount);
    }

    function setListingFeeInGame(uint256 _gameId, uint256 _kittyRed, uint256 _kittyBlack)
        external
        onlyContract(CONTRACT_NAME_GAMECREATION)
    {
        (uint256 _listingFeeEthRed, uint256 _listingFeeKtyRed) = getKittieListingFee(_kittyRed);
        _setTotalSpentInGame(_gameId, _listingFeeEthRed, _listingFeeKtyRed);
        
        (uint256 _listingFeeEthBlack, uint256 _listingFeeKtyBlack) = getKittieListingFee(_kittyBlack);
        _setTotalSpentInGame(_gameId, _listingFeeEthBlack, _listingFeeKtyBlack);
    }

    /**
     * @dev store the total debit by an a/c per game
     */
    function setTotalDebit
    (
        uint _gameId, address _account, uint _eth_amount, uint _kty_amount
    ) 
        external
        onlyContract(CONTRACT_NAME_ENDOWMENT_FUND)
        onlyExistingHoneypot(_gameId)
        returns (bool)
    {
        if (_eth_amount > 0) {
            bytes32 ethTotalDebitPerGamePerAcKey = keccak256(abi.encodePacked(_gameId, _account, "ethDebit"));
            uint ethTotal = genericDB.getUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ethTotalDebitPerGamePerAcKey);
            genericDB.setUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ethTotalDebitPerGamePerAcKey, ethTotal.add(_eth_amount));
        }

        if (_kty_amount > 0) {
            bytes32 ktyTotalDebitPerGamePerAcKey = keccak256(abi.encodePacked(_gameId, _account, "ktyDebit"));
            uint ktyTotal = genericDB.getUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ktyTotalDebitPerGamePerAcKey);
            genericDB.setUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ktyTotalDebitPerGamePerAcKey, ktyTotal.add(_kty_amount));
            }

        return true;
    }


    // getters
     ///@dev return listing fee in ether and swapped listing fee KTY for each kittie with kittieId listed
    function getKittieListingFee(uint256 kittieId)
    public view returns (uint256, uint256)
    {
        uint256 _listingFeeEther = genericDB.getUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(kittieId, "kittieListingFeeEther")));
        uint256 _listingFeeKty = genericDB.getUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(kittieId, "kittieListingFeeKty")));
        return (_listingFeeEther, _listingFeeKty);
    }

    /**
     * @dev get total debit by an a/c per game
     */
    function getTotalDebit
    (
        uint _gameId, address _account
    ) 
        public view
        //onlyExistingProfile(_account)
        onlyExistingHoneypot(_gameId)
        returns (uint256 ethTotalDebit, uint256 ktyTotalDebit)
    {
        bytes32 ethTotalDebitPerGamePerAcKey = keccak256(abi.encodePacked(_gameId, _account, "ethDebit"));
        bytes32 ktyTotalDebitPerGamePerAcKey = keccak256(abi.encodePacked(_gameId, _account, "ktyDebit"));
        ethTotalDebit = genericDB.getUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ethTotalDebitPerGamePerAcKey);
        ktyTotalDebit = genericDB.getUintStorage(CONTRACT_NAME_ACCOUNTING_DB, ktyTotalDebitPerGamePerAcKey);
    }

    function getWithdrawalState(uint _gameId, address _account) public view returns (bool) {
        (uint256 totalETHdebited, uint256 totalKTYdebited) = getTotalDebit(_gameId, _account);
        return ((totalETHdebited > 0) && (totalKTYdebited > 0));
    }

    // internal functions
     /**
     * @dev set total spent "ether" and total uniswap auto-swapped KTY for each game
    */
    function _setTotalSpentInGame(uint256 _gameId, uint256 _etherAmount, uint256 _ktyAmount)
        internal
    {
        uint256 prevEtherAmount = genericDB.getUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(_gameId, "totalSpentInGame")));
        genericDB.setUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(_gameId, "totalSpentInGame")),
            prevEtherAmount.add(_etherAmount));

        uint256 prevKtyAmount = genericDB.getUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(_gameId, "totalSwappedKtyInGame")));
        genericDB.setUintStorage(
            CONTRACT_NAME_ACCOUNTING_DB,
            keccak256(abi.encodePacked(_gameId, "totalSwappedKtyInGame")),
            prevKtyAmount.add(_ktyAmount));
    }
    
}