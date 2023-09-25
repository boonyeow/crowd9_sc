#[allow(unused_const, unused_function, unused_use)]
#[test_only]
module crowd9_sc::governance_tests {
    use crowd9_sc::governance::{Self, Governance, DelegationInfo};
    use crowd9_sc::campaign::{Self, Campaign, OwnerCap, verify_campaign_status};
    use crowd9_sc::coin_manager::{Self, AdminCap, CoinBag};
    use sui::test_scenario::{Self as ts, Scenario, take_shared, take_from_address};
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

    struct TEST_COIN has drop {}

    fun init_governance<X, Y>(scenario: &mut Scenario, user: address): (Governance<X, Y>, Clock) {
        ts::next_tx(scenario, user);
        let contributed_amount = BOB_CONTRIBUTION + BOB_CONTRIBUTION + DAVID_CONTRIBUTION;
        let contributions: LinkedTable<address, u64> = linked_table::new(ts::ctx(scenario));
        linked_table::push_back(&mut contributions, BOB, BOB_CONTRIBUTION);
        linked_table::push_back(&mut contributions, CAROL, CAROL_CONTRIBUTION);
        linked_table::push_back(&mut contributions, DAVID, DAVID_CONTRIBUTION);
        let scale_factor = 1;

        let clock = clock::create_for_testing(ts::ctx(scenario));
        let governance = governance::create_governance(
            user,
            balance::create_for_testing<SUI>(contributed_amount),
            balance::create_for_testing<TEST_COIN>(contributed_amount),
            contributions,
            scale_factor,
            &clock,
            ts::ctx(scenario)
        );

        clock::share_for_testing(clock);
        transfer::public_share_object(governance);


        ts::next_tx(scenario, ALICE);
        let governance = take_shared<Governance<X, Y>>(scenario);
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
        {};

        end_scenario(governance, clock, scenario_val);
    }

    #[test]
    fun withdraw_coin_full_balance() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun withdraw_coin_invalid_user() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun withdraw_coin_insufficient_balance() {}

    // Deposit Coin
    #[test]
    fun deposit_coin() {}

    // Delegate voting power to user
    #[test]
    fun delegate_to_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        // Before delegating
        {
            let delegations = governance::get_delegations(&governance);
            let (current_voting_power, delegate_to, delegated_by) = governance::get_delegation_info(
                table::borrow(delegations, BOB)
            );
            assert!(current_voting_power == BOB_CONTRIBUTION, 0);
            assert!(option::is_none(&delegate_to), 1);
            assert!(vector::is_empty(&delegated_by), 2);
        };

        // Delegate
        ts::next_tx(scenario, BOB);
        governance::delegate(&mut governance, CAROL, ts::ctx(scenario));

        // After delegating
        ts::next_tx(scenario, BOB);
        {
            let delegations = governance::get_delegations(&governance);
            let bob_di = table::borrow(delegations, BOB);
            let (current_voting_power, delegate_to, delegated_by) = governance::get_delegation_info(bob_di);
            assert!(current_voting_power == 0, 0);
            assert!(*option::borrow(&delegate_to) == CAROL, 1);
            assert!(vector::is_empty(&delegated_by), 1);

            let carol_di = table::borrow(delegations, CAROL);
            let (current_voting_power, delegate_to, delegated_by) = governance::get_delegation_info(carol_di);
            assert!(current_voting_power == BOB_CONTRIBUTION + CAROL_CONTRIBUTION, 0);
            assert!(option::is_none(&delegate_to), 1);
            assert!(vector::contains(&delegated_by, &BOB), 2);
        };


        end_scenario(governance, clock, scenario_val)
    }

    #[test, expected_failure(abort_code = crowd9_sc::governance::ECircularDelegation)]
    fun delegate_invalid_circular() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun delegate_invalid_sender_has_no_deposit() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_invalid_sender_already_delegated() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_invalid_delegate_to_has_no_deposit() {}

    // Remove delegated voting power
    #[test]
    fun remove_delegate_from_user() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun remove_delegate_sender_has_no_deposit() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun remove_delegate_sender_has_not_delegated() {}

    // Create a proposal
    #[test]
    fun create_proposal() {}

    #[test]
    fun create_proposal_governance_creator() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun create_proposal_governance_inactive() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidParameter)]
    fun create_proposal_invalid_proposal_type() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun create_proposal_invalid_tap_rate() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun create_proposal_sender_has_no_deposit() {}

    // Vote on a proposal
    #[test]
    fun vote_proposal() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidVoteChoice)]
    fun vote_proposal_invalid_vote() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun vote_proposal_not_active() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::ENoPermission)]
    fun vote_proposal_sender_not_in_snapshot() {}

    #[test, expected_failure(abort_code = crowd9_sc::governance::EDuplicatedVotes)]
    fun vote_proposal_sender_casting_same_vote() {}

    // End a proposal

    // Execute a proposal

    // Cancel a proposal

    // Claim refund

    // Withdraw funds (project creator)
    #[test]
    fun withdraw_funds_success() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (governance, clock) = init_governance<SUI, TEST_COIN>(scenario, ALICE);

        governance::set_tap_rate(&mut governance, 100);
        clock::increment_for_testing(&mut clock, 1);

        let coins = governance::withdraw_funds(&mut governance, &clock, ts::ctx(scenario));
        assert!(coin::value(&coins) == 100, 0);

        coin::burn_for_testing(coins);
        end_scenario(governance, clock, scenario_val);
    }
}