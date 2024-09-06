// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract CattyNip is ERC20Burnable {
    address public immutable i_kittyCombat;

    modifier onlyKittyCombat {
        if (msg.sender != i_kittyCombat) {
            revert();
        }
        _;
    }

    constructor(address _kittyCombat) ERC20("CattyNip", "CN") {
        i_kittyCombat = _kittyCombat;
    }

    function mint(address _to, uint256 _amount) external onlyKittyCombat {
        _mint(_to, _amount);
    }
}