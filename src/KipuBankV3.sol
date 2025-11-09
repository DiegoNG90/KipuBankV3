// SPDX-License-Identifier: MIT
pragma solidity > 0.8.0;

import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


/*
    @title KipuBank V3 Smart Contract
    @author DiegoNG90 
    @notice This contract accepts deposits of ETH or any ERC20 token (with Uniswap V2 pair),
    converts them to USDC, and credits them to the user's balance, respecting a global BANKCAP.
    Also allows withdrawals of USDC up to a per-transaction limit.
    @dev version 3.0.0
*/

contract KipuBankV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Uniswap V2 Router interface instance.
    IUniswapV2Router02 public immutable ROUTER;
    /// @notice WETH (Wrapped ETH) token address.
    address public immutable WETH;
    /*
        @notice balances is a nested mapping for internal accounting.
        @dev The structure is `balances[userAddress][tokenAddress]`.
        @dev In V3, all deposits are credited to `balances[user][address(USDC)]`.
        Will no longer use address(0) to store ETH.
    */
    mapping(address => mapping(address => uint256)) public balances;
    /*
        @notice USDC reference to the deployed USDC ERC-20 token contract.
        @notice USDC is still the reference token and the only one we store.
        @dev This variable is set upon deployment (`immutable`) and cannot be changed. USDC (with 6 decimals) is the only ERC-20 token supported and serves as the standard
        for all internal USD accounting.
    */
    IERC20 public immutable USDC;
    /*
        @notice MAXIMUM_WITHDRAWAL_IN_USD is the maximum value, denominated in USD (6 decimals), that can be withdrawn in a single transaction.
        @dev This value is set at deployment time (`immutable`) and enforced across both ETH and ERC-20 token withdrawals.
    */
    uint256 public immutable MAXIMUM_WITHDRAWAL_IN_USD;
    /*
        @notice BANKCAP is the absolute maximum global deposit limit for the KipuBank contract, denominated in USD (6 decimals).
        @dev This immutable ceiling prevents excessive accumulation of funds and is enforced by comparing the incoming USD value against `totalDepositsInUSD`.
     */
    uint256 public immutable BANKCAP;
    /*
        @notice Slippage tolerance in Basis Points (BPS)
        @dev 50 BPS = 0.5%
    */
    uint256 public immutable SLIPPAGE_TOLERANCE_BPS;
    /*
        @notice totalDepositsInUSD tracks the current total value of all deposits held by the contract, denominated in USD (6 decimals).
        @dev Public visibility allows users to calculate remaining deposit capacity against the `BANKCAP`. This value is updated after every successful deposit and withdrawal.
    */
    uint256 public totalDepositsInUSD;
    /// @notice totalDepositOperations variable is a counter for the total number of successful deposit operations that have occurred.
    uint256 public totalDepositOperations;
    /// @notice totalWithdrawalsOperations variable is a Counter for the total number of successful withdrawal operations that have occurred.  
    uint256 public totalWithdrawalsOperations;

    /*
        @notice FeedSet is event that fires when an Oracle has been set succesfully.  
        @params _address address type input, _time uint256 type input
    */
    event FeedSet(address indexed _address, uint256 _time);
    /*
        @notice SuccessfulEtherWithdrawal is an event that fires when a ETH withdrawal has been made succesfully.  
        @params _sender address type input, _amount uint256 type input 
    */
    event SuccessfulEtherWithdrawal(address indexed _sender, uint256 _amount);
    /*
        @notice SuccessfulTokenWithdrawal is an event that fires when a TOKEN withdrawal has been made succesfully.  
        @params _sender address type input, _tokenAddress address type input, _amount uint256 type input
    */
    event SuccessfulTokenWithdrawal(address indexed _sender, address indexed _tokenAddress, uint256 _amount);
    /*
        @notice SuccessfulEtherDeposit is an event that fires when a ETH deposit has been made succesfully.  
        @params _sender address type input, _deposit uint256 type input
    */
    event SuccessfulEtherDeposit(address _sender, uint256 _deposit);
    /*
        @notice SuccessfulTokenDeposit is an event that fires when a TOKEN deposit has been made succesfully.  
        @params _sender address type input, _tokenAddress address type input, _amount uint256 type input
    */
    event SuccessfulTokenDeposit(address _sender, address _tokenAddress, uint256 _amount);
        
    
    
    /// @notice InvalidAmount is a custom error that tells KipuBank user that indicates an invalid input amount.
    error InvalidAmount(); 
    /// @notice InsufficientBalance is a custom error that indicates the user has no balance to withdraw from.
    error InsufficientBalance();
    /*
        @notice WithdrawalAmountTooHigh is a custom error that indicates that the requested withdrawal amount has exceeded the per-transaction limit
        defined by `MAXIMUM_WITHDRAWAL_IN_USD`.
    */
    error WithdrawalAmountTooHigh();
    /// @notice BankCapReached is a custom error that indicates the deposit amount would cause the total contract holdings to exceed the global limit (`BANKCAP`).
    error BankCapReached(); 
    /*
        @notice FailureWithdrawal is a custom error that indicates a failure during the native ETH transfer.  
        @params _error bytes type input
    */
    error FailureWithdrawal(bytes _error);
    /// @notice TokenTransferFailed is a custom error that indicates a failure during the external ERC-20 token transfer (transfer/transferFrom). 
    error TokenTransferFailed();
    /* 
        @notice TokenNotSupported is a custom error that indicates that the token address provided is not the supported USDC token.  
        @params _tokenAddress address type input
    */
    error TokenNotSupported(address _tokenAddress);
    /// @notice InvalidContract is a custom error that indicates an invalid contract configuration during deployment or administration.
    error InvalidContract();
    
    // --- NUEVO ERROR V3 ---
    /// @notice SwapFailed is a custom error that indicates a failure during the token swap process via Uniswap V2.
    error SwapFailed();
    /*
        @notice TokenSwapNotSupported is a custom error that indicates the deposited token cannot be swapped to USDC due to lack of liquidity or unsupported pair.
        @params _token address type input
    */
    error TokenSwapNotSupported(address _token);


    /*
        @notice El constructor inicializa el V3.
        @param _bankCap Límite total en USD (6 decimales).
        @param _maxWithdrawalInUSD Límite de retiro por tx en USD (6 decimales).
        @param _router La dirección del Router V2 de Uniswap.
        @param _usdcToken La dirección del token USDC.
    */
    /*
        @notice the constructor function initializes the contract, setting immutable limits (BANKCAP, MAX_WITHDRAWAL_IN_USD), external dependencies (ROUTER) and an IERC20 (USDC).
        The deployer is automatically set as the contract owner (`Ownable(msg.sender)`).
        @param _bankCap uint256 input type is the absolute maximum total deposit limit, denominated in USD (6 decimals).
        @param _maxWithdrawalInUSD uint256 input type is the maximum value a user can withdraw per transaction, denominated in USD (6 decimals).
        @param _router address input type is the address of the Uniswap V2 Router contract.
        @param _usdcToken IERC20 (address) input type is the address of the supported USDC ERC-20 token contract.
        @dev The constructor enforces non-zero addresses for external contracts and initializes the `BANKCAP`, `MAXIMUM_WITHDRAWAL_IN_USD`, `ROUTER` and `USDC` immutables variables.
    */
    constructor(
        uint256 _bankCap,
        uint256 _maxWithdrawalInUSD,
        address _router, 
        IERC20 _usdcToken,
        uint256 _slippageToleranceBps
    ) Ownable(msg.sender) {
        if (_router == address(0) || address(_usdcToken) == address(0)) revert InvalidContract();
        if (_slippageToleranceBps > 10000) revert InvalidAmount();

        BANKCAP = _bankCap;
        MAXIMUM_WITHDRAWAL_IN_USD = _maxWithdrawalInUSD;
        USDC = _usdcToken;
        ROUTER = IUniswapV2Router02(_router);
        WETH = ROUTER.WETH();
        SLIPPAGE_TOLERANCE_BPS = _slippageToleranceBps;
    }

    /*
        @notice Allows reception of native Ether (ETH) sent without specifying a function.
        @dev Forwards execution to `depositEther()` to enforce security checks (BANKCAP, oracle conversion) and correct accounting via the multi-token mapping.
    */
    receive() external payable {
        depositEther();
    }


    /*
        @notice depositToken function allows depositing ANY ERC20 token.
        @dev The deposited token is swapped to USDC via Uniswap V2 and credited to the user's balance.
        If token is USDC, it is credited directly.
        Otherwise, the token is moved to this contract, the ROUTER allowance is validated, then swapped the token to USDC, and credited to the user's internal balance.
        @param _tokenAddress address input type is the address of the token to deposit.
        @param _amount uint256 input type is the amount of the token to deposit (in its native decimals).
    */
    function depositToken(address _tokenAddress, uint256 _amount) external {
        if (_amount <= 0) revert InvalidAmount();

        uint256 usdcToCredit;

        if (_tokenAddress == address(USDC)) {
            if (totalDepositsInUSD + _amount > BANKCAP) revert BankCapReached();
            
            USDC.safeTransferFrom(msg.sender, address(this), _amount);
            
            usdcToCredit = _amount;
        } else {
            uint256 estimatedUsdc = _previewSwap(_tokenAddress, _amount);
            if (totalDepositsInUSD + estimatedUsdc > BANKCAP) revert BankCapReached();

            IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);

            if (IERC20(_tokenAddress).allowance(address(this), address(ROUTER)) < _amount) {
                IERC20(_tokenAddress).safeIncreaseAllowance(address(ROUTER), type(uint256).max);
            }

            uint256 amountOutMin = _calculateAmountOutMin(estimatedUsdc);
            address[] memory path = _getPath(_tokenAddress);

            uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
                _amount,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            );
            
            usdcToCredit = amounts[amounts.length - 1];
            if (usdcToCredit < amountOutMin) revert SwapFailed();
        }

        _incrementDepositsOperations();
        _incrementDepositsInUSD(usdcToCredit);
        balances[msg.sender][address(USDC)] += usdcToCredit;

        emit SuccessfulTokenDeposit(msg.sender, _tokenAddress, _amount);

    }


    /*
        @notice withdrawToken function processes a USDC withdrawal (the only token stored).
        @param _tokenAddress address input type must be the USDC address.
        @param _amount uint256 input type is the USDC amount to withdraw (6 decimals).
        @dev This function adheres to the Checks-Effects-Interactions (CEI) pattern
        by updating internal balances *before* initiating the external token transfer.
        It also uses the `nonReentrant` modifier as a defense-in-depth measure
        against any potential reentrancy vectors.
    */
    function withdrawToken(address _tokenAddress, uint256 _amount) external nonReentrant {
        if(_tokenAddress != address(USDC)) revert TokenNotSupported(_tokenAddress);
        
        uint256 userBalance = balances[msg.sender][_tokenAddress];
        if (userBalance == 0 || _amount > userBalance) revert InsufficientBalance();
        if (_amount <= 0) revert InvalidAmount();
        if (_amount > MAXIMUM_WITHDRAWAL_IN_USD) revert WithdrawalAmountTooHigh();

        unchecked {
            balances[msg.sender][_tokenAddress] = userBalance - _amount;
        }
        _decrementDepositsInUSD(_amount);
        _incrementWithdrawalsOperations();

        USDC.safeTransfer(msg.sender, _amount);

        emit SuccessfulTokenWithdrawal(msg.sender, _tokenAddress, _amount);
    }


    /*
        @notice depositEther allows a user to deposit native Ether (ETH).
        @dev The received ETH is automatically swapped to USDC via Uniswap V2 using the contract's predefined slippage tolerance.
        The resulting USDC is credited to the user's internal balance. This function is payable and triggered by `receive()`.
    */
    function depositEther() public payable {
        if (msg.value <= 0) revert InvalidAmount();

        uint256 estimatedUsdc = _previewSwap(WETH, msg.value);

        if (totalDepositsInUSD + estimatedUsdc > BANKCAP) revert BankCapReached();

        uint256 amountOutMin = _calculateAmountOutMin(estimatedUsdc);
        address[] memory path = _getPath(WETH);

        uint256[] memory amounts = ROUTER.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            address(this), // IMPORTANT: KipuBank (this contract) receives the USDC
            block.timestamp
        );

        uint256 usdcReceived = amounts[amounts.length - 1];

        if (usdcReceived < amountOutMin) revert SwapFailed();

        _incrementDepositsOperations();
        _incrementDepositsInUSD(usdcReceived);
        balances[msg.sender][address(USDC)] += usdcReceived;

        emit SuccessfulEtherDeposit(msg.sender, msg.value);
    }

    /*
        @notice incrementWithdrawalsOperations function handles the totalWithdrawalsOperations counter increase.
        @dev Implemented with 'unchecked' block to bypass default Solidity >= 0.8.0 overflow checks. This is a safe gas optimization, 
        as 'totalWithdrawalsOperations' is a simple uint256 counter, making overflow virtually impossible to reach in practice.
    */
    function _incrementWithdrawalsOperations() private {
        unchecked {
            ++totalWithdrawalsOperations;
        }
    }

    /* 
        @notice incrementDepositsOperations function handles the totalDepositOperations counter increase.
        @dev Implemented with 'unchecked' block to bypass default Solidity >= 0.8.0 overflow checks. This is a safe gas optimization, 
        as 'totalDepositOperations' is a simple uint256 counter, making overflow virtually impossible to reach in practice.
    */
    function _incrementDepositsOperations() private {
        unchecked {
            ++totalDepositOperations;
        }
    }

    /* 
        @notice incrementDepositsFunds function handles the totalDepositsInUSD increase.
        @params _amount uint256 input type is the amount to increment.
    */
    function _incrementDepositsInUSD(uint256 _amount) private {
        totalDepositsInUSD += _amount;
    }

    /*
        @notice decrementDepositsInUSD function handles the totalDepositsInUSD decrease.
        @params _amount uint256 input type is the amount to decrement.
    */
    function _decrementDepositsInUSD(uint256 _amount) private {
        totalDepositsInUSD -= _amount;
    }

    /*
        @notice _getPath is a helper function that constructs the swap path for Uniswap V2.
        @param tokenIn address input type is the address of the input token.
        @return path address[] memory output type is the array of addresses representing the swap path.
        @dev If the input token is WETH, the path is [WETH, USDC].
        Otherwise, the path is [tokenIn, WETH, USDC].
    */
    function _getPath(address tokenIn) private view returns (address[] memory path) {
        if (tokenIn == WETH) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = address(USDC);
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH;
            path[2] = address(USDC);
        }
        return path;
    }

    /*
        @notice _previewSwap is a helper function that previews the amount of USDC that would be received for a given input.
        @param tokenIn address input type is the address of the input token.
        @param amountIn uint256 input type is the amount of the input token.
        @return amountOut uint256 output type is the estimated amount of USDC that would be received.
        @dev Uses Uniswap V2's `getAmountsOut` to estimate the output amount.
    */
    function _previewSwap(address tokenIn, uint256 amountIn) private view returns (uint256 amountOut) {
        address[] memory path = _getPath(tokenIn);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        if (amounts.length < 2) revert TokenSwapNotSupported(tokenIn);
        return amounts[amounts.length - 1];
    }

    /*
        @notice Calculates the minimum output amount based on an estimated output and the contract's slippage tolerance.
        @dev Reads the immutable SLIPPAGE_TOLERANCE_BPS to determine the floor. 
        @param estimatedAmountOut uint256 input type is an estimated amount from `_previewSwap` (e.g., 100 USDC).
        @return The minimum amount to accept, accounting for slippage (e.g., 99.5 USDC).
    */
    function _calculateAmountOutMin(uint256 estimatedAmountOut) private view returns (uint256) {
        uint256 minPercentage = 10000 - SLIPPAGE_TOLERANCE_BPS;
        return (estimatedAmountOut * minPercentage) / 10000;
    }
}