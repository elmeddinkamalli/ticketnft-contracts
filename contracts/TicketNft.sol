// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

contract TicketNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ERC721BurnableUpgradeable,
    UUPSUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    uint256 public createEventCost;
    uint256 public systemPercent;
    bool public creatorsPermission;

    struct Event {
        uint256 id;
        string _centralizedId;
        address creator;
        string eventURI;
        uint256 maxSupply;
        uint256 pricePerTicket;
        uint256 saleStarts;
        uint256 saleEnds;
        bool paused;
    }

    event createNewEvent(
        uint256 eventId,
        string centralizedId,
        uint256 saleStarts,
        uint256 saleEnds
    );
    event mintingEventTicket(
        uint256 eventId,
        uint256 tokenId,
        uint256 centralizedId
    );
    event deletingEvent(uint256 eventId);
    event burningTicket(uint256 ticketId);
    event pausingEvent(uint256 eventId, bool paused);

    uint256 public eventCount = 0;
    mapping(uint256 => Event) public idToEvent;
    mapping(address => Event[]) public addressToEvents;
    mapping(address => uint256[]) public addressToTickets;
    mapping(uint256 => uint256) public eventTicketSoldCount;
    mapping(uint256 => uint256) public ticketIdToTicketEvent;
    mapping(address => bool) public isEventCreator;
    mapping(address => mapping(uint256 => bool)) public hasEventTicket;
    mapping(uint256 => string) private _tokenURIs;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier mintCompliance(uint256 eventId, address _address) {
        _checkMintCompliance(eventId, _address);
        _;
    }

    function _checkMintCompliance(uint256 eventId, address _address)
        private
        view
    {
        Event memory _event = idToEvent[eventId];
        require(_event.id != 0, "Event does not exists!");
        require(
            _event.saleEnds == 0 ||
                (block.timestamp >= _event.saleStarts &&
                    block.timestamp <= _event.saleEnds),
            "Sale ended!"
        );
        require(!_event.paused, "Sale paused!");
        require(
            !hasEventTicket[_address][eventId],
            "Already got a ticket for this event!"
        );
        require(
            eventTicketSoldCount[eventId] <= _event.maxSupply,
            "Max supply exceeded!"
        );
    }

    modifier canCreateEvents(address _address) {
        require(
            !creatorsPermission ||
                isEventCreator[_address] ||
                _address == owner(),
            "Not authorized"
        );
        _;
    }

    function totalTicketCount() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function initialize() public initializer {
        __ERC721_init("TicketNFT", "TNFT");
        __ERC721URIStorage_init();
        __Pausable_init();
        __Ownable_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();

        createEventCost = 1000000000000000;
        systemPercent = 5;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function createEvent(
        string memory eventURI,
        string memory _centralizedId,
        uint256 maxTicketSupply,
        uint256 pricePerTicket,
        uint256 saleStarts,
        uint256 saleEnds
    ) public payable canCreateEvents(msg.sender) returns (uint256) {
        require(
            msg.value == createEventCost || msg.sender == owner(),
            "Cost not set!"
        );
        require(saleEnds == 0 || saleEnds > saleStarts, "Invalid dates!");

        eventCount++;

        addressToEvents[msg.sender].push(
            Event(
                eventCount,
                _centralizedId,
                msg.sender,
                eventURI,
                maxTicketSupply,
                pricePerTicket,
                saleStarts,
                saleEnds,
                false
            )
        );

        idToEvent[eventCount] = Event(
            eventCount,
            _centralizedId,
            msg.sender,
            eventURI,
            maxTicketSupply,
            pricePerTicket,
            saleStarts,
            saleEnds,
            false
        );

        emit createNewEvent(eventCount, _centralizedId, saleStarts, saleEnds);
        return eventCount;
    }

    function mintTicketForAddress(
        uint256 _eventId,
        address _receiver,
        string memory _tokenURI,
        uint256 _centralizedId
    ) public mintCompliance(_eventId, _receiver) onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(_receiver, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        addressToTickets[_receiver].push(tokenId);

        ticketIdToTicketEvent[tokenId] = _eventId;

        uint256 soldCount = eventTicketSoldCount[_eventId] + 1;
        eventTicketSoldCount[_eventId] = soldCount;
        hasEventTicket[msg.sender][_eventId] = true;

        emit mintingEventTicket(_eventId, tokenId, _centralizedId);

        return tokenId;
    }

    function mintTicket(
        uint256 _eventId,
        string memory _tokenURI,
        uint256 _centralizedId
    ) public payable mintCompliance(_eventId, msg.sender) returns (uint256) {
        Event memory _event = idToEvent[_eventId];
        require(
            msg.value == _event.pricePerTicket,
            "You have to pay the price!"
        );
        (bool hs, ) = payable(_event.creator).call{
            value: (msg.value * (100 - systemPercent)) / 100
        }("");
        require(hs);

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        addressToTickets[msg.sender].push(tokenId);

        ticketIdToTicketEvent[tokenId] = _eventId;

        uint256 soldCount = eventTicketSoldCount[_eventId] + 1;
        eventTicketSoldCount[_eventId] = soldCount;
        hasEventTicket[msg.sender][_eventId] = true;

        emit mintingEventTicket(_eventId, tokenId, _centralizedId);
        return tokenId;
    }

    function setCost(uint256 _cost) public onlyOwner {
        createEventCost = _cost;
    }

    function setSystemPercent(uint256 _percent) public onlyOwner {
        systemPercent = _percent;
    }

    function setCreatorsPermission(bool _allow) public onlyOwner {
        creatorsPermission = _allow;
    }

    function authorizeAddressToCreateEvent(address _address, bool _canCreate)
        public
        onlyOwner
    {
        isEventCreator[_address] = _canCreate;
    }

    function getAllEventsOf(address creator)
        public
        view
        returns (Event[] memory)
    {
        return addressToEvents[creator];
    }

    function getTicketEvent(uint256 id) public view returns (uint256) {
        return ticketIdToTicketEvent[id];
    }

    function getUserTicketsByAddress(address _address)
        public
        view
        returns (uint256[] memory)
    {
        return addressToTickets[_address];
    }

    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        uint256 eventId = ticketIdToTicketEvent[tokenId];
        delete hasEventTicket[ownerOf(tokenId)][eventId];
        super._burn(tokenId);
        emit burningTicket(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function burnEvent(uint256 _eventId) public returns (bool) {
        Event memory getEvent = idToEvent[_eventId];
        require(
            getEvent.creator == msg.sender || msg.sender == owner(),
            "Only event owner!"
        );

        delete idToEvent[_eventId];
        emit deletingEvent(_eventId);
        return true;
    }

    function changeEventPauseState(uint256 _eventId, bool paused)
        public
        returns (bool)
    {
        Event memory getEvent = idToEvent[_eventId];
        require(
            getEvent.creator == msg.sender || msg.sender == owner(),
            "Only event owner!"
        );
        require(getEvent.paused != paused, "Not try to set same value!");

        getEvent.paused = paused;
        idToEvent[_eventId] = getEvent;
        emit pausingEvent(_eventId, paused);
        return true;
    }
}
