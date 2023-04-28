// SPDX-License-Identifier: MIT

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
contract BuildtheBearLockedStake {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    address public owner;

    // NFTs with staking rewards
    address[] public nftContracts;

    // Total staked
    uint public totalSupply;
    // Duration of rewards to be paid out (in seconds)
    uint public duration;
    // Timestamp of when rewards end
    uint public finishAt;
    // Minimum of lastUpdatedTime and finishAt
    uint public updatedAt;
    // Rewards paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e9 / total supply)
    uint public rewardPerTokenStored;

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 duration;
    }

    mapping(address => StakeInfo[]) public stakes;

    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed, rewards claimed
    mapping(address => uint) public rewards;
    mapping(address => uint) public claimedRewards;
    // User address => staked amount
    mapping(address => uint) public balanceOf;

    constructor(address _stakingToken, address _rewardsToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    modifier onlyOwner() { require(msg.sender == owner, "Function can only be called by the contract owner"); _; }

    // Update reward calculations
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            uint accountReward = earned(_account);
            rewards[_account] = accountReward; // Update rewards mapping value
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    // Return last block rewards were applicable
    function lastTimeRewardApplicable() public view returns (uint) {
        return block.timestamp <= finishAt ? block.timestamp : finishAt;
    }

    // Calculate reward per token staked
    function rewardPerToken() public view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        uint timeDiff = lastTimeRewardApplicable() - updatedAt;
        uint adjustedRewardRate = rewardRate * timeDiff / duration;

        return rewardPerTokenStored + (adjustedRewardRate * 1e9) / totalSupply;
    }

    // Stake a given number of tokens for a given timeframe
    function stake(uint _amount, uint256 _duration) external updateReward(msg.sender) {
        require(_amount > 0, "Must stake some amount");
        require(_duration % 3 == 0 && _duration <= 12, "Invalid staking duration, should be 3, 6, 9, or 12 (months)");

        stakingToken.transferFrom(msg.sender, address(this), _amount);
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;

        stakes[msg.sender].push(StakeInfo({
            amount: _amount,
            startTime: block.timestamp,
            duration: _duration * 30 minutes
        }));
    }

    // Withdraw a given stake
    function withdraw(uint _amount, uint _stakeIndex) external {
        require(_amount > 0, "Must withdraw some amount");
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        require(block.timestamp >= stakes[msg.sender][_stakeIndex].startTime + stakes[msg.sender][_stakeIndex].duration, "Staking period not finished");

        stakes[msg.sender][_stakeIndex].amount -= _amount;

        if (stakes[msg.sender][_stakeIndex].amount == 0) {
            stakes[msg.sender][_stakeIndex] = stakes[msg.sender][stakes[msg.sender].length - 1];
            stakes[msg.sender].pop();
        }

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        stakingToken.transfer(msg.sender, _amount);
    }

    // Calculate rewards earned for the current reward pool
    function earned(address _account) public view returns (uint) {
        if (block.timestamp >= finishAt && updatedAt >= finishAt) {
            return 0;
        }

        uint totalReward = 0;

        for (uint i = 0; i < stakes[_account].length; i++) {
            uint timeDiff = block.timestamp >= stakes[_account][i].startTime + stakes[_account][i].duration ?
            stakes[_account][i].startTime + stakes[_account][i].duration - stakes[_account][i].startTime :
            lastTimeRewardApplicable() - stakes[_account][i].startTime;

            uint stakeReward = rewardPerToken() * stakes[_account][i].amount * timeDiff / 1e9;
            uint durationBonusPercentage;
            uint stakeDuration = stakes[_account][i].duration;

            if (stakeDuration == 3 * 30 minutes) {
                durationBonusPercentage = 0;
            } else if (stakeDuration == 6 * 30 minutes) {
                durationBonusPercentage = 10;
            } else if (stakeDuration == 9 * 30 minutes) {
                durationBonusPercentage = 20;
            } else if (stakeDuration == 12 * 30 minutes) {
                durationBonusPercentage = 30;
            }

            uint bonusReward = (stakeReward * durationBonusPercentage) / 100;

            totalReward += stakeReward + bonusReward;
        }

        // Calculate net earned rewards
        uint netEarnedRewards = totalReward > claimedRewards[_account] ? totalReward - claimedRewards[_account] : 0;

        return netEarnedRewards;
    }

    // Claim earned rewards
    function getReward() external {
        uint reward = earned(msg.sender);
        uint totalReward = applyNFTRewards(reward, msg.sender);

        if (totalReward > 0) {
            rewardsToken.transfer(msg.sender, totalReward);

            // Update the reward values after the rewards are claimed
            updatedAt = lastTimeRewardApplicable();
            rewardPerTokenStored = rewardPerToken();
            rewards[msg.sender] = 0;
            userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;

            claimedRewards[msg.sender] += totalReward;
        }
    }

    // Compound earned rewards evenly across all stakes
    function compoundRewards() external {
        uint reward = earned(msg.sender);
        uint totalReward = reward;

        if (totalReward > 0) {
            rewards[msg.sender] = 0;

            uint stakeCount = stakes[msg.sender].length;
            uint remainingReward = totalReward;

            for (uint i = 0; i < stakeCount; i++) {
                uint stakeReward = totalReward / stakeCount;

                if (i == stakeCount - 1) {
                    stakeReward = remainingReward;
                }

                stakes[msg.sender][i].amount += stakeReward;
                balanceOf[msg.sender] += stakeReward;
                remainingReward -= stakeReward;
            }

            totalSupply += totalReward;

            updatedAt = lastTimeRewardApplicable();
            rewardPerTokenStored = rewardPerToken();
            userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;
            claimedRewards[msg.sender] += totalReward;
        }
    }

    // Set duration of pool's reward distribution
    function setRewardsDuration(uint _duration) external onlyOwner {
        require(finishAt < block.timestamp, "Reward duration not finished");

        duration = _duration;
        finishAt = block.timestamp + _duration;
    }

    // Set amount of rewards to be distributed
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

    // Push another bonus reward supporting NFT contract
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
