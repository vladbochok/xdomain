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
    function hope(address usr) external;
    function file(bytes32 what, uint256 data) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external;
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

/// @title Extend a line of credit to a domain
abstract contract DomainJoin {

    // --- Data ---
    mapping (address => uint256) public wards;

    bytes32     public immutable ilk;
    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;
    DaiLike     public immutable dai;
    address     public immutable escrow;

    uint256 public line;

    uint256 constant RAY = 10 ** 27;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Lift(uint256 wad);
    event Release(uint256 wad);
    event Cage();

    modifier auth {
        require(wards[msg.sender] == 1, "DomainJoin/not-authorized");
        _;
    }

    constructor(bytes32 _ilk, address _daiJoin, address _escrow) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        daiJoin = DaiJoinLike(_daiJoin);
        vat = daiJoin.vat();
        dai = daiJoin.dai();
        escrow = _escrow;
        
        vat.hope(address(daiJoin));
    }

    // --- Math ---
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0);
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

    /// @notice Set the global debt ceiling for the remote domain
    ///
    /// @dev Please note that pre-mint DAI cannot be removed from the remote domain
    /// until the remote domain signals that it is safe to do so
    function lift(uint256 wad) external auth {
        uint256 rad = wad * RAY;
        uint256 minted;

        if (rad > line) {
            // We are issuing new pre-minted DAI
            minted = (rad - line) / RAY;                    // No precision loss as line is always a multiple of RAY
            vat.slip(ilk, address(this), int256(minted));   // No need for conversion check as amt is under a RAY of full size
            vat.frob(ilk, address(this), address(this), address(this), int256(minted), int256(minted));
            daiJoin.exit(escrow, minted);
        }

        line = rad;

        _lift(rad, minted);

        emit Lift(wad);
    }

    /// @notice Withdraw pre-mint DAI from the remote domain
    ///
    /// @dev Should only be triggered by remote domain when it is safe to do so
    function release(uint256 wad) external auth {
        int256 amt = -_int256(wad);

        require(dai.transferFrom(escrow, address(this), wad), "DomainJoin/transfer-failed");
        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), address(this), amt, amt);
        vat.slip(ilk, address(this), amt);

        emit Release(wad);
    }

    /// @notice Initiate cage for this domain
    function cage() external auth {
        // TODO
        _cage();

        emit Cage();
    }

    // Bridge-specific functions
    function _lift(uint256 line, uint256 minted) internal virtual;
    function _cage() internal virtual;

}
