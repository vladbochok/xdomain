// SPDX-License-Identifier: AGPL-3.0-or-later

/// DomainJoin.sol -- xdomain join adapter

// Copyright (C) 2022 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.13;

interface VatLike {
    function debt() external view returns (uint256);
    function Line() external view returns (uint256);
    function file(bytes32 what, uint256 data) external;
    function dai(address usr) external view returns (uint256);
    function sin(address usr) external view returns (uint256);
    function heal(uint256 rad) external;
}

interface DaiJoinLike {
    function vat() external view returns (VatLike);
    function dai() external view returns (DaiLike);
    function join(address usr, uint256 wad) external;
    function exit(address usr, uint256 wad) external;
}

interface DaiLike {
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}

/// @title Keeps track of local slave-instance dss values and relays messages to DomainJoin
abstract contract DomainManager {
    
    // --- Data ---
    mapping (address => uint256) public wards;

    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;
    DaiLike     public immutable dai;

    uint256 public grain;       // Keep track of the pre-minted DAI in the remote escrow

    uint256 constant RAY = 10 ** 27;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    modifier auth {
        require(wards[msg.sender] == 1, "DomainManager/not-authorized");
        _;
    }

    constructor(address _daiJoin) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        daiJoin = DaiJoinLike(_daiJoin);
        vat = daiJoin.vat();
        dai = daiJoin.dai();
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x + y - 1) / y;
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /// @notice Set the global debt ceiling for the local dss
    /// @dev Should only be triggered from the DomainJoin
    function lift(uint256 line, uint256 minted) external auth {
        vat.file("Line", line);
        grain += minted;
    }

    /// @notice Will release remote DAI from the escrow when it is safe to do so
    /// @dev Should be run by keeper on a regular schedule
    function release() external {
        uint256 limit = _min(vat.Line() / RAY, _divup(vat.debt(), RAY));
        require(grain > limit, "DomainManager/no-extra-to-release");
        uint256 burned = grain - limit;
        grain = limit;

        _release(burned);
    }

    /// @notice Push surplus (or deficit) to the master dss
    /// @dev Should be run by keeper on a regular schedule
    function push() external {
        uint256 _dai = vat.dai(address(this));
        uint256 _sin = vat.sin(address(this));
        if (_dai > _sin) {
            // We have a surplus
            vat.heal(_sin);

            uint256 wad = (_dai - _sin) / RAY;    // Leave the dust
            daiJoin.exit(address(this), wad);
            _surplus(wad);
        } else if (_dai < _sin) {
            // We have a deficit
            vat.heal(_dai);

            _deficit(_divup(_dai - _sin, RAY));   // Round up to overcharge for deficit
        }
    }

    function cage() external {
        // TODO
    }

    // Bridge-specific functions
    function _release(uint256 burned) internal virtual;
    function _surplus(uint256 wad) internal virtual;
    function _deficit(uint256 wad) internal virtual;
    
}
