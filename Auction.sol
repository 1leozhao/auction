// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Auction is ReentrancyGuard {
    enum AuctionType { English, Dutch }

    struct AuctionDetail {
        IERC721 nft;
        uint256 nftId;
        address payable seller;
        uint256 startPrice;
        uint256 endPrice; // For Dutch auction
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool started;
        bool ended;
        AuctionType auctionType;
    }

    AuctionDetail public auction;

    event Start(uint256 startTime, uint256 endTime);
    event Bid(address indexed sender, uint256 amount);
    event Withdraw(address indexed bidder, uint256 amount);
    event End(address winner, uint256 amount);

    constructor(
        address _nft,
        uint256 _nftId,
        uint256 _startingBid,
        uint256 _endPrice,
        AuctionType _auctionType
    ) {
        auction.nft = IERC721(_nft);
        auction.nftId = _nftId;
        auction.seller = payable(msg.sender);
        auction.startPrice = _startingBid;
        auction.endPrice = _endPrice;
        auction.auctionType = _auctionType;
        auction.highestBid = _startingBid;
    }

    function start(uint256 _duration) external {
        require(msg.sender == auction.seller, "Only seller can start auction");
        require(!auction.started, "Auction already started");

        auction.nft.transferFrom(msg.sender, address(this), auction.nftId);
        auction.started = true;
        auction.startTime = block.timestamp;
        auction.endTime = block.timestamp + _duration;

        emit Start(auction.startTime, auction.endTime);
    }

    function bid() external payable nonReentrant {
        require(auction.started, "Auction not started");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(!auction.ended, "Auction already ended");

        uint256 bidAmount = msg.value;

        if (auction.auctionType == AuctionType.English) {
            require(bidAmount > auction.highestBid, "Bid too low");
        } else { // Dutch Auction
            uint256 currentPrice = getCurrentPrice();
            require(bidAmount >= currentPrice, "Bid too low");
            auction.ended = true;
        }

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        emit Bid(msg.sender, bidAmount);

        if (auction.auctionType == AuctionType.Dutch) {
            end();
        }
    }

    function end() public {
        require(auction.started, "Auction not started");
        require(!auction.ended, "Auction already ended");
        require(block.timestamp >= auction.endTime || auction.auctionType == AuctionType.Dutch, "Auction cannot be ended yet");

        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            auction.nft.safeTransferFrom(address(this), auction.highestBidder, auction.nftId);
            auction.seller.transfer(auction.highestBid);
        } else {
            auction.nft.safeTransferFrom(address(this), auction.seller, auction.nftId);
        }

        emit End(auction.highestBidder, auction.highestBid);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (auction.auctionType == AuctionType.English) {
            return auction.highestBid;
        } else {
            if (block.timestamp >= auction.endTime) return auction.endPrice;
            uint256 elapsed = block.timestamp - auction.startTime;
            uint256 duration = auction.endTime - auction.startTime;
            return auction.startPrice - (auction.startPrice - auction.endPrice) * elapsed / duration;
        }
    }
}
