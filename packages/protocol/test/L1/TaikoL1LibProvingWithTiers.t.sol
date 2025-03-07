// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TaikoL1TestBase.sol";

contract TaikoL1Tiers is TaikoL1 {
    function getConfig() public view override returns (TaikoData.Config memory config) {
        config = TaikoL1.getConfig();

        config.maxBlocksToVerifyPerProposal = 0;
        config.blockMaxProposals = 10;
        config.blockRingBufferSize = 12;
        config.livenessBond = 1e18; // 1 Taiko token
    }
}

contract Verifier {
    fallback(bytes calldata) external returns (bytes memory) {
        return bytes.concat(keccak256("taiko"));
    }
}

contract TaikoL1LibProvingWithTiers is TaikoL1TestBase {
    function deployTaikoL1() internal override returns (TaikoL1 taikoL1) {
        taikoL1 = TaikoL1(
            payable(deployProxy({ name: "taiko", impl: address(new TaikoL1Tiers()), data: "" }))
        );
    }

    function proveHigherTierProof(
        TaikoData.BlockMetadata memory meta,
        bytes32 parentHash,
        bytes32 stateRoot,
        bytes32 blockHash,
        uint16 minTier
    )
        internal
    {
        uint16 tierToProveWith;
        if (minTier == LibTiers.TIER_OPTIMISTIC) {
            tierToProveWith = LibTiers.TIER_SGX;
        } else if (minTier == LibTiers.TIER_SGX) {
            tierToProveWith = LibTiers.TIER_SGX_AND_PSE_ZKEVM;
        } else if (minTier == LibTiers.TIER_SGX_AND_PSE_ZKEVM) {
            tierToProveWith = LibTiers.TIER_GUARDIAN;
        }
        proveBlock(Carol, Carol, meta, parentHash, blockHash, stateRoot, tierToProveWith, "");
    }

    function test_L1_ContestingWithSameProof() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e6 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // blockhash:blockId
            proveBlock(Bob, Bob, meta, parentHash, blockHash, stateRoot, meta.minTier, "");

            // Try to contest - but should revert with L1_ALREADY_PROVED
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                meta.minTier,
                TaikoErrors.L1_ALREADY_PROVED.selector
            );

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ContestingWithDifferentButCorrectProof() external {
        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // stateRoot instead of blockHash
            uint16 minTier = meta.minTier;

            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, minTier, "");

            // Try to contest
            proveBlock(Carol, Carol, meta, parentHash, blockHash, stateRoot, minTier, "");

            vm.roll(block.number + 15 * 12);

            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            // Cannot verify block because it is contested..
            verifyBlock(Carol, 1);

            proveHigherTierProof(meta, parentHash, stateRoot, blockHash, minTier);

            vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);
            // Now can verify
            console2.log("Probalom verify-olni");
            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ContestingWithSgxProof() external {
        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // stateRoot instead of blockHash
            uint16 minTier = meta.minTier;
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, minTier, "");

            // Try to contest
            proveBlock(Carol, Carol, meta, parentHash, blockHash, stateRoot, minTier, "");

            vm.roll(block.number + 15 * 12);

            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            // Cannot verify block because it is contested..
            verifyBlock(Carol, 1);

            proveHigherTierProof(meta, parentHash, stateRoot, blockHash, minTier);

            // Otherwise just not contest
            vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);
            // Now can verify
            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ContestingWithDifferentButInCorrectProof() external {
        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // stateRoot instead of blockHash
            uint16 minTier = meta.minTier;

            proveBlock(Bob, Bob, meta, parentHash, blockHash, stateRoot, minTier, "");

            if (minTier == LibTiers.TIER_OPTIMISTIC) {
                // Try to contest
                proveBlock(Carol, Carol, meta, parentHash, stateRoot, stateRoot, minTier, "");

                vm.roll(block.number + 15 * 12);

                vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

                // Cannot verify block because it is contested..
                verifyBlock(Carol, 1);

                proveBlock(
                    Carol,
                    Carol,
                    meta,
                    parentHash,
                    blockHash,
                    stateRoot,
                    LibTiers.TIER_SGX_AND_PSE_ZKEVM,
                    ""
                );
            }

            // Otherwise just not contest
            vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);
            // Now can verify
            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ContestingWithInvalidBlockHash() external {
        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < 10; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // stateRoot instead of blockHash
            uint16 minTier = meta.minTier;
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, minTier, "");

            if (minTier == LibTiers.TIER_OPTIMISTIC) {
                // Try to contest
                proveBlock(Carol, Carol, meta, parentHash, blockHash, stateRoot, minTier, "");

                vm.roll(block.number + 15 * 12);

                vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);

                // Cannot verify block because it is contested..
                verifyBlock(Carol, 1);

                proveBlock(
                    Carol,
                    Carol,
                    meta,
                    parentHash,
                    0,
                    stateRoot,
                    LibTiers.TIER_SGX_AND_PSE_ZKEVM,
                    TaikoErrors.L1_INVALID_TRANSITION.selector
                );
            }

            // Otherwise just not contest
            vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);
            // Now can verify
            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_NonAsignedProverCannotBeFirstInProofWindowTime() external {
        giveEthAndTko(Alice, 1e8 ether, 100 ether);
        // This is a very weird test (code?) issue here.
        // If this line (or Bob's query balance) is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        console2.log("Alice balance:", tko.balanceOf(Alice));
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        giveEthAndTko(Carol, 1e8 ether, 100 ether);
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (uint256 blockId = 1; blockId < 10; blockId++) {
            //printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                meta.minTier,
                TaikoErrors.L1_NOT_ASSIGNED_PROVER.selector
            );
            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);
            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_asignedProverCannotProveAfterHisWindowElapsed() external {
        giveEthAndTko(Alice, 1e8 ether, 100 ether);
        // This is a very weird test (code?) issue here.
        // If this line (or Bob's query balance) is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        console2.log("Alice balance:", tko.balanceOf(Alice));
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        giveEthAndTko(Carol, 1e8 ether, 100 ether);
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (uint256 blockId = 1; blockId < 10; blockId++) {
            //printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            proveBlock(
                Bob,
                Bob,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                meta.minTier,
                TaikoErrors.L1_ASSIGNED_PROVER_NOT_ALLOWED.selector
            );

            verifyBlock(Carol, 1);
            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_GuardianProverCanAlwaysOverwriteTheProof() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e6 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // blockhash:blockId

            (, TaikoData.SlotB memory b) = L1.getStateVariables();
            uint64 lastVerifiedBlockBefore = b.lastVerifiedBlockId;
            proveBlock(Bob, Bob, meta, parentHash, blockHash, stateRoot, meta.minTier, "");
            console2.log("mintTier is:", meta.minTier);
            // Try to contest
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                bytes32(uint256(1)),
                bytes32(uint256(1)),
                meta.minTier,
                ""
            );
            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            (, b) = L1.getStateVariables();
            uint64 lastVerifiedBlockAfter = b.lastVerifiedBlockId;

            console.log(lastVerifiedBlockAfter, lastVerifiedBlockBefore);
            // So it is contested - because last verified not changd
            assertEq(lastVerifiedBlockAfter, lastVerifiedBlockBefore);

            // Guardian can prove with the original (good) hashes.
            proveBlock(
                Carol, Carol, meta, parentHash, blockHash, stateRoot, LibTiers.TIER_GUARDIAN, ""
            );

            vm.roll(block.number + 15 * 12);
            vm.warp(block.timestamp + L1.getTier(LibTiers.TIER_GUARDIAN).cooldownWindow + 1);

            verifyBlock(Carol, 1);
            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_GuardianProverFailsWithInvalidBlockHash() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e6 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // blockhash:blockId
            proveBlock(Bob, Bob, meta, parentHash, blockHash, stateRoot, meta.minTier, "");

            // Try to contest - but should revert with L1_ALREADY_PROVED
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                0,
                stateRoot,
                LibTiers.TIER_GUARDIAN,
                TaikoErrors.L1_INVALID_TRANSITION.selector
            );

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_GuardianProverCanOverwriteIfNotSameProof() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e7 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // blockhash:blockId
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, meta.minTier, "");

            // Prove as guardian
            proveBlock(
                Carol, Carol, meta, parentHash, blockHash, stateRoot, LibTiers.TIER_GUARDIAN, ""
            );

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_IfGuardianRoleIsNotGrantedToProver() external {
        registerAddress("guardian_prover", Alice);

        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < 10; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of
            // blockhash:blockId
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, meta.minTier, "");

            // Prove as guardian but in reality not a guardian
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                LibTiers.TIER_GUARDIAN,
                GuardianVerifier.PERMISSION_DENIED.selector
            );

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ProveWithInvalidBlockId() external {
        registerAddress("guardian_prover", Alice);

        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < 10; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);

            meta.id = 100;
            proveBlock(
                Carol,
                Carol,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                LibTiers.TIER_PSE_ZKEVM,
                TaikoErrors.L1_INVALID_BLOCK_ID.selector
            );

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ProveWithInvalidMetahash() external {
        registerAddress("guardian_prover", Alice);

        giveEthAndTko(Alice, 1e8 ether, 1000 ether);
        giveEthAndTko(Carol, 1e8 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e8 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < 10; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);

            // Mess up metahash
            meta.l1Height = 200;
            proveBlock(
                Bob,
                Bob,
                meta,
                parentHash,
                blockHash,
                stateRoot,
                LibTiers.TIER_PSE_ZKEVM,
                TaikoErrors.L1_BLOCK_MISMATCH.selector
            );

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_GuardianProofCannotBeOverwrittenByLowerTier() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are onsgoing with foundry team
        giveEthAndTko(Bob, 1e7 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of blockhash is
            // exchanged with stateRoot
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, meta.minTier, "");

            // Prove as guardian
            proveBlock(
                Carol, Carol, meta, parentHash, blockHash, stateRoot, LibTiers.TIER_GUARDIAN, ""
            );

            // Try to re-prove but reverts
            proveBlock(
                Bob,
                Bob,
                meta,
                parentHash,
                stateRoot,
                stateRoot,
                LibTiers.TIER_PSE_ZKEVM,
                TaikoErrors.L1_INVALID_TIER.selector
            );

            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_GuardianCanReturnBondIfBlockUnprovable() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e7 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        for (uint256 blockId = 1; blockId < conf.blockMaxProposals * 3; blockId++) {
            printVariables("before propose");
            (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
            //printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1e10 + blockId);
            bytes32 stateRoot = bytes32(1e9 + blockId);
            // This proof cannot be verified obviously because of blockhash is
            // exchanged with stateRoot
            proveBlock(Bob, Bob, meta, parentHash, stateRoot, stateRoot, meta.minTier, "");

            // Let's say the 10th block is unprovable so prove accordingly
            if (blockId == 10) {
                TaikoData.Transition memory tran = TaikoData.Transition({
                    parentHash: parentHash,
                    blockHash: blockHash,
                    stateRoot: stateRoot,
                    graffiti: 0x0,
                    __reserved: [bytes32(0), bytes32(0)]
                });

                TaikoData.TierProof memory proof;
                proof.tier = LibTiers.TIER_GUARDIAN;
                proof.data = bytes.concat(keccak256("RETURN_LIVENESS_BOND"));

                uint256 balanceBeforeReimbursement = tko.balanceOf(Bob);

                vm.prank(David, David);
                gp.approve(meta, tran, proof);
                vm.prank(Emma, Emma);
                gp.approve(meta, tran, proof);
                vm.prank(Frank, Frank);
                gp.approve(meta, tran, proof);

                // // Credited back the bond (not transferred to the user
                // wallet,
                // // but in-contract account credited only.)
                assertEq(tko.balanceOf(Bob) - balanceBeforeReimbursement, 1 ether);
            } else {
                // Prove as guardian
                proveBlock(
                    Carol, Carol, meta, parentHash, blockHash, stateRoot, LibTiers.TIER_GUARDIAN, ""
                );
            }
            vm.roll(block.number + 15 * 12);

            uint16 minTier = meta.minTier;
            vm.warp(block.timestamp + L1.getTier(minTier).cooldownWindow + 1);

            verifyBlock(Carol, 1);

            parentHash = blockHash;
        }
        printVariables("");
    }

    function test_L1_ContestingWithLowerTierProofReverts() external {
        giveEthAndTko(Alice, 1e7 ether, 1000 ether);
        giveEthAndTko(Carol, 1e7 ether, 1000 ether);
        console2.log("Alice balance:", tko.balanceOf(Alice));
        // This is a very weird test (code?) issue here.
        // If this line is uncommented,
        // Alice/Bob has no balance.. (Causing reverts !!!)
        // Current investigations are ongoing with foundry team
        giveEthAndTko(Bob, 1e6 ether, 100 ether);
        console2.log("Bob balance:", tko.balanceOf(Bob));
        // Bob
        vm.prank(Bob, Bob);

        bytes32 parentHash = GENESIS_BLOCK_HASH;
        printVariables("before propose");
        (TaikoData.BlockMetadata memory meta,) = proposeBlock(Alice, Bob, 1_000_000, 1024);
        //printVariables("after propose");
        mine(1);

        bytes32 blockHash = bytes32(uint256(1));
        bytes32 stateRoot = bytes32(uint256(1));
        proveBlock(
            Bob, Bob, meta, parentHash, blockHash, stateRoot, LibTiers.TIER_SGX_AND_PSE_ZKEVM, ""
        );

        // Try to contest with a lower tier proof- but should revert with L1_INVALID_TIER
        proveBlock(
            Carol,
            Carol,
            meta,
            parentHash,
            blockHash,
            stateRoot,
            LibTiers.TIER_SGX,
            TaikoErrors.L1_INVALID_TIER.selector
        );

        printVariables("");
    }
}
