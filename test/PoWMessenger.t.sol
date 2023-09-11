// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {PoWMessenger} from "src/PoWMessenger.sol";

contract PoWMessengerTest is Test {
    event Deposit(address indexed sender, uint256 value);
    event Withdrawal(address indexed sender, uint256 value);
    event IncentiveSet(address indexed sender, address indexed receiver, uint128 rewardPerMessage, uint64 patience);
    event MessageSent(address indexed sender, address indexed receiver, string message);
    event Response(address indexed sender, address indexed receiver, string message);

    PoWMessenger public messenger;
    address internal receiver = makeAddr("receiver");
    uint128 internal rewardPerMessage = 1 gwei;
    uint64 internal patience = 7200;

    function setUp() public {
        messenger = new PoWMessenger();
        messenger.setIncentive(receiver, rewardPerMessage, patience);
    }

    receive() external payable {}

    function testDeposit() public {
        vm.expectEmit(address(messenger));
        emit Deposit(address(this), 100);
        messenger.deposit{value: 100}();
        assertEq(messenger.balanceOf(address(this)), 100);
    }

    function testDeposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        if (amount != 0) {
            vm.expectEmit(address(messenger));
            emit Deposit(address(this), amount);
        }
        messenger.deposit{value: amount}();
        assertEq(messenger.balanceOf(address(this)), amount);
    }

    function testReceive() public {
        vm.expectEmit(address(messenger));
        emit Deposit(address(this), 100);
        (bool success,) = address(messenger).call{value: 100}("");
        assertTrue(success);
        assertEq(messenger.balanceOf(address(this)), 100);
    }

    function testWithdraw() public {
        messenger.deposit{value: 100}();
        vm.expectEmit(address(messenger));
        emit Withdrawal(address(this), 50);
        messenger.withdraw(50);
        assertEq(messenger.balanceOf(address(this)), 50);
    }

    function testWithdraw(uint256 amount) public {
        messenger.deposit{value: 1 ether}();
        amount = bound(amount, 0, 1 ether);
        uint256 balance = address(this).balance;
        vm.expectEmit(address(messenger));
        emit Withdrawal(address(this), amount);
        messenger.withdraw(amount);
        assertEq(messenger.balanceOf(address(this)), 1 ether - amount);
        assertEq(address(this).balance, balance + amount);
    }

    function testSetIncentive() public {
        vm.expectEmit(address(messenger));
        emit IncentiveSet(address(this), receiver, rewardPerMessage, patience);
        messenger.setIncentive(receiver, rewardPerMessage, patience);
        PoWMessenger.Conversation memory convo = messenger.conversations(address(this), receiver);
        assertEq(convo.rewardPerMessage, rewardPerMessage);
        assertEq(convo.patience, patience);
    }

    function testSendMessage() public {
        vm.expectEmit(address(messenger));
        emit MessageSent(address(this), receiver, "hello");
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        assertEq(messenger.balanceOf(address(this)), 1 ether);
    }

    function testSendMessage(string calldata message) public {
        vm.expectEmit(address(messenger));
        emit MessageSent(address(this), receiver, message);
        messenger.sendMessage{value: 1 ether}(receiver, message);
        assertEq(messenger.balanceOf(address(this)), 1 ether);
    }

    function testRespond() public {
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        vm.startPrank(receiver);
        vm.expectEmit(address(messenger));
        emit Response(address(this), receiver, "world");
        messenger.respond(address(this), "world");
        assertEq(messenger.balanceOf(address(this)), 1 ether - rewardPerMessage);
        assertEq(receiver.balance, rewardPerMessage);
    }

    function testRespond(uint256 delay) public {
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        delay = bound(delay, 0, patience - 1);
        vm.warp(block.timestamp + delay);
        vm.startPrank(receiver);
        vm.expectEmit(address(messenger));
        emit Response(address(this), receiver, "world");
        messenger.respond(address(this), "world");
        uint256 reward = uint256(rewardPerMessage) * (patience - delay) / patience;
        assertLe(reward, rewardPerMessage);
        assertEq(messenger.balanceOf(address(this)), 1 ether - reward);
        assertEq(receiver.balance, reward);
    }

    function testDoubleRespond() public {
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        vm.startPrank(receiver);
        messenger.respond(address(this), "world");
        vm.expectRevert();
        messenger.respond(address(this), "world");
    }

    function testInsufficientBalance() public {
        vm.expectRevert("insufficient balance");
        messenger.sendMessage{value: rewardPerMessage - 1}(receiver, "hello");
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        messenger.withdraw(1 ether - 1);
        vm.startPrank(receiver);
        vm.expectRevert("insufficient balance");
        messenger.respond(address(this), "world");
    }

    function testRespondAfterDeadline() public {
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        vm.startPrank(receiver);
        vm.warp(block.timestamp + patience);
        vm.expectRevert("patience exhausted");
        messenger.respond(address(this), "world");
    }

    function testDifferentReceiver() public {
        messenger.sendMessage{value: 1 ether}(receiver, "hello");
        vm.expectRevert("patience exhausted");
        messenger.respond(makeAddr("different"), "world");
    }
}
