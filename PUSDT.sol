// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "./math/SafeMath.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external ;
    function decimals() external view returns (uint8);
}

contract PUSDT {
    using SafeMath for uint256;
    string public name     = "PairX Tether USD";
    string public symbol   = "PUSDT";
    uint8  public decimals = 6;

    uint256 public totalPUSDT = 0;
    uint256 public totalUSDT = 0;
    uint256 public totalInterest = 0;
    uint256 public subTotalInterest = 0;
    uint256 public usedUSDT = 0;
    address public investAddr;

    bool private reEntrancyMutex = false;//Mutexes that prevent reentrant attacks
    bool private canDeposit = true;//Allow to deposit.
    IERC20 usdt;

    event  Approval(address indexed src, address indexed guy, uint256 wad);
    event  Transfer(address indexed src, address indexed dst, uint256 wad);
    event  Deposit(address indexed dst, uint256 wad);
    event  Refund(address indexed src, uint256 principle);
    event  AddInterest(address indexed src, uint256 interest);
    event  SubInterest(address indexed src, uint256 interest);
    event  Withdrawal(address indexed src, uint256 wad, uint256 ethNeed);
    event  Invest(address indexed src, uint256 wad);
    event  ChangeIvAddr(address indexed src, address indexed newAddr);
    event  ChangeDeposit(address indexed src, bool canDeposit);

    mapping (address => uint256)                       public  balanceOf;
    mapping (address => mapping (address => uint256))  public  allowance;

    constructor(address _investAddr,IERC20 _usdt) public {
        investAddr = _investAddr;
        usdt = _usdt;
    }

    function deposit(uint256 wad) public {
        require(canDeposit);
        if (totalUSDT > 0 && totalPUSDT > 0 && totalUSDT != totalPUSDT) {
            balanceOf[msg.sender] = wad.mul(totalPUSDT).div(totalUSDT).add(balanceOf[msg.sender]);
            totalPUSDT = wad.mul(totalPUSDT).div(totalUSDT).add(totalPUSDT);
            totalUSDT = totalUSDT.add(wad);
            emit Transfer(address(0), msg.sender, wad.mul(totalPUSDT).div(totalUSDT));
        } else {
            balanceOf[msg.sender] = balanceOf[msg.sender].add(wad);
            totalPUSDT = totalPUSDT.add(wad);
            totalUSDT = totalUSDT.add(wad);
            emit Transfer(address(0), msg.sender, wad);
        }
        usdt.transferFrom(msg.sender, address(this), wad);
        emit Deposit(msg.sender, wad);
    }
    function refund(uint256 principle) public {
        usedUSDT = usedUSDT.sub(principle);
        usdt.transferFrom(msg.sender, address(this), principle);
        emit Refund(msg.sender, principle);
    }
    function addInterest(uint256 interest) public {
        totalUSDT = totalUSDT.add(interest);
        totalInterest = totalInterest.add(interest);
        usdt.transferFrom(msg.sender, address(this), interest);
        emit AddInterest(msg.sender, interest);
    }
    function subInterest(uint256 interest) public {
        require(msg.sender == investAddr, "Only investAddr can reduce interest.");
        totalUSDT = totalUSDT.sub(interest);
        subTotalInterest = subTotalInterest.add(interest);
        usdt.transfer(msg.sender, interest);
        emit SubInterest(msg.sender, interest);
    }
    function withdraw(uint256 wad) public {
        require(!reEntrancyMutex);
        uint256 assetNeed = 0;
        if (totalPUSDT > 0) assetNeed = wad.mul(totalUSDT).div(totalPUSDT);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(wad);
        totalPUSDT = totalPUSDT.sub(wad);
        totalUSDT  = totalUSDT.sub(assetNeed);

        reEntrancyMutex = true;
        usdt.transfer(msg.sender, assetNeed);
        emit Transfer(msg.sender, address(0), wad);
        emit Withdrawal(msg.sender, wad, assetNeed);
        reEntrancyMutex = false;
    }
    function invest(uint256 wad) public {
        require(msg.sender == investAddr, "Only investAddr can invest.");
        usedUSDT = usedUSDT.add(wad);
        usdt.transfer(msg.sender, wad);
        emit Invest(msg.sender, wad);
    }
    function changeIvAddr(address newAddr) public {
        require(msg.sender == investAddr, "Only investAddr can change Invest Address.");
        investAddr = newAddr;
        emit ChangeIvAddr(msg.sender, newAddr);
    }
    function changeDeposit(bool _canDeposit) public {
        require(msg.sender == investAddr, "Only investAddr can change Deposit State.");
        canDeposit = _canDeposit;
        emit ChangeDeposit(msg.sender, _canDeposit);
    }

    function totalSupply() public view returns (uint256) {
        return totalPUSDT;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] = allowance[src][msg.sender].sub(wad);
        }

        balanceOf[src] = balanceOf[src].sub(wad);
        balanceOf[dst] = balanceOf[dst].add(wad);

        emit Transfer(src, dst, wad);

        return true;
    }
}
