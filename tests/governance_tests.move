#[allow(unused_const, unused_function, unused_use)]
#[test_only]
module crowd9_sc::governance_tests {
    use std::debug::print;
    use crowd9_sc::governance::{Self, Governance, check_proposal_status, create_proposal};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::sui::SUI;
    use std::option::{Self};
    use sui::object::{Self, ID};
    use sui::coin::{Self};
    use sui::transfer::{Self};
    use sui::clock::{Self, Clock};
    use sui::linked_table;
    use sui::linked_table::LinkedTable;
    use sui::balance;

    const ADMIN: address = @0xABCED;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const CAROL: address = @0xCCCC;
    const DAVID: address = @0xDDDD;
    const ERIN: address = @0xEEEE;
    const FRANK: address = @0xFFFF;

    const VAgainst: u8 = 0;
    const VFor: u8 = 1;
    const VAbstain: u8 = 2;
    const VNoVote: u8 = 3;

    const SActive: u8 = 0;
    const SInactive: u8 = 1;
    const SSuccess: u8 = 2;
    const SFailure: u8 = 3;
    const SAborted: u8 = 4;
    const SExecuted: u8 = 5;

    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const EDuplicatedVotes: u64 = 001;
    const EUnauthorizedUser: u64 = 002;
    const EInvalidAction: u64 = 003;
    const ENonExistingAction: u64 = 004;
    const EUnxpectedError: u64 = 005;
    const ERepeatedDelegation: u64 = 006;
    const EInvalidDelegatee: u64 = 007;
    const ENoPermission: u64 = 008;
    const EInsufficientBalance: u64 = 008;
    const ECircularDelegation: u64 = 009;
    const EInvalidVoteChoice: u64 = 010;
    const EInvalidParameter: u64 = 011;

    // 3 days
    const PROPOSAL_DURATION: u64 = 259200 * 1000;
    // 0.5% of total votes to create proposal
    const PROPOSAL_CREATE_THRESHOLD: u64 = 5;
    // 5% of total votes for proposal to be considered valid
    const QUORUM_THRESHOLD: u64 = 50;
    // 66.7% for proposal to be approved
    const APPROVAL_THRESHOLD: u64 = 667;
    const THRESHOLD_DENOMINATOR: u64 = 1000;

    // user contribution
    const BOB_CONTRIBUTION: u64 = 20000;
    const CAROL_CONTRIBUTION: u64 = 25000;
    const DAVID_CONTRIBUTION: u64 = 30000;
    const FRANK_CONTRIBUTION: u64 = 50000;
    const INITIAL_CONTRIBUTED_AMOUNT: u64 = 20000 + 25000 + 30000;
    const INITIAL_TAP_RATE: u64 = 1000;

    struct TEST_COIN has drop {}

    fun init_governance<X, Y>(scenario: &mut Scenario, user: address): (Governance<X, Y>, Clock) {
        ts::next_tx(scenario, user);
        let contributions: LinkedTable<address, u64> = linked_table::new(ts::ctx(scenario));
        linked_table::push_back(&mut contributions, BOB, BOB_CONTRIBUTION);
        linked_table::push_back(&mut contributions, CAROL, CAROL_CONTRIBUTION);
        linked_table::push_back(&mut contributions, DAVID, DAVID_CONTRIBUTION);
        linked_table::push_back(&mut contributions, FRANK, FRANK_CONTRIBUTION);
        let scale_factor = 1;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        let governance = governance::create_governance(
            user,
            b"test",
            b"test_desc",
            b"abc.com",
            object::id_from_address(@0xABC),
            balance::create_for_testing<SUI>(INITIAL_CONTRIBUTED_AMOUNT),
            balance::create_for_testing<TEST_COIN>(INITIAL_CONTRIBUTED_AMOUNT),
            contributions,
            scale_factor,
            &clock,
            ts::ctx(scenario)
        );

        clock::share_for_testing(clock);
        transfer::public_share_object(governance);


        ts::next_tx(scenario, ALICE);
        let governance = ts::take_shared<Governance<X, Y>>(scenario);
        let clock = ts::take_shared<Clock>(scenario);
        (governance, clock)
    }

