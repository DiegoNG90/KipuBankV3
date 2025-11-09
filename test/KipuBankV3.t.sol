// test/KipuBankV3.t.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Se recomienda 0.8.20+ para scripts/tests

import "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol"; // Para logs útiles en los tests

contract KipuBankV3Test is Test {
    KipuBankV3 public kipuBank;

    address constant _WETH_ADDRESS = 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
    address constant _WHALE = 0x6a956f0AEd3b8625F20d696A5e934A5DE8C27A2C; 
    address constant _USER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; 

    uint256 constant _BANK_CAP = 1_000_000 * 1e6; // 1M USDC (6 decimals)
    uint256 constant _MAX_WITHDRAWAL = 10_000 * 1e6; // 10k USDC (6 decimals)
    address constant _ROUTER = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address constant _USDC_ADDRESS = 0xfC9201f4116aE6b054722E10b98D904829b469c3;
    uint256 constant _SLIPPAGE_TOLERANCE_BPS = 50; // 0.5%

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC"));
        
        kipuBank = new KipuBankV3(
            _BANK_CAP,
            _MAX_WITHDRAWAL,
            _ROUTER,
            IERC20(_USDC_ADDRESS),
            _SLIPPAGE_TOLERANCE_BPS
        );
        
        // 3. (Opcional pero útil) Mover fondos de ETH a WHALE para que pueda pagar el gas y ETH de depósito
        vm.deal(_WHALE, 10 ether); 
        vm.label(_WHALE, "WHALE (Funder)");
        vm.label(address(kipuBank), "KipuBankV3");
    }

    /*
        @notice testDepositUSDCSuccess tests the direct deposit of USDC (V2 functionality).
        @dev It verifies the happy path when the user's internal balance, the contract's token balance, and the total bank deposits are all correctly updated.
    */
    function testDepositUSDCSuccess() public {
        uint256 amountToDeposit = 1_000 * 1e6;
        
        vm.startPrank(_WHALE);

        IERC20(_USDC_ADDRESS).approve(address(kipuBank), amountToDeposit);

        kipuBank.depositToken(_USDC_ADDRESS, amountToDeposit);

        vm.stopPrank();

        assertEq(kipuBank.balances(_WHALE, _USDC_ADDRESS), amountToDeposit, "User internal balance mismatch");
        assertEq(IERC20(_USDC_ADDRESS).balanceOf(address(kipuBank)), amountToDeposit, "Contract USDC balance mismatch");
        assertEq(kipuBank.totalDepositsInUSD(), amountToDeposit, "Total bank deposits mismatch");
    }


    /*
        @notice testDepositEtherSwapsToUSDC tests the deposit of native ETH (V3 functionality).
        @dev It verifies the happy path when ETH is received, swapped to USDC,
        and the user's *USDC* internal balance is credited.
    */
    function testDepositEtherSwapsToUSDC() public {
        uint256 ethAmountIn = 1 ether;
        uint256 usdcBalanceBefore = kipuBank.balances(_WHALE, _USDC_ADDRESS);
        uint256 bankTotalBefore = kipuBank.totalDepositsInUSD();

        vm.startPrank(_WHALE);

        kipuBank.depositEther{value: ethAmountIn}();

        vm.stopPrank();

        uint256 usdcBalanceAfter = kipuBank.balances(_WHALE, _USDC_ADDRESS);
        uint256 bankTotalAfter = kipuBank.totalDepositsInUSD();
        
        assertGt(usdcBalanceAfter, usdcBalanceBefore, "User USDC balance should increase");
        assertGt(bankTotalAfter, bankTotalBefore, "Bank total deposits should increase");
        uint256 contractUSDC = IERC20(_USDC_ADDRESS).balanceOf(address(kipuBank));
        assertGt(contractUSDC, 0, "Contract should hold the swapped USDC");
        assertEq(address(kipuBank).balance, 0, "Contract should have 0 native ETH");
    }

    /*
        @notice testRevertWhenUSDCDepositExceedsCap tests that deposits (both USDC and ETH) fail if they
        would exceed the BANKCAP.
        @dev Deploys a new, local bank with a tiny cap for testing.
    */
    function testRevertWhenUSDCDepositExceedsCap() public {
        uint256 tinyCap = 100 * 1e6; 
        KipuBankV3 localBank = new KipuBankV3(
            tinyCap,
            _MAX_WITHDRAWAL,
            _ROUTER,
            IERC20(_USDC_ADDRESS),
            _SLIPPAGE_TOLERANCE_BPS
        );

        vm.startPrank(_WHALE);

        IERC20(_USDC_ADDRESS).approve(address(localBank), 200 * 1e6);
        
        vm.expectRevert();
        
        localBank.depositToken(_USDC_ADDRESS, 101 * 1e6);
        
        vm.stopPrank();
    }

    /*
        @notice testRevertWhenETHDepositExceedsCap tests that ETH deposits revert if they exceed the BANKCAP.
        @dev Deploys a new, local bank with a tiny cap for testing.
    */
    function testRevertWhenETHDepositExceedsCap() public {
        // 1. SETUP: Crear un banco con un cap de solo 50 USDC (50 * 10^6)
        // El valor real en decimales es 50,000,000
        uint256 tinyCap = 100_000; // 0.1 * 1e6
        KipuBankV3 localBank = new KipuBankV3(
            tinyCap,
            _MAX_WITHDRAWAL,
            _ROUTER,
            IERC20(_USDC_ADDRESS),
            _SLIPPAGE_TOLERANCE_BPS
        );

        vm.startPrank(_WHALE);
        
        vm.expectRevert();
        

        localBank.depositEther{value: 1 ether}();
        
        vm.stopPrank();
    }

    /*
        @notice Tests the happy path for withdrawing USDC.
        @dev 
        1. Deposits 1000 USDC.
        2. Withdraws 400 USDC.
        3. Verifies internal and external balances are correct.
    */
    function testWithdrawUSDCSuccess() public {
        uint256 amountToDeposit = 1_000 * 1e6;
        vm.startPrank(_WHALE);
        IERC20(_USDC_ADDRESS).approve(address(kipuBank), amountToDeposit);
        kipuBank.depositToken(_USDC_ADDRESS, amountToDeposit);
        vm.stopPrank();

        assertEq(kipuBank.balances(_WHALE, _USDC_ADDRESS), amountToDeposit);
        uint256 bankBalance_before = IERC20(_USDC_ADDRESS).balanceOf(address(kipuBank));
        uint256 whaleBalance_before = IERC20(_USDC_ADDRESS).balanceOf(_WHALE);

        uint256 amountToWithdraw = 400 * 1e6;
        vm.startPrank(_WHALE);
        
        kipuBank.withdrawToken(_USDC_ADDRESS, amountToWithdraw);
        
        vm.stopPrank();

        assertEq(kipuBank.balances(_WHALE, _USDC_ADDRESS), amountToDeposit - amountToWithdraw);
        
        assertEq(IERC20(_USDC_ADDRESS).balanceOf(address(kipuBank)), bankBalance_before - amountToWithdraw);
        
        assertEq(IERC20(_USDC_ADDRESS).balanceOf(_WHALE), whaleBalance_before + amountToWithdraw);
        
        assertEq(kipuBank.totalDepositsInUSD(), amountToDeposit - amountToWithdraw);
    }
    
}