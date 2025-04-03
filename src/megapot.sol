// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Interface for the BaseJackpot contract - must be defined at file level, not inside another contract
interface IBaseJackpot {
    function purchaseTickets(address referrer, uint256 value, address recipient) external;
    function ticketPrice() external view returns (uint256);
}

/**
 * @title JackpotCashback
 * @dev A contract that purchases tickets from BaseJackpot on behalf of users
 * and provides immediate cashback to incentivize usage.
 * Now with subscription features allowing users to purchase tickets automatically for multiple days.
 * Updated with subscription upgrade/merge functionality.
 * Modified to use batch processing for all ticket purchases, including initial subscription day.
 * Updated to use global batch day tracking instead of individual day tracking.
 */
contract JackpotCashback is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IBaseJackpot public jackpotContract;
    IERC20 public token;
    address public referrer;
    uint256 public immediatePurchaseCashbackPercentage; // in basis points (e.g., 200 = 2%)
    uint256 public subscriptionCashbackPercentage; // in basis points (e.g., 300 = 3%)
    uint256 public constant MAX_CASHBACK_PERCENTAGE = 1000; // 10% maximum cashback
    uint256 public constant WITHDRAWAL_TAX_PERCENTAGE = 2000; // 20% tax on normal withdrawals

    // Batch tracking variables
    uint256 public currentBatchDay; // Global counter for batch days
    uint256 public lastBatchTimestamp; // Last time a full batch cycle was completed
    uint256 public constant BATCH_SIZE = 100; // Process 100 subscriptions at once
    uint256 public constant PROCESSING_INTERVAL = 1 days; // 24 hours between processing batches
    mapping(uint256 => bool) public batchProcessed; // Tracks which batches have been processed for the current batch day
    uint256 public totalBatches; // Total number of batches needed to process all subscribers

    // Subscription-related state variables
    struct Subscription {
        uint256 ticketsPerDay; // How many tickets to buy each day
        uint256 daysRemaining; // Number of days left in subscription
        uint256 lastProcessedBatchDay; // Last batch day this subscription was processed
        bool isActive; // Whether the subscription is active
    }

    mapping(address => Subscription) public subscriptions;
    address[] public subscribers; // List of all subscribers for batch processing

    // Events
    event TicketPurchased(address indexed user, uint256 amount, uint256 cashbackAmount);
    event ReferrerUpdated(address indexed newReferrer);
    event ImmediateCashbackPercentageUpdated(uint256 newPercentage);
    event SubscriptionCashbackPercentageUpdated(uint256 newPercentage);
    event FundsDeposited(address indexed from, uint256 amount);
    event CashbackFailed(address indexed user, uint256 amount, string reason);
    event RefundPartiallyCompleted(address indexed user, uint256 requestedAmount, uint256 actualRefund);

    // Subscription events
    event SubscriptionCreated(address indexed user, uint256 ticketsPerDay, uint256 daysCount, uint256 totalCost);
    event SubscriptionProcessed(address indexed user, uint256 ticketsProcessed, uint256 daysRemaining);
    event SubscriptionCancelled(address indexed user, uint256 refundAmount, uint256 taxAmount);
    event ReferrerTaxPaid(address indexed referrer, address indexed user, uint256 taxAmount);
    event BatchProcessed(uint256 batchIndex, uint256 processedCount);
    event BatchDayCompleted(uint256 batchDay, uint256 timestamp);
    event SubscriptionUpgraded(
        address indexed user, uint256 newTicketsPerDay, uint256 newDaysRemaining, uint256 additionalCost
    );

    /**
     * @dev Constructor sets initial contract parameters
     * @param _jackpotContract Address of the BaseJackpot contract
     * @param _token Address of the USDC or other ERC20 token used
     * @param _referrer Address to receive referral fees
     * @param _cashbackPercentage Initial cashback percentage in basis points
     */
    constructor(address _jackpotContract, address _token, address _referrer, uint256 _cashbackPercentage)
        Ownable(msg.sender)
    {
        require(_jackpotContract != address(0), "Invalid jackpot contract address");
        require(_token != address(0), "Invalid token address");
        require(_referrer != address(0), "Invalid referrer address");
        require(_cashbackPercentage <= MAX_CASHBACK_PERCENTAGE, "Cashback percentage too high");

        jackpotContract = IBaseJackpot(_jackpotContract);
        token = IERC20(_token);
        referrer = _referrer;
        immediatePurchaseCashbackPercentage = _cashbackPercentage;
        subscriptionCashbackPercentage = _cashbackPercentage; // Initially set to same value, can be changed later
        
        // Initialize batch day tracking
        currentBatchDay = 1;
        lastBatchTimestamp = block.timestamp;
    }

    /**
     * @dev Allows users to purchase tickets with automatic cashback
     * @param amount Amount of tokens to spend on tickets
     */
    function purchaseTicketsWithCashback(uint256 amount) external nonReentrant whenNotPaused {
        uint256 ticketCost = jackpotContract.ticketPrice();
        require(amount >= ticketCost, "Amount below ticket price");

        // Calculate cashback amount for immediate purchases
        uint256 cashbackAmount = (amount * immediatePurchaseCashbackPercentage) / 10000;

        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Approve jackpot contract to spend tokens
        token.approve(address(jackpotContract), amount);

        // Purchase tickets on behalf of the user
        jackpotContract.purchaseTickets(referrer, amount, msg.sender);

        // Try to send cashback to user if contract has funds
        uint256 actualCashback = 0;
        if (cashbackAmount > 0) {
            uint256 contractBalance = token.balanceOf(address(this));

            if (contractBalance >= cashbackAmount) {
                token.safeTransfer(msg.sender, cashbackAmount);
                actualCashback = cashbackAmount;
            } else if (contractBalance > 0) {
                // Send partial cashback if possible
                token.safeTransfer(msg.sender, contractBalance);
                actualCashback = contractBalance;
                emit CashbackFailed(
                    msg.sender, cashbackAmount - contractBalance, "Partial cashback - insufficient funds"
                );
            } else {
                emit CashbackFailed(msg.sender, cashbackAmount, "No cashback - insufficient funds");
            }
        }

        emit TicketPurchased(msg.sender, amount, actualCashback);
    }

    /**
     * @dev Creates a subscription for daily ticket purchases or redirects to upgrade if one exists
     * @param ticketsPerDay Number of tickets to purchase each day
     * @param daysCount Number of days to maintain the subscription
     * @notice If user already has a subscription, this automatically upgrades it (must have same or more tickets)
     * @notice Tickets are now only purchased through batch processing, not immediately
     */
    function createSubscription(uint256 ticketsPerDay, uint256 daysCount) external nonReentrant whenNotPaused {
        require(ticketsPerDay > 0, "Must purchase at least 1 ticket per day");
        require(daysCount > 0, "Subscription must be at least 1 day");

        // Check if user already has an active subscription
        if (hasActiveSubscription(msg.sender)) {
            // If they do, call the upgrade function
            _upgradeSubscription(ticketsPerDay, daysCount);
            return;
        }

        uint256 ticketPrice = jackpotContract.ticketPrice();
        uint256 totalCost = ticketPrice * ticketsPerDay * daysCount;

        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), totalCost);

        // Add user to subscribers list if not already there
        bool alreadySubscribed = false;
        for (uint256 i = 0; i < subscribers.length; i++) {
            if (subscribers[i] == msg.sender) {
                alreadySubscribed = true;
                break;
            }
        }

        if (!alreadySubscribed) {
            subscribers.push(msg.sender);
            // Update total batches
            totalBatches = (subscribers.length + BATCH_SIZE - 1) / BATCH_SIZE;
        }

        // Create subscription with full days - no immediate purchase
        // Set lastProcessedBatchDay to one before current batch day so it will be processed in next batch
        subscriptions[msg.sender] = Subscription({
            ticketsPerDay: ticketsPerDay,
            daysRemaining: daysCount,
            lastProcessedBatchDay: currentBatchDay > 0 ? currentBatchDay - 1 : 0, // Handle case when currentBatchDay is 0
            isActive: true
        });

        emit SubscriptionCreated(msg.sender, ticketsPerDay, daysCount, totalCost);
    }

    /**
     * @dev Upgrades an existing subscription by merging in new parameters
     * @param newTicketsPerDay New number of tickets to purchase each day
     * @param additionalDays Additional days to add to the subscription
     */
    function upgradeSubscription(uint256 newTicketsPerDay, uint256 additionalDays)
        external
        nonReentrant
        whenNotPaused
    {
        require(hasActiveSubscription(msg.sender), "No active subscription");
        require(newTicketsPerDay > 0, "Must purchase at least 1 ticket per day");
        require(additionalDays > 0, "Must add at least 1 day");
        require(newTicketsPerDay >= subscriptions[msg.sender].ticketsPerDay, "Cannot downgrade tickets per day");

        _upgradeSubscription(newTicketsPerDay, additionalDays);
    }

    /**
     * @dev Internal function to handle subscription upgrades
     * @param newTicketsPerDay New number of tickets to purchase each day
     * @param additionalDays Additional days to add to the subscription
     */
    function _upgradeSubscription(uint256 newTicketsPerDay, uint256 additionalDays) internal {
        Subscription storage sub = subscriptions[msg.sender];

        // Prevent downgrades - new tickets must be at least as many as current
        require(newTicketsPerDay >= sub.ticketsPerDay, "Cannot downgrade tickets per day");

        uint256 ticketPrice = jackpotContract.ticketPrice();

        // Calculate remaining value in current subscription
        uint256 currentValue = sub.daysRemaining * sub.ticketsPerDay * ticketPrice;

        // Calculate value of the new configuration
        uint256 totalDays = sub.daysRemaining + additionalDays;
        uint256 newValue = totalDays * newTicketsPerDay * ticketPrice;

        // Calculate additional cost
        uint256 additionalCost = 0;
        if (newValue > currentValue) {
            additionalCost = newValue - currentValue;

            // Transfer additional tokens from user to this contract
            token.safeTransferFrom(msg.sender, address(this), additionalCost);
        }

        // Update subscription
        sub.ticketsPerDay = newTicketsPerDay;
        sub.daysRemaining = totalDays;

        emit SubscriptionUpgraded(msg.sender, newTicketsPerDay, totalDays, additionalCost);
    }

    /**
     * @dev Processes a batch of subscriptions
     * @param batchIndex Index of the batch to process
     */
    function processDailyBatch(uint256 batchIndex) external nonReentrant whenNotPaused {
        // Ensure processing interval has passed if we're starting a new batch day
        if (batchIndex == 0 && !allBatchesProcessed()) {
            require(block.timestamp >= lastBatchTimestamp + PROCESSING_INTERVAL, "Processing too soon");
        }

        // Calculate batch boundaries
        uint256 startIndex = batchIndex * BATCH_SIZE;
        uint256 endIndex = startIndex + BATCH_SIZE;

        // Make sure endIndex doesn't exceed array length
        if (endIndex > subscribers.length) {
            endIndex = subscribers.length;
        }

        // Ensure batch is valid
        require(startIndex < subscribers.length, "Batch index out of range");
        
        // Check if this batch has already been processed for the current batch day
        require(!batchProcessed[batchIndex], "Batch already processed for current day");

        // Mark this batch as processed for the current day
        batchProcessed[batchIndex] = true;
        
        uint256 processedCount = 0;
        
        // Approve maximum possible amount first (type(uint256).max)
        token.approve(address(jackpotContract), type(uint256).max);

        // Process subscriptions in this batch
        for (uint256 i = startIndex; i < endIndex; i++) {
            address subscriber = subscribers[i];
            Subscription storage sub = subscriptions[subscriber];

            // Check if subscription is active and hasn't been processed in the current batch day
            if (sub.isActive && sub.daysRemaining > 0 && sub.lastProcessedBatchDay < currentBatchDay) {
                // Calculate amount to spend today
                uint256 ticketPrice = jackpotContract.ticketPrice();
                uint256 amountToSpend = ticketPrice * sub.ticketsPerDay;

                // Calculate cashback for subscription processing
                uint256 cashbackAmount = (amountToSpend * subscriptionCashbackPercentage) / 10000;

                // Purchase tickets for the user (using already approved tokens)
                jackpotContract.purchaseTickets(referrer, amountToSpend, subscriber);

                // Try to send cashback to user, but don't fail if there are insufficient funds
                if (cashbackAmount > 0) {
                    uint256 contractBalance = token.balanceOf(address(this));

                    if (contractBalance >= cashbackAmount) {
                        token.safeTransfer(subscriber, cashbackAmount);
                    } else if (contractBalance > 0) {
                        // Send partial cashback if possible
                        token.safeTransfer(subscriber, contractBalance);
                        emit CashbackFailed(
                            subscriber, cashbackAmount - contractBalance, "Partial cashback - insufficient funds"
                        );
                    } else {
                        emit CashbackFailed(subscriber, cashbackAmount, "No cashback - insufficient funds");
                    }
                }

                // Update subscription
                sub.lastProcessedBatchDay = currentBatchDay;
                sub.daysRemaining--;

                emit SubscriptionProcessed(subscriber, sub.ticketsPerDay, sub.daysRemaining);
                processedCount++;

                // Remove subscription if days remaining is 0
                if (sub.daysRemaining == 0) {
                    sub.isActive = false;
                    // We don't remove from the subscribers array here to avoid messing up batch iteration
                }
            }
        }
        
        // Reset approval to 0 for security
        token.approve(address(jackpotContract), 0);

        emit BatchProcessed(batchIndex, processedCount);

        // Check if all batches have been processed
        if (allBatchesProcessed()) {
            // Increment the batch day counter
            currentBatchDay++;
            
            // Reset all batch processed flags for the new batch day
            for (uint256 i = 0; i < totalBatches; i++) {
                batchProcessed[i] = false;
            }
            
            // Update last batch timestamp
            lastBatchTimestamp = block.timestamp;
            
            // Emit event for batch day completion
            emit BatchDayCompleted(currentBatchDay - 1, block.timestamp);
            
            // Clean up subscribers list (remove inactive subscriptions)
            cleanupInactiveSubscribers();
        }
    }

    /**
     * @dev Checks if all batches have been processed for the current batch day
     * @return Whether all batches have been processed
     */
    function allBatchesProcessed() public view returns (bool) {
        for (uint256 i = 0; i < totalBatches; i++) {
            // Skip empty batches
            uint256 startIndex = i * BATCH_SIZE;
            if (startIndex >= subscribers.length) {
                continue;
            }
            
            // If any batch is not processed, return false
            if (!batchProcessed[i]) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Returns the number of batches needed to process all subscribers
     * @return Number of batches
     */
    function getNumberOfBatches() public view returns (uint256) {
        return totalBatches;
    }

    /**
     * @dev Allows users to cancel their subscription and get a refund for remaining days
     * @notice If the contract is NOT paused, a 20% tax will be applied to the refund amount and sent to the referrer
     * @notice If the contract is paused, no tax will be applied (emergency withdrawals)
     * @notice If there are insufficient funds, the user may receive a partial refund
     */
    function cancelSubscription() external nonReentrant {
        Subscription storage sub = subscriptions[msg.sender];
        require(sub.isActive, "No active subscription");
        require(sub.daysRemaining > 0, "No days remaining");

        // Calculate refund amount
        uint256 ticketPrice = jackpotContract.ticketPrice();
        uint256 totalAmount = ticketPrice * sub.ticketsPerDay * sub.daysRemaining;
        uint256 refundAmount = totalAmount;
        uint256 taxAmount = 0;

        // Apply tax if contract is NOT paused (normal operation)
        if (!paused()) {
            taxAmount = (totalAmount * WITHDRAWAL_TAX_PERCENTAGE) / 10000;
            refundAmount = totalAmount - taxAmount;
        }

        // Mark subscription as inactive
        sub.isActive = false;

        // Check contract balance
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 actualRefund = 0;
        uint256 actualTax = 0;

        // Determine how to allocate the available funds
        if (contractBalance >= totalAmount) {
            // Full refund and tax possible
            token.safeTransfer(msg.sender, refundAmount);
            actualRefund = refundAmount;

            // Send tax to referrer if applicable
            if (taxAmount > 0) {
                token.safeTransfer(referrer, taxAmount);
                actualTax = taxAmount;
                emit ReferrerTaxPaid(referrer, msg.sender, taxAmount);
            }
        } else if (contractBalance > 0) {
            // Partial funds available - prioritize user refund
            if (contractBalance >= refundAmount) {
                // Can pay full refund to user, partial or no tax to referrer
                token.safeTransfer(msg.sender, refundAmount);
                actualRefund = refundAmount;

                uint256 remainingForTax = contractBalance - refundAmount;
                if (remainingForTax > 0) {
                    token.safeTransfer(referrer, remainingForTax);
                    actualTax = remainingForTax;
                    emit ReferrerTaxPaid(referrer, msg.sender, remainingForTax);
                }
            } else {
                // Can only pay partial refund to user, nothing to referrer
                token.safeTransfer(msg.sender, contractBalance);
                actualRefund = contractBalance;
            }

            // Emit event for partial completion
            emit RefundPartiallyCompleted(msg.sender, refundAmount, actualRefund);
        } else {
            // No funds available
            emit RefundPartiallyCompleted(msg.sender, refundAmount, 0);
        }

        emit SubscriptionCancelled(msg.sender, actualRefund, actualTax);
    }

    /**
     * @dev Checks if a user has an active subscription
     * @param user Address to check
     * @return Whether the user has an active subscription
     */
    function hasActiveSubscription(address user) public view returns (bool) {
        return subscriptions[user].isActive;
    }

    /**
     * @dev Returns the subscription details for a user
     * @param user Address to check
     * @return ticketsPerDay Number of tickets purchased daily
     * @return daysRemaining Days left in the subscription
     * @return lastProcessedBatchDay Last batch day the subscription was processed
     * @return isActive Whether the subscription is active
     */
    function getSubscription(address user)
        external
        view
        returns (uint256 ticketsPerDay, uint256 daysRemaining, uint256 lastProcessedBatchDay, bool isActive)
    {
        Subscription storage sub = subscriptions[user];
        return (sub.ticketsPerDay, sub.daysRemaining, sub.lastProcessedBatchDay, sub.isActive);
    }

    /**
     * @dev Returns the total number of active subscribers
     * @return Number of subscribers
     */
    function getSubscriberCount() external view returns (uint256) {
        return subscribers.length;
    }

    /**
     * @dev Cleans up inactive subscribers from the subscribers array
     */
    function cleanupInactiveSubscribers() internal {
        uint256 i = 0;
        while (i < subscribers.length) {
            address subscriber = subscribers[i];

            if (!subscriptions[subscriber].isActive) {
                // Replace this element with the last one and then pop the array
                subscribers[i] = subscribers[subscribers.length - 1];
                subscribers.pop();
                // Don't increment i as we now have a new element at position i
            } else {
                i++;
            }
        }
        
        // Update total batches after cleanup
        totalBatches = (subscribers.length + BATCH_SIZE - 1) / BATCH_SIZE;
    }

    /**
     * @dev Updates the referrer address
     * @param _newReferrer New referrer address
     */
    function setReferrer(address _newReferrer) external onlyOwner {
        require(_newReferrer != address(0), "Invalid referrer address");
        referrer = _newReferrer;
        emit ReferrerUpdated(_newReferrer);
    }

    /**
     * @dev Updates the immediate purchase cashback percentage
     * @param _newPercentage New cashback percentage in basis points
     */
    function setImmediatePurchaseCashbackPercentage(uint256 _newPercentage) external onlyOwner {
        require(_newPercentage <= MAX_CASHBACK_PERCENTAGE, "Cashback percentage too high");
        immediatePurchaseCashbackPercentage = _newPercentage;
        emit ImmediateCashbackPercentageUpdated(_newPercentage);
    }

    /**
     * @dev Updates the subscription cashback percentage
     * @param _newPercentage New cashback percentage in basis points
     */
    function setSubscriptionCashbackPercentage(uint256 _newPercentage) external onlyOwner {
        require(_newPercentage <= MAX_CASHBACK_PERCENTAGE, "Cashback percentage too high");
        subscriptionCashbackPercentage = _newPercentage;
        emit SubscriptionCashbackPercentageUpdated(_newPercentage);
    }

    /**
     * @dev Deposits tokens into the contract to fund cashbacks
     * @param amount Amount of tokens to deposit
     */
    function fundCashback(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit FundsDeposited(msg.sender, amount);
    }

    /**
     * @dev Pauses contract functions
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses contract functions
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Calculates the amount of tokens needed to create a subscription
     * @param ticketsPerDay Number of tickets to purchase each day
     * @param daysCount Number of days to maintain the subscription
     * @return requiredAmount Total amount of tokens needed
     */
    function calculateSubscriptionCost(uint256 ticketsPerDay, uint256 daysCount) external view returns (uint256 requiredAmount) {
        uint256 ticketPrice = jackpotContract.ticketPrice();
        return ticketPrice * ticketsPerDay * daysCount;
    }

    /**
     * @dev Calculates the amount of tokens needed to upgrade an existing subscription
     * @param newTicketsPerDay New number of tickets to purchase each day
     * @param additionalDays Additional days to add to the subscription
     * @return additionalCost Additional amount of tokens needed (0 if no additional cost)
     */
    function calculateUpgradeCost(address subscriber, uint256 newTicketsPerDay, uint256 additionalDays) external view returns (uint256 additionalCost) {
        require(hasActiveSubscription(subscriber), "No active subscription");
        
        Subscription storage sub = subscriptions[subscriber];
        uint256 ticketPrice = jackpotContract.ticketPrice();
        
        // Calculate remaining value in current subscription
        uint256 currentValue = sub.daysRemaining * sub.ticketsPerDay * ticketPrice;
        
        // Calculate value of the new configuration
        uint256 totalDays = sub.daysRemaining + additionalDays;
        uint256 newValue = totalDays * newTicketsPerDay * ticketPrice;
        
        // Calculate additional cost
        if (newValue > currentValue) {
            return newValue - currentValue;
        }
        return 0;
    }
}