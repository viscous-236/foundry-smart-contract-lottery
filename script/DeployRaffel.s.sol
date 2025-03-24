//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffel} from "src/Raffel.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffel is Script {
    function run() external {
        DeployContract();
    }

    function DeployContract() public returns (Raffel, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig
            .getConfig();

        if (networkConfig.subscriptionId == 0) {
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (
                networkConfig.subscriptionId,
                networkConfig.vrfCoordinator
            ) = createSubscription.createSubscription(
                networkConfig.vrfCoordinator,
                networkConfig.account
            );

            // fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                networkConfig.vrfCoordinator,
                networkConfig.subscriptionId,
                networkConfig.link,
                networkConfig.account
            );
        }

        vm.startBroadcast(networkConfig.account);
        Raffel raffel = new Raffel(
            networkConfig.entranceFee,
            networkConfig.intervalForLottery,
            networkConfig.vrfCoordinator,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffel),
            networkConfig.vrfCoordinator,
            networkConfig.subscriptionId,
            networkConfig.account
        );

        return (raffel, helperConfig);
    }
}
