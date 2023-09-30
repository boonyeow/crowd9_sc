#[allow(unused_const, unused_function, unused_use)]
#[test_only]
module crowd9_sc::governance_tests {
    use crowd9_sc::governance::{Self, Governance, DelegationInfo};
    use crowd9_sc::campaign::{Self, Campaign, OwnerCap};
    use crowd9_sc::coin_manager::{Self, AdminCap, CoinBag};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::sui::SUI;
    use std::option::{Self};
    use sui::tx_context;
    use sui::coin::{Self, Coin, balance, CoinMetadata};
    use sui::transfer::{Self};
    use sui::clock::{Self, Clock};
    use std::vector::{Self};
    use sui::linked_table;
    use sui::linked_table::LinkedTable;
    use sui::balance;
    use sui::table;
    use sui::math;

    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const CAROL: address = @0xCCCC;
    const DAVID: address = @0xDDDD;
    const ERIN: address = @0xEEEE;

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
    const INITIAL_CONTRIBUTED_AMOUNT: u64 = 20000 + 25000 + 30000;

    struct TEST_COIN has drop {}

    fun init_governance<X, Y>(scenario: &mut Scenario, user: address): (Governance<X, Y>, Clock) {
        ts::next_tx(scenario, user);
        let contributions: LinkedTable<address, u64> = linked_table::new(ts::ctx(scenario));
        linked_table::push_back(&mut contributions, BOB, BOB_CONTRIBUTION);
        linked_table::push_back(&mut contributions, CAROL, CAROL_CONTRIBUTION);
        linked_table::push_back(&mut contributions, DAVID, DAVID_CONTRIBUTION);
        let scale_factor = 1;

        let clock = clock::create_for_testing(ts::ctx(scenario));
        let governance = governance::create_governance(
            user,
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
            assert!(governance::check_user_voting_power(&governance, BOB, BOB_CONTRIBUTION), 0);
            assert!(governance::check_user_delegate_to(&governance, BOB, option::none<address>()), 1);
            assert!(governance::check_user_voting_power(&governance, CAROL, CAROL_CONTRIBUTION), 0);
            assert!(!governance::check_user_in_delegate_by(&governance, CAROL, BOB), 1)
        };

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        {
            assert!(governance::check_user_voting_power(&governance, BOB, 0), 0);
            assert!(governance::check_user_delegate_to(&governance, BOB, option::some(CAROL)), 1);
            assert!(governance::check_user_voting_power(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION), 0);
            assert!(governance::check_user_delegate_to(&governance, CAROL, option::none<address>()), 1);
            assert!(governance::check_user_in_delegate_by(&governance, CAROL, BOB), 2);
        };

        end_scenario(governance, clock, scenario_val)
    }

    #[test]
    fun delegate_then_withdraw_full() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        let carol_voting_power;
        let bob_voting_power;

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        {
            let delegations = governance::get_delegations(&governance);
            let bob_di = table::borrow(delegations, BOB);
            let (current_voting_power, _, _) = governance::get_delegation_info(bob_di);
            bob_voting_power = current_voting_power;

            let carol_di = table::borrow(delegations, CAROL);
            let (current_voting_power, _, _) = governance::get_delegation_info(carol_di);
            carol_voting_power = current_voting_power;
        };

        assert!(bob_voting_power == 0, 1);
        assert!(carol_voting_power == BOB_CONTRIBUTION + CAROL_CONTRIBUTION, 1);

        // Bob withdraw
        ts::next_tx(scenario, BOB);
        {
            let withdrawn_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION, ts::ctx(scenario));
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        // After delegating
        ts::next_tx(scenario, CAROL);
        {
            let delegations = governance::get_delegations(&governance);
            let carol_di = table::borrow(delegations, CAROL);
            let (current_voting_power, _, _) = governance::get_delegation_info(carol_di);
            carol_voting_power = current_voting_power;
        };

        assert!(carol_voting_power == CAROL_CONTRIBUTION, 1);

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
        assert!(governance::check_user_voting_power(&governance, BOB, 0), 0);
        assert!(governance::check_user_delegate_to(&governance, BOB, option::some(CAROL)), 1);
        assert!(governance::check_user_voting_power(&governance, CAROL, BOB_CONTRIBUTION + CAROL_CONTRIBUTION), 0);
        assert!(governance::check_user_delegate_to(&governance, CAROL, option::none<address>()), 1);
        assert!(governance::check_user_in_delegate_by(&governance, CAROL, BOB), 2);

        // Bob withdraw
        ts::next_tx(scenario, BOB);
        {
            let withdrawn_coin = governance::withdraw_coin(&mut governance, BOB_CONTRIBUTION - 1, ts::ctx(scenario));
            balance::destroy_for_testing(coin::into_balance(withdrawn_coin));
        };

        ts::next_tx(scenario, CAROL);
        assert!(governance::check_user_voting_power(&governance, CAROL, CAROL_CONTRIBUTION + 1), 0);

        end_scenario(governance, clock, scenario_val)
    }
    //
    // #[test]
    // fun delegate_delegatee_withdraw() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ECircularDelegation)]
    // fun delegate_invalid_circular() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    // fun delegate_invalid_sender_has_no_deposit() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun delegate_invalid_sender_already_delegated() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun delegate_invalid_delegate_to_has_no_deposit() {}
    //
    // // Remove delegated voting power
    // #[test]
    // fun remove_delegate_from_user() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    // fun remove_delegate_sender_has_no_deposit() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun remove_delegate_sender_has_not_delegated() {}
    //
    // // Create a proposal
    // #[test]
    // fun create_proposal() {}
    //
    // #[test]
    // fun create_proposal_governance_creator() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun create_proposal_governance_inactive() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidParameter)]
    // fun create_proposal_invalid_proposal_type() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun create_proposal_invalid_tap_rate() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    // fun create_proposal_sender_has_no_deposit() {}
    //
    // // Vote on a proposal
    // #[test]
    // fun vote_proposal() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidVoteChoice)]
    // fun vote_proposal_invalid_vote() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun vote_proposal_not_active() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    // fun vote_proposal_sender_not_in_snapshot() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EDuplicatedVotes)]
    // fun vote_proposal_sender_casting_same_vote() {}
    //
    // // End a proposal
    // #[test]
    // fun end_proposal_success() {}
    //
    // #[test]
    // fun end_proposal_failure() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun end_proposal_invalid_status() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun end_proposal_before_proposal_end_time() {}
    //
    // // Execute a proposal
    // #[test]
    // fun execute_proposal_adjustment() {}
    //
    // #[test]
    // fun execute_proposal_refund() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun execute_proposal_invalid_status() {}
    //
    // // Cancel a proposal
    // #[test]
    // fun cancel_proposal() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun cancel_proposal_invalid_status() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    // fun cancel_proposal_no_permission() {}
    //
    // // Claim refund
    // #[test]
    // fun claim_refund() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun claim_refund_governance_ongoing() {}
    //
    // // Withdraw funds (project creator)
    // #[test]
    // fun withdraw_funds() {
    //     let scenario_val = ts::begin(ALICE);
    //     let scenario = &mut scenario_val;
    //     let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);
    //
    //     governance::set_tap_rate(&mut governance, 100);
    //     clock::increment_for_testing(&mut clock, 1);
    //
    //     let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
    //     assert!(coin::value(&coins) == 100, 0);
    //
    //     coin::burn_for_testing(coins);
    //     end_scenario(governance, clock, scenario_val);
    // }
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun withdraw_funds_governance_not_in_progress() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun withdraw_funds_invalid_sender() {}
    //
    // #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    // fun withdraw_funds_no_funds_withdrawable() {}
}