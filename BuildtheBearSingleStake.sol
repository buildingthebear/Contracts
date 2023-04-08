//SPDX-License-Identifier: MIT

/**
▄▄▄▄· ▄• ▄▌▪  ▄▄▌  ·▄▄▄▄      ▄▄▄▄▄ ▄ .▄▄▄▄ .    ▄▄▄▄· ▄▄▄ . ▄▄▄· ▄▄▄
▐█ ▀█▪█▪██▌██ ██•  ██▪ ██     •██  ██▪▐█▀▄.▀·    ▐█ ▀█▪▀▄.▀·▐█ ▀█ ▀▄ █·
▐█▀▀█▄█▌▐█▌▐█·██▪  ▐█· ▐█▌     ▐█.▪██▀▐█▐▀▀▪▄    ▐█▀▀█▄▐▀▀▪▄▄█▀▀█ ▐▀▀▄
██▄▪▐█▐█▄█▌▐█▌▐█▌▐▌██. ██      ▐█▌·██▌▐▀▐█▄▄▌    ██▄▪▐█▐█▄▄▌▐█ ▪▐▌▐█•█▌
·▀▀▀▀  ▀▀▀ ▀▀▀.▀▀▀ ▀▀▀▀▀•      ▀▀▀ ▀▀▀ · ▀▀▀     ·▀▀▀▀  ▀▀▀  ▀  ▀ .▀  ▀
           -... ..- .. .-.. -..    - .... .    -... . .- .-.

buildthebear.market, buildthebear.online
@buildingthebear on telegram, twitter, github
*/

pragma solidity ^0.8.19;


/* - INTERFACES - */

// ERC-20
interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ERC-20 Metadata
interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface NFTContract {
    function balanceOf(address owner) external view returns (uint256 balance);
}


/* - CONTRACTS - */

// ERC-20
contract ERC20 is IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    string private contractName;
    string private contractSymbol;

    uint8 private constant DECIMALS = 9;
    uint256 private constant SUPPLY = 1000000 gwei;

    constructor(string memory n, string memory s) {
        contractName = n;
        contractSymbol = s;

        _balances[msg.sender] = SUPPLY;

        emit Transfer(address(0), msg.sender, SUPPLY);
    }

    function symbol() external view virtual override returns (string memory) { return contractSymbol; }
    function name() external view virtual override returns (string memory) { return contractName; }
    function balanceOf(address account) public view virtual override returns (uint256) { return _balances[account]; }
    function decimals() public pure virtual override returns (uint8) { return DECIMALS; }
    function totalSupply() external view virtual override returns (uint256) { return SUPPLY; }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        address owner = msg.sender;

        uint256 currentAllowance = allowance(owner, spender);

        require(currentAllowance >= subtractedValue, "Allowance cannot be less than zero");

        unchecked { _approve(owner, spender, currentAllowance - subtractedValue); }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        address owner = msg.sender;

        _approve(owner, spender, allowance(owner, spender) + addedValue);

        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);

        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");

            unchecked { _approve(owner, spender, currentAllowance - amount); }
        }
    }

    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        address owner = msg.sender;

        _approve(owner, spender, amount);

        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "Cannot approve from the zero address");
        require(spender != address(0), "Cannot approve to the zero address");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        address spender = msg.sender;

        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);

        return true;
    }
}

// ʕ •ᴥ•ʔ Build the Bear, Bring the Bull
contract BuildtheBearSingleStake {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    address public owner;

    // NFTs with staking rewards
    address[] public nftContracts;

    // Total staked
    uint public totalSupply;
    // Duration of rewards to be paid out (in seconds)
    uint public duration;
    // Timestamp of when the rewards finish
    uint public finishAt;
    // Minimum of last updated time and reward finish time
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e9 / total supply)
    uint public rewardPerTokenStored;

    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;
    // User address => staked amount
    mapping(address => uint) public balanceOf;

    constructor(address _stakingToken, address _rewardsToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    modifier onlyOwner() { require(msg.sender == owner, "Function can only be called by the contract owner"); _; }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return block.timestamp <= finishAt ? block.timestamp : finishAt;
    }

    function rewardPerToken() public view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e9) / totalSupply;
    }

    function stake(uint _amount) external updateReward(msg.sender) {
        require(_amount > 0, "Must stake some amount");

        stakingToken.transferFrom(msg.sender, address(this), _amount);
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
    }

    function withdraw(uint _amount) external updateReward(msg.sender) {
        require(_amount > 0, "Must withdraw some amount");

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        stakingToken.transfer(msg.sender, _amount);
    }

    function earned(address _account) public view returns (uint) {
        return ((balanceOf[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e9) + rewards[_account];
    }

    function getReward() external updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        uint totalReward = reward;

        totalReward = applyNFTRewards(reward, msg.sender);

        if (totalReward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, totalReward);
        }
    }

    function setRewardsDuration(uint _duration) external onlyOwner {
        require(finishAt < block.timestamp, "Reward duration not finished");

        duration = _duration;
    }

    function setRewardAmount(uint _amount) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint remainingRewards = (finishAt - block.timestamp) * rewardRate;

            rewardRate = (_amount + remainingRewards) / duration;
        }

        require(rewardRate > 0, "Reward rate must be greater than zero");
        require(rewardRate * duration <= rewardsToken.balanceOf(address(this)), "Reward pool not sufficient");

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    function addNFTContract(address contractAddress) external onlyOwner {
        nftContracts.push(contractAddress);
    }

    // Rewards scale downwards for any future BtB NFT Collection releases
    // e.g. Base reward + 25% for Early Adopters, Base + 20% for BtB PFP, and so-on with future collections
    function applyNFTRewards(uint baseAmount, address stakeholder) private view returns (uint) {
        uint rewardScale = 25;
        uint rewardAmount;
        uint finalAmount;

        for(uint8 i = 0; i < nftContracts.length; i++) {
            if (NFTContract(nftContracts[i]).balanceOf(stakeholder) > 0) {
                unchecked {
                    baseAmount > 0 ? rewardAmount += (baseAmount * rewardScale) / 100 : rewardAmount = 0;
                }
            }

            rewardScale -= 5;
        }

        finalAmount = baseAmount + rewardAmount;

        return finalAmount;
    }
}

/** 01000010 01110101 01101001 01101100 01100100  01110100 01101000 01100101  01000010 01100101 01100001 01110010 */
