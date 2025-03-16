// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import {Base_Test} from "../Base.t.sol";

contract Unit_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();

        // Make the owner the caller for `launch`.
        resetPrank({msgSender: users.owner});
        hook.launch();

        // Set `users.sender` as the default caller for the tests.
        resetPrank({msgSender: users.sender});
    }
}
