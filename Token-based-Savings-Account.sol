// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenSavingsAccount
 * @dev A simple savings account that accepts token deposits, 
 * applies interest, and allows withdrawals after lock periods
 */
contract TokenSavingsAccount is ReentrancyGuard {
    // Token being used for the savings account
    IERC20 public savingsToken;
    
    // Contract owner
    address public owner;
    
    // Interest rate (expressed as basis points, 1 basis point = 0.01%)
    uint256 public interestRateBps = 500; // 5% annual interest rate
    
    // Lock period in seconds (default: 30 days)
    uint256 public lockPeriod = 30 days;
    
    // Structure to represent a user's savings account
    struct SavingsAccount {
        uint256 balance;
        uint256 lastDepositTime;
        uint256 interestAccrued;
    }
    
    // Mapping user addresses to their savings accounts
    mapping(address => SavingsAccount) public accounts;
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event InterestAccrued(address indexed user, uint256 amount);
    
    // Simple owner check modifier
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    /**
     * @dev Constructor to set the token address used for savings
     * @param _tokenAddress Address of the ERC20 token
     */
    constructor(address _tokenAddress) {
        savingsToken = IERC20(_tokenAddress);
        owner = msg.sender;
    }
    
    /**
     * @dev Deposit tokens into the savings account
     * @param _amount Amount of tokens to deposit
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        
        // First calculate any outstanding interest if there's an existing balance
        if (accounts[msg.sender].balance > 0) {
            _calculateInterest(msg.sender);
        }
        
        // Transfer tokens from user to contract
        bool success = savingsToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");
        
        // Update user's account
        accounts[msg.sender].balance += _amount;
        accounts[msg.sender].lastDepositTime = block.timestamp;
        
        emit Deposit(msg.sender, _amount);
    }
    
    /**
     * @dev Withdraw tokens from the savings account
     * @param _amount Amount of tokens to withdraw
     */
    function withdraw(uint256 _amount) external nonReentrant {
        SavingsAccount storage account = accounts[msg.sender];
        
        require(_amount > 0, "Amount must be greater than zero");
        require(account.balance >= _amount, "Insufficient balance");
        require(
            block.timestamp >= account.lastDepositTime + lockPeriod,
            "Funds are still in lock period"
        );
        
        // Calculate interest before withdrawal
        _calculateInterest(msg.sender);
        
        // Reduce balance
        account.balance -= _amount;
        
        // Transfer tokens to user
        bool success = savingsToken.transfer(msg.sender, _amount);
        require(success, "Token transfer failed");
        
        emit Withdrawal(msg.sender, _amount);
    }
    
    /**
     * @dev Calculate and update accrued interest for a user
     * @param _user Address of the user
     * @return interest The amount of interest accrued
     */
    function _calculateInterest(address _user) internal returns (uint256 interest) {
        SavingsAccount storage account = accounts[_user];
        
        if (account.balance == 0) {
            return 0;
        }
        
        // Calculate time elapsed since last deposit (in seconds)
        uint256 timeElapsed = block.timestamp - account.lastDepositTime;
        
        // Calculate interest: balance × rate × timeElapsed / (365 days × 10000)
        // Rate is in basis points (1/100 of a percent), hence divided by 10000
        interest = (account.balance * interestRateBps * timeElapsed) / (365 days * 10000);
        
        // Update account
        account.interestAccrued += interest;
        account.lastDepositTime = block.timestamp; // Reset the clock
        
        emit InterestAccrued(_user, interest);
    }
    
    /**
     * @dev View function to check account balance including accrued interest
     * @param _user Address of the user
     * @return principalBalance The base amount deposited by the user
     * @return interestAccrued The amount of interest earned but not yet added to principal
     * @return totalBalance The combined principal and interest amount
     * @return unlockTime The timestamp when funds become available for withdrawal
     */
    function getAccountDetails(address _user) external view returns (
        uint256 principalBalance,
        uint256 interestAccrued,
        uint256 totalBalance,
        uint256 unlockTime
    ) {
        SavingsAccount memory account = accounts[_user];
        
        // Calculate current interest (not updating state)
        uint256 currentInterest = account.interestAccrued;
        if (account.balance > 0) {
            uint256 timeElapsed = block.timestamp - account.lastDepositTime;
            currentInterest += (account.balance * interestRateBps * timeElapsed) / (365 days * 10000);
        }
        
        return (
            account.balance,
            currentInterest,
            account.balance + currentInterest,
            account.lastDepositTime + lockPeriod
        );
    }
}
