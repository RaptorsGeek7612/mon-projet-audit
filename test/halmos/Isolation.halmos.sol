// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/Vault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract VaultMinimal {
    IERC20 public immutable asset;

    constructor(IERC20 _asset) {
        asset = _asset;
    }
}

contract VaultTwoUses {
    IERC20 public immutable asset;

    constructor(IERC20 _asset) {
        asset = _asset;
    }

    function peek() external view returns (address) {
        return address(asset);
    }
}

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

contract OnlyTokenHalmosTest is Test {
    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
    }

    function check_dummy() public view {
        assert(address(token) != address(0));
    }
}

contract OnlyVaultHalmosTest is Test {
    Vault vault;

    function setUp() public {
        vault = new Vault(MockERC20(address(0xBEEF)));
    }

    function check_dummy() public view {
        assert(address(vault.asset()) == address(0xBEEF));
    }
}

contract OnlyVaultMinimalHalmosTest is Test {
    VaultMinimal vault;

    function setUp() public {
        vault = new VaultMinimal(IERC20(address(0xBEEF)));
    }

    function check_dummy() public view {
        assert(address(vault.asset()) == address(0xBEEF));
    }
}

contract OnlyVaultTwoUsesHalmosTest is Test {
    VaultTwoUses vault;

    function setUp() public {
        vault = new VaultTwoUses(IERC20(address(0xBEEF)));
    }

    function check_dummy() public view {
        assert(address(vault.asset()) == address(0xBEEF));
    }
}

contract VaultRawCreateHalmosTest is Test {
    Vault vault;

    function setUp() public {
        bytes memory initcode = abi.encodePacked(type(Vault).creationCode, abi.encode(address(0xBEEF)));
        address addr;
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), "raw create failed");
        vault = Vault(addr);
    }

    function check_dummy() public view {
        assert(address(vault.asset()) == address(0xBEEF));
    }
}

contract IsolationHalmosTest is Test {
    Helper helper;
    NoImmutable a;
    WithImmutableAddress b;
    WithImmutableInterface c;
    ConsumesInterfaceDirectly d;
    MockERC20 token;
    Vault vault;

    function setUp() public {
        helper = new Helper();
        a = new NoImmutable(address(helper));
        b = new WithImmutableAddress(address(helper));
        c = new WithImmutableInterface(address(helper));
        d = new ConsumesInterfaceDirectly(helper);
        token = new MockERC20();
        vault = new Vault(token);
    }

    function check_dummy() public view {
        assert(a.target() == address(helper));
        assert(b.target() == address(helper));
        assert(address(c.target()) == address(helper));
        assert(address(d.target()) == address(helper));
        assert(address(vault.asset()) == address(token));
    }
}
