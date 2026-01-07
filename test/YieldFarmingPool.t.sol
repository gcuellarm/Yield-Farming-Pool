// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdStorage.sol";
import "../src/YieldFarmingPool.sol";
import "../src/MockToken.sol";

contract YieldFarmingPoolTest is Test {
    using stdStorage for StdStorage;
    YieldFarmingPool public yieldFarmingPool;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    bytes32 public poolId1;
    bytes32 public poolId2;
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18;
    uint256 public constant REWARD_RATE = 1 * 10**16; // 0.01 tokens por segundo

    function _deployFreshPool(uint256 rewardTokenFunding) internal returns (YieldFarmingPool pool, MockToken rwd, MockToken stk) {
        rwd = new MockToken("Reward Token", "RWD", INITIAL_SUPPLY);
        stk = new MockToken("Staking Token", "STK", INITIAL_SUPPLY);
        pool = new YieldFarmingPool(address(rwd));
        if (rewardTokenFunding > 0) {
            rwd.transfer(address(pool), rewardTokenFunding);
        }
    }

    function _setPoolActive(bytes32 poolId, bool active) internal {
        stdstore
            .target(address(yieldFarmingPool))
            .sig("pools(bytes32)")
            .with_key(poolId)
            .depth(5)
            .checked_write(active);

        (, , , , , bool isActiveAfter) = yieldFarmingPool.pools(poolId);
        assertEq(isActiveAfter, active);
    }
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy tokens
        rewardToken = new MockToken("Reward Token", "RWD", INITIAL_SUPPLY);
        stakingToken1 = new MockToken("Staking Token 1", "STK1", INITIAL_SUPPLY);
        stakingToken2 = new MockToken("Staking Token 2", "STK2", INITIAL_SUPPLY);
        
        // Deploy contracts
        yieldFarmingPool = new YieldFarmingPool(address(rewardToken));
        
        // Transfer tokens to users
        stakingToken1.transfer(user1, 10000 * 10**18);
        stakingToken1.transfer(user2, 10000 * 10**18);
        stakingToken2.transfer(user1, 10000 * 10**18);
        stakingToken2.transfer(user3, 10000 * 10**18);
        
        // Transfer reward tokens to the farming pool
        rewardToken.transfer(address(yieldFarmingPool), 500000 * 10**18);
        
        // Create pools
        poolId1 = yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
        poolId2 = yieldFarmingPool.createPool(address(stakingToken2), REWARD_RATE * 2);
        
        // Approve tokens
        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarmingPool), type(uint256).max);
        stakingToken2.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        stakingToken1.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        stakingToken2.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
    }
    
    function testCreatePool() public {
        // Verificar que los pools se crearon correctamente
        // Accedemos a los campos de la estructura Pool usando índices
        (address token1, uint256 totalStaked1, uint256 rewardRate1, uint256 lastUpdateTime1, uint256 rewardPerTokenStored1, bool isActive1) = yieldFarmingPool.pools(poolId1);
        (address token2, uint256 totalStaked2, uint256 rewardRate2, uint256 lastUpdateTime2, uint256 rewardPerTokenStored2, bool isActive2) = yieldFarmingPool.pools(poolId2);
        
        assertTrue(isActive1);
        assertTrue(isActive2);
        assertEq(token1, address(stakingToken1));
        assertEq(token2, address(stakingToken2));
        assertEq(rewardRate1, REWARD_RATE);
        assertEq(rewardRate2, REWARD_RATE * 2);
    }
    
    function testPoolIdUniqueness() public {
        // Verificar que los poolIds son únicos
        assertTrue(poolId1 != poolId2);
        
        // Crear otro pool con los mismos parámetros pero en diferente tiempo
        vm.warp(block.timestamp + 1);
        bytes32 poolId3 = yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
        
        // Debería ser diferente debido al timestamp
        assertTrue(poolId1 != poolId3);
    }
    
    function testStake() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        vm.stopPrank();
        
        // Verificar que el stake se registró correctamente
        (uint256 amount, uint256 rewardDebt, uint256 lastClaimTime) = yieldFarmingPool.userInfo(poolId1, user1);
        (address token, uint256 totalStaked, uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardPerTokenStored, bool isActive) = yieldFarmingPool.pools(poolId1);
        
        assertEq(amount, stakeAmount);
        assertEq(totalStaked, stakeAmount);
    }
    
    function testStakeAndRewards() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        vm.stopPrank();
        
        // Avanzar tiempo para generar recompensas
        vm.warp(block.timestamp + 100);
        
        // Verificar recompensas pendientes
        uint256 pendingRewards = yieldFarmingPool.pendingRewards(poolId1, user1);
        assertGt(pendingRewards, 0);
        
        // Reclamar recompensas
        vm.startPrank(user1);
        yieldFarmingPool.claimRewards(poolId1);
        vm.stopPrank();
        
        // Verificar que las recompensas se transfirieron
        assertGt(rewardToken.balanceOf(user1), 0);
    }
    
    function testWithdraw() public {
        uint256 stakeAmount = 1000 * 10**18;
        uint256 withdrawAmount = 500 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        
        // Avanzar tiempo para generar recompensas
        vm.warp(block.timestamp + 100);
        
        yieldFarmingPool.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();
        
        // Verificar que el withdraw se procesó correctamente
        (uint256 amount, , ) = yieldFarmingPool.userInfo(poolId1, user1);
        ( , uint256 totalStaked, , , , ) = yieldFarmingPool.pools(poolId1);
        
        assertEq(amount, stakeAmount - withdrawAmount);
        assertEq(totalStaked, stakeAmount - withdrawAmount);
        assertEq(stakingToken1.balanceOf(user1), 9000 * 10**18 + withdrawAmount);
    }
    
    function testMultipleUsers() public {
        uint256 stakeAmount1 = 1000 * 10**18;
        uint256 stakeAmount2 = 2000 * 10**18;
        
        // User1 stake en pool1
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount1);
        vm.stopPrank();
        
        // User2 stake en pool1
        vm.startPrank(user2);
        yieldFarmingPool.stake(poolId1, stakeAmount2);
        vm.stopPrank();
        
        // Avanzar tiempo
        vm.warp(block.timestamp + 100);
        
        // Verificar que ambos usuarios tienen recompensas
        uint256 pending1 = yieldFarmingPool.pendingRewards(poolId1, user1);
        uint256 pending2 = yieldFarmingPool.pendingRewards(poolId1, user2);
        
        assertGt(pending1, 0);
        assertGt(pending2, 0);
        
        // User2 debería tener más recompensas por tener más tokens staked
        assertGt(pending2, pending1);
    }
    
    function testGetPoolEncodedData() public {
        // Obtener datos codificados del pool
        bytes memory encodedData = yieldFarmingPool.getPoolEncodedData(poolId1);
        
        // Verificar que los datos están codificados
        assertGt(encodedData.length, 0);
        
        // Los datos codificados deberían contener información del pool
        // Como no podemos decodificar directamente, verificamos que no esté vacío
        assertTrue(encodedData.length > 0);
    }
    
    function testGetUserHash() public {
        // Crear hash único para el usuario
        bytes32 userHash = yieldFarmingPool.getUserHash(poolId1, user1);
        
        // Verificar que el hash es único
        bytes32 userHash2 = yieldFarmingPool.getUserHash(poolId1, user2);
        assertTrue(userHash != userHash2);
        
        // Verificar que el mismo usuario en diferentes pools tiene diferentes hashes
        bytes32 userHashPool2 = yieldFarmingPool.getUserHash(poolId2, user1);
        assertTrue(userHash != userHashPool2);
    }
    
    function testUpdatePoolRewardRate() public {
        uint256 newRewardRate = REWARD_RATE * 2;
        
        yieldFarmingPool.updatePoolRewardRate(poolId1, newRewardRate);
        
        ( , , uint256 rewardRate, , , ) = yieldFarmingPool.pools(poolId1);
        assertEq(rewardRate, newRewardRate);
    }
    
    function testEmergencyWithdraw() public {
        // Transferir tokens al contrato para probar emergency withdraw
        stakingToken1.transfer(address(yieldFarmingPool), 1000 * 10**18);
        
        uint256 balanceBefore = stakingToken1.balanceOf(owner);
        
        yieldFarmingPool.emergencyWithdraw(address(stakingToken1), 1000 * 10**18);
        
        uint256 balanceAfter = stakingToken1.balanceOf(owner);
        assertEq(balanceAfter, balanceBefore + 1000 * 10**18);
    }
    
    function test_RevertWhen_StakeInactivePool() public {
        _setPoolActive(poolId1, false);
        vm.startPrank(user1);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.stake(poolId1, 1);
        vm.stopPrank();
    }
    
    function test_RevertWhen_WithdrawMoreThanStaked() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        
        vm.expectRevert("Insufficient staked amount");
        yieldFarmingPool.withdraw(poolId1, stakeAmount + 1);
        vm.stopPrank();
    }
    
    function test_RevertWhen_ClaimNoRewards() public {
        vm.startPrank(user1);
        vm.expectRevert("No rewards to claim");
        yieldFarmingPool.claimRewards(poolId1);
        vm.stopPrank();
    }
    
    function testGetActivePools() public {
        bytes32[] memory activePools = yieldFarmingPool.getActivePools();
        assertEq(activePools.length, 2);
        assertEq(activePools[0], poolId1);
        assertEq(activePools[1], poolId2);
        
        assertEq(yieldFarmingPool.getActivePoolsCount(), 2);
    }

    function test_RevertWhen_ConstructorInvalidRewardToken() public {
        vm.expectRevert("Invalid Reward Token");
        new YieldFarmingPool(address(0));
    }

    function test_RevertWhen_CreatePoolInvalidToken() public {
        vm.expectRevert("Invalid Token");
        yieldFarmingPool.createPool(address(0), REWARD_RATE);
    }

    function test_RevertWhen_CreatePoolRewardRateZero() public {
        vm.expectRevert("Reward Rate must be positive");
        yieldFarmingPool.createPool(address(stakingToken1), 0);
    }

    function test_RevertWhen_CreatePoolAlreadyExistsSameTimestamp() public {
        MockToken stk = new MockToken("Staking Token", "STK", INITIAL_SUPPLY);
        vm.warp(123456);
        bytes32 id1 = yieldFarmingPool.createPool(address(stk), REWARD_RATE);
        vm.expectRevert("Pool already exists");
        bytes32 id2 = yieldFarmingPool.createPool(address(stk), REWARD_RATE);
        id1;
        id2;
    }

    function test_RevertWhen_StakeAmountZero() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be positive");
        yieldFarmingPool.stake(poolId1, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawAmountZero() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 1000 * 10**18);
        vm.expectRevert("Amount must be positive");
        yieldFarmingPool.withdraw(poolId1, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdatePoolRewardRateNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        yieldFarmingPool.updatePoolRewardRate(poolId1, REWARD_RATE * 3);
        vm.stopPrank();
    }

    function test_RevertWhen_EmergencyWithdrawNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        yieldFarmingPool.emergencyWithdraw(address(stakingToken1), 1);
        vm.stopPrank();
    }

    function testPendingRewardsNoStakeReturnsZero() public {
        uint256 pending = yieldFarmingPool.pendingRewards(poolId1, user1);
        assertEq(pending, 0);
    }

    function testClaimRewardsCapsToRewardBalance() public {
        (YieldFarmingPool pool, MockToken rwd, MockToken stk) = _deployFreshPool(1);
        bytes32 pid = pool.createPool(address(stk), REWARD_RATE);

        address u = makeAddr("capUser");
        stk.transfer(u, 1000 * 10**18);
        vm.startPrank(u);
        stk.approve(address(pool), type(uint256).max);
        pool.stake(pid, 1000 * 10**18);
        vm.warp(block.timestamp + 100);
        pool.claimRewards(pid);
        vm.stopPrank();

        assertEq(rwd.balanceOf(u), 1);
        assertEq(rwd.balanceOf(address(pool)), 0);
    }

    function testClaimRewardsWithZeroRewardBalanceTransfersNothing() public {
        (YieldFarmingPool pool, MockToken rwd, MockToken stk) = _deployFreshPool(0);
        bytes32 pid = pool.createPool(address(stk), REWARD_RATE);

        address u = makeAddr("zeroRewardUser");
        stk.transfer(u, 1000 * 10**18);
        vm.startPrank(u);
        stk.approve(address(pool), type(uint256).max);
        pool.stake(pid, 1000 * 10**18);
        vm.warp(block.timestamp + 100);
        pool.claimRewards(pid);
        vm.stopPrank();

        assertEq(rwd.balanceOf(u), 0);
    }

    function testMockTokenMintAndBurn() public {
        uint256 mintAmount = 123 * 10**18;
        rewardToken.mint(user1, mintAmount);
        assertEq(rewardToken.balanceOf(user1), mintAmount);

        vm.startPrank(user1);
        rewardToken.burn(23 * 10**18);
        vm.stopPrank();
        assertEq(rewardToken.balanceOf(user1), 100 * 10**18);
    }

    function test_RevertWhen_MockTokenMintNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        rewardToken.mint(user1, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_StakeNonexistentPool() public {
        bytes32 nonexistent = keccak256("does-not-exist");
        vm.startPrank(user1);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.stake(nonexistent, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawInactivePool() public {
        uint256 stakeAmount = 1000 * 10**18;

        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        vm.stopPrank();

        _setPoolActive(poolId1, false);

        vm.startPrank(user1);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.withdraw(poolId1, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdatePoolRewardRateInactivePool() public {
        _setPoolActive(poolId1, false);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.updatePoolRewardRate(poolId1, REWARD_RATE);
    }
}