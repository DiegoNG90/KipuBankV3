// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployKipuBankV3 is Script {
    function run() external returns (KipuBankV3) {
        KipuBankV3 kipuBank;
        uint256 _bankCap = 1_000_000 * 1e6; // 1M USD
        uint256 _maxWithdrawal = 10_000 * 1e6; // 10k USD
        address _router = address(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3); // UniswapV2Router02 on Sepolia
        IERC20 _usdc = IERC20(0x1C7d4B196Cb0C7B01D743fbc6116A902379C7A9c); // USDC on Ethereum Sepolia
        uint256 _slippageToleranceBps = 50; // 0.5%

        uint256 deployerKey = vm.envUint("SEPOLIA_USER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        
        kipuBank = new KipuBankV3(_bankCap, _maxWithdrawal, _router, _usdc, _slippageToleranceBps);
        
        vm.stopBroadcast();
        return kipuBank; 
    }
}
