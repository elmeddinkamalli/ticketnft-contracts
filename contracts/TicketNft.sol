// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TicketNFT is ERC721, Ownable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private supply;

    string public uriPrefix = "";
    string public uriSuffix = ".json";
    string public hiddenMetadataUri;

    uint256 public createEventCost = 1000000000000000;
    uint256 public systemPercent = 5;

    bool public paused = true;
    bool public revealed = false;

    struct Event {
        uint256 id;
        address creator;
        string name;
        uint256 maxSupply;
        uint256 pricePerTicket;
    }

    uint256 public eventCount = 0;
    mapping(uint256 => Event) public idToEvent;
    mapping(address => Event[]) public addressToEvents;
    mapping(address => uint256[]) public addressToTickets;
    mapping(uint256 => uint256) public eventTicketSoldCount;
    mapping(uint256 => uint256) public ticketIdToTicketEvent;
    mapping(address => bool) public eventCreator;
    mapping(address => mapping(uint256 => bool)) public hasEventTicket;

    constructor() ERC721("TicketNFT", "TNFT") {
        setHiddenMetadataUri(
            "ipfs://QmUivQkWwjvLKwPJ9CmZPELSNDNyfN9uKyuptubgYehU8L/hidden.json"
        );
    }

    modifier mintCompliance(uint256 eventId, address _address) {
        require(idToEvent[eventId].id != 0, "Event does not exists!");
        require(
            !hasEventTicket[_address][eventId],
            "Already got a ticket for this event!"
        );
        require(idToEvent[eventId].id != 0, "Event does not exists!");
        require(
            eventTicketSoldCount[eventId] + 1 <= idToEvent[eventId].maxSupply,
            "Max supply exceeded!"
        );
        _;
    }

    modifier canCreateEvents(address _address) {
        require(
            eventCreator[_address] || _address == owner(),
            "Not authorized"
        );
        _;
    }

    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    function createEvent(
        string memory eventName,
        uint256 maxTicketSupply,
        uint256 pricePerTicket
    ) public payable canCreateEvents(msg.sender) returns (uint256) {
        require(
            msg.value == createEventCost || msg.sender == owner(),
            "Cost not set!"
        );
        eventCount++;

        addressToEvents[msg.sender].push(
            Event(
                eventCount,
                msg.sender,
                eventName,
                maxTicketSupply,
                pricePerTicket
            )
        );

        idToEvent[eventCount] = Event(
            eventCount,
            msg.sender,
            eventName,
            maxTicketSupply,
            pricePerTicket
        );

        return eventCount;
    }

    function mintTicket(uint256 _eventId)
        public
        payable
        mintCompliance(_eventId, msg.sender)
        returns (uint256)
    {
        Event memory _event = idToEvent[_eventId];
        require(
            msg.value == _event.pricePerTicket,
            "You have to pay the price!"
        );
        (bool hs, ) = payable(_event.creator).call{
            value: (msg.value * (100 - systemPercent)) / 100
        }("");
        require(hs);
        supply.increment();
        _safeMint(msg.sender, supply.current());

        addressToTickets[msg.sender].push(supply.current());

        ticketIdToTicketEvent[supply.current()] = _eventId;

        uint256 soldCount = eventTicketSoldCount[_eventId] + 1;
        eventTicketSoldCount[_eventId] = soldCount;
        hasEventTicket[msg.sender][_eventId] = true;
        return supply.current();
    }

    function mintTicketForAddress(uint256 _eventId, address _receiver)
        public
        mintCompliance(_eventId, _receiver)
        onlyOwner
        returns (uint256)
    {
        supply.increment();
        _safeMint(_receiver, supply.current());

        addressToTickets[_receiver].push(supply.current());

        ticketIdToTicketEvent[supply.current()] = _eventId;

        uint256 soldCount = eventTicketSoldCount[_eventId] + 1;
        eventTicketSoldCount[_eventId] = soldCount;
        hasEventTicket[msg.sender][_eventId] = true;
        return supply.current();
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return hiddenMetadataUri;
        }

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    function setCost(uint256 _cost) public onlyOwner {
        createEventCost = _cost;
    }

    function setSystemPercent(uint256 _percent) public onlyOwner {
        systemPercent = _percent;
    }

    function setHiddenMetadataUri(string memory _hiddenMetadataUri)
        public
        onlyOwner
    {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function setUriPrefix(string memory _uriPrefix) public onlyOwner {
        uriPrefix = _uriPrefix;
    }

    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function setPaused(bool _state) public onlyOwner {
        paused = _state;
    }

    function setEventCreator(address _address, bool _canCreate)
        public
        onlyOwner
    {
        eventCreator[_address] = _canCreate;
    }

    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function _mintLoop(address _receiver, uint256 _mintAmount) internal {
        for (uint256 i = 0; i < _mintAmount; i++) {
            supply.increment();
            _safeMint(_receiver, supply.current());
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return uriPrefix;
    }

    function getAllEvents(address creator)
        public
        view
        returns (Event[] memory)
    {
        return addressToEvents[creator];
    }

    function getTicketEvent(uint256 id) public view returns (uint256) {
        return ticketIdToTicketEvent[id];
    }

    function getUserTickets() public view returns (uint256[] memory) {
        return addressToTickets[msg.sender];
    }

    function getUserTicketsByAddress(address _address)
        public
        view
        returns (uint256[] memory)
    {
        return addressToTickets[_address];
    }
}