    fun init_governance_with_proposals_created<X, Y>(
        scenario: &mut Scenario,
        user: address
    ): (Governance<X, Y>, Clock, ID, ID, ID) {
        ts::next_tx(scenario, user);
        let contributions: LinkedTable<address, u64> = linked_table::new(ts::ctx(scenario));
        linked_table::push_back(&mut contributions, BOB, BOB_CONTRIBUTION);
        linked_table::push_back(&mut contributions, CAROL, CAROL_CONTRIBUTION);
        linked_table::push_back(&mut contributions, DAVID, DAVID_CONTRIBUTION);
        linked_table::push_back(&mut contributions, FRANK, FRANK_CONTRIBUTION);
        let scale_factor = 1;

        let clock = clock::create_for_testing(ts::ctx(scenario));
        let governance = governance::create_governance(
            user,
            b"test",
            b"test_desc",
            b"abc.com",
            object::id_from_address(@0xABC),
            balance::create_for_testing<SUI>(INITIAL_CONTRIBUTED_AMOUNT),
            balance::create_for_testing<TEST_COIN>(INITIAL_CONTRIBUTED_AMOUNT),
            contributions,
            scale_factor,
            &clock,
            ts::ctx(scenario)
        );

        clock::share_for_testing(clock);
        transfer::public_share_object(governance);

        ts::next_tx(scenario, ALICE);
        let governance = ts::take_shared<Governance<X, Y>>(scenario);
        let clock = ts::take_shared<Clock>(scenario);

        ts::next_tx(scenario, ALICE);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(INITIAL_TAP_RATE);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };
        let proposal_id1 = governance::get_proposal_id_by_index(&governance, 0);

        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario))
        };

        ts::next_tx(scenario, DAVID);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario))
        };

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise Refund";
            let proposal_desc = b"Proposal to initialise refund stage for contributors";
            let proposed_tap_rate = option::some<u64>(0);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PRefund,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };
        let proposal_id2 = governance::get_proposal_id_by_index(&governance, 1);

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Set 0 tap rate";
            let proposal_desc = b"Proposal to set 0 tap rate to begin refund process";
            let proposed_tap_rate = option::some<u64>(0);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };
        let proposal_id3 = governance::get_proposal_id_by_index(&governance, 2);

        (governance, clock, proposal_id1, proposal_id2, proposal_id3)
    }

    fun end_scenario<X, Y>(governance: Governance<X, Y>, clock: Clock, scenario_val: Scenario) {
        ts::return_shared(governance);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }

    // Withdraw Coin
    #[test]
    fun withdraw_coin_partial_balance() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            let user = ts::sender(scenario);
            let withdraw_amount = 10000;
            let withdrawn_coin = governance::withdraw_coin(&mut governance, withdraw_amount, ts::ctx(scenario));

            assert!(
                governance::check_project_coin_balance(&governance, INITIAL_CONTRIBUTED_AMOUNT - withdraw_amount),
                1
            );
            assert!(governance::check_user_balance(&governance, user, BOB_CONTRIBUTION - withdraw_amount), 1);
            assert!(coin::value(&withdrawn_coin) == withdraw_amount, 1);
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test]
    fun withdraw_coin_full_balance() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            let user = ts::sender(scenario);
            let withdraw_amount = BOB_CONTRIBUTION;
            let withdrawn_coin = governance::withdraw_coin(&mut governance, withdraw_amount, ts::ctx(scenario));

            assert!(
                governance::check_project_coin_balance(&governance, INITIAL_CONTRIBUTED_AMOUNT - withdraw_amount),
                1
            );
            assert!(governance::check_user_balance(&governance, user, BOB_CONTRIBUTION - withdraw_amount), 1);
            assert!(coin::value(&withdrawn_coin) == withdraw_amount, 1);
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun withdraw_coin_invalid_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, ERIN);
        {
            let withdraw_amount = 1;
            let withdrawn_coin = governance::withdraw_coin(&mut governance, withdraw_amount, ts::ctx(scenario));

            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun withdraw_coin_insufficient_balance() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            let withdraw_amount = BOB_CONTRIBUTION + 1;
            let withdrawn_coin = governance::withdraw_coin(&mut governance, withdraw_amount, ts::ctx(scenario));

            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        end_scenario(governance, clock, scenario_val);
    }

    // Deposit Coin
    #[test]
    fun deposit_coin_no_existing_balance() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, ERIN);
        {
            let user = ts::sender(scenario);
            let deposit_coin_amount = 1000;
            let deposit_coin = coin::mint_for_testing<TEST_COIN>(deposit_coin_amount, ts::ctx(scenario));
            governance::deposit_coin(&mut governance, deposit_coin, ts::ctx(scenario));

            assert!(
                governance::check_project_coin_balance(&governance, INITIAL_CONTRIBUTED_AMOUNT + deposit_coin_amount),
                1
            );
            assert!(governance::check_user_balance(&governance, user, deposit_coin_amount), 1);
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test]
    fun deposit_coin_has_existing_balance() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            let user = ts::sender(scenario);
            let deposit_coin_amount = 1000;
            let deposit_coin = coin::mint_for_testing<TEST_COIN>(deposit_coin_amount, ts::ctx(scenario));
            governance::deposit_coin(&mut governance, deposit_coin, ts::ctx(scenario));

            assert!(
                governance::check_project_coin_balance(&governance, INITIAL_CONTRIBUTED_AMOUNT + deposit_coin_amount),
                1
            );
            assert!(governance::check_user_balance(&governance, user, BOB_CONTRIBUTION + deposit_coin_amount), 1);
        };

        end_scenario(governance, clock, scenario_val);
    }

    // Delegate voting power to user
    #[test]
    fun delegate_to_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Before delegating
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, BOB_CONTRIBUTION), 0);
            assert!(governance::check_user_delegate_to(&governance, BOB, option::none<address>()), 1);
            assert!(governance::check_user_voting_power_governance(&governance, CAROL, CAROL_CONTRIBUTION), 0);
            assert!(!governance::check_if_user_in_delegate_by(&governance, CAROL, BOB), 1)
        };

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 0);
            assert!(governance::check_user_delegate_to(&governance, BOB, option::some(CAROL)), 1);
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    CAROL,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION
                ),
                0
            );
            assert!(governance::check_user_delegate_to(&governance, CAROL, option::none<address>()), 1);
            assert!(governance::check_if_user_in_delegate_by(&governance, CAROL, BOB), 2);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_then_withdraw_full() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 0);
        assert!(governance::check_user_delegate_to(&governance, BOB, option::some(CAROL)), 1);
        assert!(
            governance::check_user_voting_power_governance(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION),
            0
        );
        assert!(governance::check_user_delegate_to(&governance, CAROL, option::none<address>()), 1);
        assert!(governance::check_if_user_in_delegate_by(&governance, CAROL, BOB), 2);

        // Bob withdraw
        ts::next_tx(scenario, BOB);
        {
            let withdrawn_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION, ts::ctx(scenario));
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        // After delegating
        assert!(governance::check_user_voting_power_governance(&governance, CAROL, CAROL_CONTRIBUTION), 0);

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_then_withdraw_partial() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 0);
        assert!(governance::check_user_delegate_to(&governance, BOB, option::some(CAROL)), 1);
        assert!(
            governance::check_user_voting_power_governance(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION),
            0
        );
        assert!(governance::check_user_delegate_to(&governance, CAROL, option::none<address>()), 1);
        assert!(governance::check_if_user_in_delegate_by(&governance, CAROL, BOB), 2);

        // Bob withdraw
        ts::next_tx(scenario, BOB);
        {
            let withdrawn_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION - 1, ts::ctx(scenario));
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        ts::next_tx(scenario, CAROL);
        assert!(governance::check_user_voting_power_governance(&governance, CAROL, CAROL_CONTRIBUTION + 1), 0);

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_delegatee_withdraw() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        // Before withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    CAROL,
                    CAROL_CONTRIBUTION + BOB_CONTRIBUTION
                ),
                1
            );
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
        };

        ts::next_tx(scenario, CAROL);
        {
            let coin = governance::withdraw_coin(&mut governance, CAROL_CONTRIBUTION, ts::ctx(scenario));
            coin::burn_for_testing(coin);
        };

        // After withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, BOB_CONTRIBUTION), 1);
            assert!(governance::check_user_voting_power_governance(&governance, CAROL, 0), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_3_level_middle_delegatee_withdraw() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, DAVID, ts::ctx(scenario));
        };

        // Before withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    DAVID,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION + DAVID_CONTRIBUTION
                ),
                1
            );
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
        };

        ts::next_tx(scenario, CAROL);
        {
            let coin = governance::withdraw_coin(&mut governance, CAROL_CONTRIBUTION, ts::ctx(scenario));
            coin::burn_for_testing(coin);
        };

        // After withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, BOB_CONTRIBUTION), 1);
            assert!(governance::check_user_voting_power_governance(&governance, CAROL, 0), 1);
            assert!(governance::check_user_voting_power_governance(&governance, DAVID, DAVID_CONTRIBUTION), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_3_level_middle_delegatee_redelegate() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, DAVID, ts::ctx(scenario));
        };

        // Before redelegate
        ts::next_tx(scenario, ALICE);
        {
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    DAVID,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION + DAVID_CONTRIBUTION
                ),
                1
            );
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
        };

        ts::next_tx(scenario, CAROL);
        {
            governance::remove_delegate(&mut governance, ts::ctx(scenario));
        };
        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, FRANK, ts::ctx(scenario));
        };

        ts::next_tx(scenario, ALICE);
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
            assert!(governance::check_user_voting_power_governance(&governance, CAROL, 0), 1);
            assert!(governance::check_user_voting_power_governance(&governance, DAVID, DAVID_CONTRIBUTION), 1);
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    FRANK,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION + FRANK_CONTRIBUTION
                ),
                1
            );
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_3_level_final_delegatee_withdraw() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, DAVID, ts::ctx(scenario));
        };

        // Before withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    DAVID,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION + DAVID_CONTRIBUTION
                ),
                1
            );
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
        };

        ts::next_tx(scenario, DAVID);
        {
            let coin = governance::withdraw_coin(&mut governance, DAVID_CONTRIBUTION, ts::ctx(scenario));
            coin::burn_for_testing(coin);
        };

        // After withdrawal
        ts::next_tx(scenario, ALICE);
        {
            assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 1);
            assert!(
                governance::check_user_voting_power_governance(
                    &governance,
                    CAROL,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION
                ),
                1
            );
            assert!(governance::check_user_voting_power_governance(&governance, DAVID, 0), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ECircularDelegation)]
    fun delegate_invalid_circular() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        // Delegate
        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun delegate_invalid_sender_has_no_deposit() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, ERIN);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_invalid_sender_already_delegated() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, DAVID, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun delegate_invalid_delegate_to_has_no_deposit() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, ERIN, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    // Remove delegated voting power
    #[test]
    fun remove_delegate_from_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        assert!(governance::check_user_voting_power_governance(&governance, BOB, 0), 0);
        assert!(
            governance::check_user_voting_power_governance(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION),
            0
        );

        // Delegate
        ts::next_tx(scenario, CAROL);
        governance::delegate(&mut governance, DAVID, ts::ctx(scenario));
        assert!(governance::check_user_voting_power_governance(&governance, CAROL, 0), 0);
        assert!(
            governance::check_user_voting_power_governance(
                &governance,
                DAVID,
                BOB_CONTRIBUTION + CAROL_CONTRIBUTION + DAVID_CONTRIBUTION
            ),
            0
        );

        ts::next_tx(scenario, CAROL);
        governance::remove_delegate(&mut governance, ts::ctx(scenario));
        assert!(
            governance::check_user_voting_power_governance(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION),
            0
        );
        assert!(
            governance::check_user_voting_power_governance(&governance, DAVID, DAVID_CONTRIBUTION),
            0
        );
        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun remove_delegate_sender_has_no_deposit() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, ADMIN);
        governance::remove_delegate(&mut governance, ts::ctx(scenario));

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun remove_delegate_sender_has_not_delegated() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            governance::remove_delegate(&mut governance, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val);
    }

    // Create a proposal
    #[test]
    fun create_proposal_with_delegations() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, ALICE);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
            let proposal_id = governance::get_proposal_id_by_index(&governance, 0);
            assert!(
                governance::assert_proposal_details(
                    &governance,
                    proposal_id,
                    proposal_name,
                    proposal_desc,
                    ALICE,
                    PAdjustment,
                    SActive,
                    proposed_tap_rate
                ), 1
            );
            assert!(governance::check_user_voting_power_proposal(&governance, proposal_id, BOB, BOB_CONTRIBUTION), 1);
            assert!(
                governance::check_user_voting_power_proposal(&governance, proposal_id, CAROL, CAROL_CONTRIBUTION),
                1
            );
            assert!(
                governance::check_user_voting_power_proposal(&governance, proposal_id, DAVID, DAVID_CONTRIBUTION),
                1
            );
        };

        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        ts::next_tx(scenario, ALICE);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
            let proposal_id = governance::get_proposal_id_by_index(&governance, 1);
            assert!(
                governance::assert_proposal_details(
                    &governance,
                    proposal_id,
                    proposal_name,
                    proposal_desc,
                    ALICE,
                    PAdjustment,
                    SActive,
                    proposed_tap_rate
                ), 1
            );
            assert!(
                governance::check_user_voting_power_proposal(
                    &governance,
                    proposal_id,
                    CAROL,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION
                ),
                1
            );
            assert!(
                governance::check_user_voting_power_proposal(&governance, proposal_id, DAVID, DAVID_CONTRIBUTION),
                1
            );
        };

        ts::next_tx(scenario, DAVID);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        ts::next_tx(scenario, ALICE);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
            let proposal_id = governance::get_proposal_id_by_index(&governance, 2);
            assert!(
                governance::assert_proposal_details(
                    &governance,
                    proposal_id,
                    proposal_name,
                    proposal_desc,
                    ALICE,
                    PAdjustment,
                    SActive,
                    proposed_tap_rate
                ), 1
            );
            assert!(
                governance::check_user_voting_power_proposal(
                    &governance,
                    proposal_id,
                    CAROL,
                    BOB_CONTRIBUTION + CAROL_CONTRIBUTION + DAVID_CONTRIBUTION
                ),
                1
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test]
    fun create_proposal_not_governance_creator() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun create_proposal_governance_inactive() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        {
            governance::set_governance_ongoing_status(&mut governance, false);
        };

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidParameter)]
    fun create_proposal_invalid_proposal_type() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                2,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidParameter)]
    fun create_proposal_invalid_tap_rate_for_adjustment() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::none<u64>();
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun create_proposal_invalid_tap_rate_for_refund() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        {
            governance::set_tap_rate(&mut governance, 10);
        };

        ts::next_tx(scenario, CAROL);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PRefund,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun create_proposal_sender_has_no_deposit() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, ERIN);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun create_proposal_sender_has_no_voting_power() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        ts::next_tx(scenario, BOB);
        {
            let proposal_name = b"Initialise tap rate";
            let proposal_desc = b"Proposal to start the tap rate";
            let proposed_tap_rate = option::some<u64>(100);
            governance::create_proposal(
                &mut governance,
                proposal_name,
                proposal_desc,
                PAdjustment,
                proposed_tap_rate,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(governance, clock, scenario_val);
    }

    // Vote on a proposal
    #[test]
    fun vote_proposal() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, BOB);
        {
            let vote_type = VFor;
            governance::vote_proposal(&mut governance, proposal_id1, vote_type, ts::ctx(scenario));
            assert!(
                governance::check_vote_count_and_user_in_proposal_vote(
                    &governance,
                    proposal_id1,
                    vote_type,
                    BOB_CONTRIBUTION,
                    BOB
                ),
                1
            );
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidVoteChoice)]
    fun vote_proposal_invalid_vote() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, BOB);
        {
            let vote_type = 3;
            governance::vote_proposal(&mut governance, proposal_id1, vote_type, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun vote_proposal_not_active() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        {
            governance::set_proposal_status(&mut governance, proposal_id1, SSuccess);
        };

        ts::next_tx(scenario, BOB);
        {
            let vote_type = VFor;
            governance::vote_proposal(&mut governance, proposal_id1, vote_type, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun vote_proposal_sender_not_in_snapshot() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, _, proposal_id2, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, BOB);
        {
            let vote_type = VFor;
            governance::vote_proposal(&mut governance, proposal_id2, vote_type, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EDuplicatedVotes)]
    fun vote_proposal_sender_casting_same_vote() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, BOB);
        {
            let vote_type = VFor;
            governance::vote_proposal(&mut governance, proposal_id1, vote_type, ts::ctx(scenario));
        };

        ts::next_tx(scenario, BOB);
        {
            let vote_type = VFor;
            governance::vote_proposal(&mut governance, proposal_id1, vote_type, ts::ctx(scenario));
        };

        end_scenario(governance, clock, scenario_val)
    }

    // End a proposal
    #[test]
    fun end_proposal_success() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, _, proposal_id2, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id2, VFor, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);
        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id2, &clock);
            assert!(governance::check_proposal_status(&governance, proposal_id2, SSuccess), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun end_proposal_failure() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, _, proposal_id2, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id2, VAgainst, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);
        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id2, &clock);
            assert!(governance::check_proposal_status(&governance, proposal_id2, SFailure), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun end_proposal_invalid_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, _, proposal_id2, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);
        governance::set_proposal_status(&mut governance, proposal_id2, SAborted);

        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id2, &clock);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun end_proposal_before_proposal_end_time() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, _, proposal_id2, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id2, &clock);
        };

        end_scenario(governance, clock, scenario_val)
    }

    // Execute a proposal
    #[test]
    fun execute_proposal_adjustment() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id1, VFor, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);

        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id1, &clock);
        };

        assert!(governance::check_tap_rate(&governance, 0), 1);

        ts::next_tx(scenario, ALICE);
        {
            governance::execute_proposal(&mut governance, proposal_id1, &clock);
            assert!(governance::check_proposal_status(&governance, proposal_id1, SExecuted), 1);
            assert!(governance::check_tap_rate(&governance, INITIAL_TAP_RATE), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun execute_proposal_refund() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, proposal_id2, proposal_id3) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id1, VAgainst, ts::ctx(scenario));
            governance::vote_proposal(&mut governance, proposal_id2, VFor, ts::ctx(scenario));
            governance::vote_proposal(&mut governance, proposal_id3, VFor, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);

        ts::next_tx(scenario, ALICE);
        {
            governance::end_proposal(&mut governance, proposal_id1, &clock);
            governance::end_proposal(&mut governance, proposal_id2, &clock);
            governance::end_proposal(&mut governance, proposal_id3, &clock);
        };

        ts::next_tx(scenario, ALICE);
        {
            governance::execute_proposal(&mut governance, proposal_id2, &clock);
            assert!(governance::check_proposal_status(&governance, proposal_id2, SExecuted), 1);
            assert!(governance::check_governance_status(&governance, false), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun execute_proposal_invalid_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, ALICE);
        {
            governance::execute_proposal(&mut governance, proposal_id1, &clock);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun execute_proposal_invalid_governance_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        governance::set_governance_ongoing_status(&mut governance, false);

        ts::next_tx(scenario, ALICE);
        {
            governance::execute_proposal(&mut governance, proposal_id1, &clock);
        };

        end_scenario(governance, clock, scenario_val)
    }

    // Cancel a proposal
    #[test]
    fun cancel_proposal() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, ALICE);
        {
            governance::cancel_proposal(&mut governance, proposal_id1, ts::ctx(scenario));
            assert!(governance::check_proposal_status(&governance, proposal_id1, SAborted), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun cancel_proposal_invalid_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        governance::set_proposal_status(&mut governance, proposal_id1, SExecuted);

        ts::next_tx(scenario, ALICE);
        {
            governance::cancel_proposal(&mut governance, proposal_id1, ts::ctx(scenario));
            assert!(governance::check_proposal_status(&governance, proposal_id1, SAborted), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun cancel_proposal_no_permission() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock, proposal_id1, _, _) = init_governance_with_proposals_created<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::cancel_proposal(&mut governance, proposal_id1, ts::ctx(scenario));
            assert!(governance::check_proposal_status(&governance, proposal_id1, SAborted), 1);
        };

        end_scenario(governance, clock, scenario_val)
    }

    // Claim refund
    #[test]
    fun claim_refund_full_treasury() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, CAROL);
        {
            governance::create_proposal(
                &mut governance,
                b"Refund",
                b"Initiate Refund",
                PRefund,
                option::none<u64>(),
                &clock,
                ts::ctx(scenario)
            );
        };

        let proposal_id = governance::get_proposal_id_by_index(&governance, 0);

        ts::next_tx(scenario, BOB);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };
        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };
        ts::next_tx(scenario, DAVID);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);
        ts::next_tx(scenario, CAROL);
        {
            governance::end_proposal(&mut governance, proposal_id, &clock);
            governance::execute_proposal(&mut governance, proposal_id, &clock);
        };

        ts::next_tx(scenario, BOB);
        {
            let project_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == BOB_CONTRIBUTION, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        ts::next_tx(scenario, CAROL);
        {
            let project_coin = governance::withdraw_coin(&mut governance, CAROL_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == CAROL_CONTRIBUTION, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        ts::next_tx(scenario, DAVID);
        {
            let project_coin = governance::withdraw_coin(&mut governance, DAVID_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == DAVID_CONTRIBUTION, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun claim_refund_not_full_treasury() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        governance::set_treasury_amount(&mut governance, INITIAL_CONTRIBUTED_AMOUNT / 2);

        ts::next_tx(scenario, CAROL);
        {
            governance::create_proposal(
                &mut governance,
                b"Refund",
                b"Initiate Refund",
                PRefund,
                option::none<u64>(),
                &clock,
                ts::ctx(scenario)
            );
        };

        let proposal_id = governance::get_proposal_id_by_index(&governance, 0);

        ts::next_tx(scenario, BOB);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };
        ts::next_tx(scenario, CAROL);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };
        ts::next_tx(scenario, DAVID);
        {
            governance::vote_proposal(&mut governance, proposal_id, VFor, ts::ctx(scenario));
        };

        clock::increment_for_testing(&mut clock, PROPOSAL_DURATION + 1);
        ts::next_tx(scenario, CAROL);
        {
            governance::end_proposal(&mut governance, proposal_id, &clock);
            governance::execute_proposal(&mut governance, proposal_id, &clock);
        };

        ts::next_tx(scenario, BOB);
        {
            let project_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == BOB_CONTRIBUTION / 2, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        ts::next_tx(scenario, CAROL);
        {
            let project_coin = governance::withdraw_coin(&mut governance, CAROL_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == CAROL_CONTRIBUTION / 2, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        ts::next_tx(scenario, DAVID);
        {
            let project_coin = governance::withdraw_coin(&mut governance, DAVID_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            assert!(coin::value(&raised_coin) == DAVID_CONTRIBUTION / 2, 1);
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun claim_refund_governance_ongoing() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(
            scenario,
            ALICE
        );

        ts::next_tx(scenario, BOB);
        {
            let project_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION, ts::ctx(scenario));
            let raised_coin = governance::claim_refund(&mut governance, project_coin, ts::ctx(scenario));
            balance::destroy_for_testing(coin::into_balance(raised_coin));
        };

        end_scenario(governance, clock, scenario_val)
    }

    // Withdraw funds (project creator)
    #[test]
    fun withdraw_funds() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        let tap_rate = 100;
        governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
        clock::increment_for_testing(&mut clock, 1);

        ts::next_tx(scenario, ALICE);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            assert!(coin::value(&coins) == tap_rate, 0);
            coin::burn_for_testing(coins);
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test]
    fun withdraw_fund_varying_tap_rate() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        let total_withdrawable = 0;

        ts::next_tx(scenario, ALICE);
        {
            let tap_rate = 100;
            let time = 10;
            governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
            clock::increment_for_testing(&mut clock, time);
            total_withdrawable = total_withdrawable + tap_rate * time;
        };

        ts::next_tx(scenario, ALICE);
        {
            let tap_rate = 50;
            let time = 20;
            governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
            clock::increment_for_testing(&mut clock, time);
            total_withdrawable = total_withdrawable + tap_rate * time;
        };

        ts::next_tx(scenario, ALICE);
        {
            let tap_rate = 40;
            let time = 30;
            governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
            clock::increment_for_testing(&mut clock, time);
            total_withdrawable = total_withdrawable + tap_rate * time;
        };

        ts::next_tx(scenario, ALICE);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            assert!(coin::value(&coins) == total_withdrawable, 0);
            assert!(coin::value(&coins) == 100 * 10 + 50 * 20 + 40 * 30, 0);
            coin::burn_for_testing(coins);
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun withdraw_funds_governance_not_in_progress() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        governance::set_governance_ongoing_status(&mut governance, false);

        ts::next_tx(scenario, ALICE);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            coin::burn_for_testing(coins);
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun withdraw_funds_invalid_sender() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        let tap_rate = 100;
        governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
        clock::increment_for_testing(&mut clock, 1);

        ts::next_tx(scenario, BOB);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            coin::burn_for_testing(coins);
        };

        end_scenario(governance, clock, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun withdraw_funds_no_funds_withdrawable() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        let tap_rate = 100;
        governance::simulate_tap_adjustment(&mut governance, &clock, tap_rate);
        clock::increment_for_testing(&mut clock, 1);

        ts::next_tx(scenario, ALICE);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            coin::burn_for_testing(coins);
        };

        ts::next_tx(scenario, ALICE);
        {
            let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
            coin::burn_for_testing(coins);
        };

        end_scenario(governance, clock, scenario_val);
    }
}