// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

interface IHelperIface {
    function x() external view returns (uint256);
}

contract Helper is IHelperIface {
    uint256 public x;
}

contract ConsumesInterfaceDirectly {
    IHelperIface public immutable target;

    constructor(IHelperIface _target) {
        target = _target;
    }
}

contract NoImmutable {
    address public target;

    constructor(address _target) {
        target = _target;
    }
}

contract WithImmutableAddress {
    address public immutable target;

    constructor(address _target) {
        target = _target;
    }
}

interface IHelper {
    function x() external view returns (uint256);
}

contract WithImmutableInterface {
    IHelper public immutable target;

    constructor(address _target) {
        target = IHelper(_target);
    }
}

contract IsolationHalmosTest is Test {
    Helper helper;
    NoImmutable a;
    WithImmutableAddress b;
    WithImmutableInterface c;
    ConsumesInterfaceDirectly d;

    function setUp() public {
        helper = new Helper();
        a = new NoImmutable(address(helper));
        b = new WithImmutableAddress(address(helper));
        c = new WithImmutableInterface(address(helper));
        d = new ConsumesInterfaceDirectly(helper);
    }

    function check_dummy() public view {
        assert(a.target() == address(helper));
        assert(b.target() == address(helper));
        assert(address(c.target()) == address(helper));
        assert(address(d.target()) == address(helper));
    }
}
