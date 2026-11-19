// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal interface of the SPACE ID Agent ID registry (BNB Chain).
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title AgentWall
/// @notice An on-chain guestbook and daily check-in wall bound to SPACE ID Agent IDs.
/// @dev Every action must name the caller's Agent ID token, and the contract verifies
///      on-chain that the caller actually owns that Agent ID (ownerOf == msg.sender).
///      The contract holds no user assets, takes no approvals, and has no admin keys:
///      there is no owner, no pause, no mint, and no withdrawal function at all.
contract AgentWall {
    /// @notice The SPACE ID Agent ID registry on BNB Chain (0x60B9...8B022F).
    IAgentIdRegistry public immutable agentRegistry;

    uint256 public constant MAX_MESSAGE_BYTES = 280;
    uint256 public constant MAX_STATUS_BYTES = 64;

    struct Post {
        address author;
        uint256 agentId;
        string message;
        uint256 timestamp;
    }

    Post[] private _posts;

    /// @notice Last UTC day index (timestamp / 86400) the Agent ID checked in.
    mapping(uint256 => uint256) public lastCheckInDay;
    /// @notice Current consecutive-day check-in streak of an Agent ID.
    mapping(uint256 => uint256) public checkInStreak;
    /// @notice Lifetime check-in count of an Agent ID.
    mapping(uint256 => uint256) public totalCheckIns;
    /// @notice Short public status line set by an Agent ID's owner.
    mapping(uint256 => string) public statusOf;
    /// @notice Whether an address has ever interacted with the wall.
    mapping(address => bool) public hasInteracted;

    /// @notice Number of distinct Agent ID holder addresses that have interacted.
    uint256 public uniqueAgents;
    /// @notice Total number of actions (posts + check-ins + status sets).
    uint256 public totalActions;

    event Posted(address indexed author, uint256 indexed agentId, uint256 postIndex, string message);
    event CheckedIn(address indexed author, uint256 indexed agentId, uint256 day, uint256 streak);
    event StatusSet(address indexed author, uint256 indexed agentId, string status);

    constructor(address registry) {
        require(registry != address(0), "registry is zero address");
        agentRegistry = IAgentIdRegistry(registry);
    }

    modifier onlyAgentOwner(uint256 agentId) {
        require(agentRegistry.ownerOf(agentId) == msg.sender, "AgentWall: not your Agent ID");
        _;
    }

    function _touch() internal {
        if (!hasInteracted[msg.sender]) {
            hasInteracted[msg.sender] = true;
            uniqueAgents += 1;
        }
        totalActions += 1;
    }

    /// @notice Post a message to the wall, signed by your Agent ID.
    function sign(uint256 agentId, string calldata message) external onlyAgentOwner(agentId) {
        uint256 len = bytes(message).length;
        require(len > 0, "AgentWall: empty message");
        require(len <= MAX_MESSAGE_BYTES, "AgentWall: message too long");
        _posts.push(Post({author: msg.sender, agentId: agentId, message: message, timestamp: block.timestamp}));
        _touch();
        emit Posted(msg.sender, agentId, _posts.length - 1, message);
    }

    /// @notice Check in once per UTC day with your Agent ID and build a streak.
    function checkIn(uint256 agentId) external onlyAgentOwner(agentId) {
        uint256 today = block.timestamp / 86400;
        uint256 last = lastCheckInDay[agentId];
        require(last != today, "AgentWall: already checked in today");
        if (last == today - 1) {
            checkInStreak[agentId] += 1;
        } else {
            checkInStreak[agentId] = 1;
        }
        lastCheckInDay[agentId] = today;
        totalCheckIns[agentId] += 1;
        _touch();
        emit CheckedIn(msg.sender, agentId, today, checkInStreak[agentId]);
    }

    /// @notice Set a short public status line for your Agent ID.
    function setStatus(uint256 agentId, string calldata status) external onlyAgentOwner(agentId) {
        require(bytes(status).length <= MAX_STATUS_BYTES, "AgentWall: status too long");
        statusOf[agentId] = status;
        _touch();
        emit StatusSet(msg.sender, agentId, status);
    }

    /// @notice True if the address holds at least one Agent ID.
    function isAgentHolder(address account) external view returns (bool) {
        return agentRegistry.balanceOf(account) > 0;
    }

    /// @notice True if the address owns the given Agent ID.
    function ownsAgent(address account, uint256 agentId) external view returns (bool) {
        return agentRegistry.ownerOf(agentId) == account;
    }

    function postCount() external view returns (uint256) {
        return _posts.length;
    }

    function getPost(uint256 index) external view returns (address author, uint256 agentId, string memory message, uint256 timestamp) {
        require(index < _posts.length, "AgentWall: no such post");
        Post storage p = _posts[index];
        return (p.author, p.agentId, p.message, p.timestamp);
    }

    /// @notice Read up to `count` posts starting at `offset` (count is capped at 50).
    function getPosts(uint256 offset, uint256 count) external view returns (Post[] memory) {
        uint256 total = _posts.length;
        if (offset >= total) return new Post[](0);
        uint256 n = count > 50 ? 50 : count;
        if (offset + n > total) n = total - offset;
        Post[] memory out = new Post[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = _posts[offset + i];
        }
        return out;
    }
}
