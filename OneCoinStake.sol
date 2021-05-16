// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
import "./token/ERC20/SafeERC20.sol";

contract OneCoinStake {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address public ownerAddr;

    // 用户信息.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // 池子信息.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        //uint256 allocPoint; // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardTime; // Last reward time that CAKEs distribution occurs.
        uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e12. See below.
    }

    // The CAKE TOKEN!
    IERC20 public syrup;
    IERC20 public rewardToken;

    // CAKE tokens created per day.
    uint256 public rewardPerDay;
    // Secends per day.
    uint256 private secendsPerDay = 24*60*60;

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // The timestamp when CAKE mining starts.
    uint256 public startTime;
    // The timestamp when CAKE mining ends.
    uint256 public bonusEndTime;
    //Allow to deposit.
    bool private canDeposit = true;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event ChangeDeposit(address indexed src, bool canDeposit);

    constructor(
        address _ownerAddr,
        IERC20 _syrup,
        IERC20 _rewardToken,
        uint256 _rewardPerDay,
        uint256 _startTime,
        uint256 _bonusEndTime
    ) public {
        ownerAddr = _ownerAddr;
        syrup = _syrup;
        rewardToken = _rewardToken;
        rewardPerDay = _rewardPerDay;
        startTime = _startTime;
        bonusEndTime = _bonusEndTime;

        // staking pool
        poolInfo = PoolInfo({ lpToken: _syrup, lastRewardTime: startTime, accCakePerShare: 0 });
        
    }

    function stopReward() public {
        require(msg.sender == ownerAddr, "Only ownerAddr can stop reward.");
        bonusEndTime = block.timestamp;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256)
    {
        if (_to <= bonusEndTime) {
            return _to.sub(_from);
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 cakeReward = multiplier.mul(rewardPerDay).div(secendsPerDay);
            accCakePerShare = accCakePerShare.add( cakeReward.mul(1e12).div(lpSupply) );
        }
        return user.amount.mul(accCakePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        PoolInfo storage pool = poolInfo;
        uint256 timestamp = block.timestamp;
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, timestamp);
        uint256 cakeReward = multiplier.mul(rewardPerDay).div(secendsPerDay);
        pool.accCakePerShare = pool.accCakePerShare.add(
            cakeReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardTime = timestamp;
    }

    // Stake SYRUP tokens to SmartChef
    function deposit(uint256 _amount) public {
        require(canDeposit);
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];

        // require (_amount.add(user.amount) <= maxStaking, 'exceed max stake');

        updatePool();
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accCakePerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    function changeDeposit(bool _canDeposit) public {
        require(msg.sender == ownerAddr, "Only ownerAddr can change Deposit State.");
        canDeposit = _canDeposit;
        emit ChangeDeposit(msg.sender, _canDeposit);
    }

    // Withdraw SYRUP tokens from STAKING.
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending =
            user.amount.mul(pool.accCakePerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public {
        require(msg.sender == ownerAddr, "Only ownerAddr can stop reward.");
        require(_amount < rewardToken.balanceOf(address(this)), "not enough token");
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }
}
