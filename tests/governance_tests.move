#[test_only]
module crowd9_sc::governance_tests {
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::governance::{ Governance};
    use sui::transfer;
    // use sui::table::{Self, Table};
    // use sui::vec_set::{Self, VecSet};
    // use sui::object::{Self, ID};
    // use sui::tx_context::{TxContext};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self as ts, Scenario};
    use crowd9_sc::nft::{Project, Nft};
    use crowd9_sc::governance::{Self};
    // use crowd9_sc::dict::{Self};
    // use crowd9_sc::governance::{Governance, Proposal};
    use std::vector;

    /// Constants
    // Status Codes
    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const ADMIN: address = @0xCAFE;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xAAAB;
    const CAROL: address = @0xAAAC;
    const DAVID: address = @0xAAAD;
    const ERIN: address = @0xAAAE;
    const FRANK: address = @0xAAAF;

    fun init_test_accounts(scenario: &mut Scenario, value: u64) {
        ts::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), CAROL);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), DAVID);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ERIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), FRANK);
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user:address, amount: u64) : Coin<T>{
        ts::next_tx(scenario, user);
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin= coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun init_governance(
        scenario: &mut Scenario,
        alice_qty:u64,
        bob_qty:u64,
        carol_qty:u64,
        david_qty:u64,
        erin_qty:u64,
        frank_qty:u64
    ): (Project, Governance) {
        ts::next_tx(scenario, ADMIN);
        ino::create_campaign(b"The One", b"Description", 100, 1, 1, 20, ts::ctx(scenario));
        ts::next_tx(scenario, ADMIN);
        let campaign = ts::take_shared<Campaign>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, ADMIN);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &owner_cap, ts::ctx(scenario));

        ts::next_tx(scenario, ALICE);
        ino::contribute(&mut campaign, alice_qty, take_coins(scenario, ALICE, alice_qty), ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, bob_qty, take_coins(scenario, BOB, bob_qty), ts::ctx(scenario));

        ts::next_tx(scenario, CAROL);
        ino::contribute(&mut campaign, carol_qty, take_coins(scenario, CAROL, carol_qty), ts::ctx(scenario));

        ts::next_tx(scenario, DAVID);
        ino::contribute(&mut campaign, david_qty, take_coins(scenario, DAVID, david_qty), ts::ctx(scenario));

        ts::next_tx(scenario, ERIN);
        ino::contribute(&mut campaign, erin_qty, take_coins(scenario, ERIN, erin_qty), ts::ctx(scenario));

        ts::next_tx(scenario, FRANK);
        ino::contribute(&mut campaign, frank_qty, take_coins(scenario, FRANK, frank_qty), ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let project = ts::take_shared<Project>(scenario);
        let governance = ts::take_shared<Governance>(scenario);

        ts::return_to_address(ADMIN, owner_cap);
        ts::return_shared(campaign);
        (project, governance)
    }

    fun take_nft_from_store(scenario: &mut Scenario, governance: &mut Governance, project: &mut Project, qty: u64, user: address): Nft{
        ts::next_tx(scenario, user);
        governance::withdraw_nft(governance, project, qty, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        ts::take_from_address<Nft>(scenario, user)
    }

    #[test]
    fun withdraw_nfts(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        // Withdraw all nfts
        ts::next_tx(scenario, ALICE);
        {
            // Before withdrawing all nfts
            assert!(governance::is_user_in_nft_store(&governance, ALICE), 0);
            assert!(governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::find_delegation_root(&governance, ALICE) == ALICE, 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == alice_qty, 0);

            // After withdrawing all nfts
            governance::withdraw_nft(&mut governance, &mut project, alice_qty, ts::ctx(scenario));
            assert!(!governance::is_user_in_nft_store(&governance, ALICE), 0);
            assert!(!governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == 0, 0);
            assert!(governance::get_voting_power(&governance, ALICE) == 0, 0);
        };

        // Withdraw some nfts
        ts::next_tx(scenario, BOB);
        {
            // Before withdrawing some nfts
            assert!(governance::is_user_in_nft_store(&governance, BOB), 0);
            assert!(governance::is_user_in_delegations(&governance, BOB), 0);
            assert!(governance::find_delegation_root(&governance, BOB) == BOB, 0);
            assert!(governance::get_nft_value_in_store(&governance, BOB) == bob_qty, 0);

            // After withdrawing some nfts
            governance::withdraw_nft(&mut governance, &mut project, 33, ts::ctx(scenario));
            assert!(governance::is_user_in_nft_store(&governance, BOB), 0);
            assert!(governance::is_user_in_delegations(&governance, BOB), 0);
            assert!(governance::find_delegation_root(&governance, BOB) == BOB, 0);
            assert!(governance::get_nft_value_in_store(&governance, BOB) == bob_qty - 33, 0);
            assert!(governance::get_voting_power(&governance, BOB) == bob_qty - 33, 0);
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::EUnexpectedError)]
    fun withdraw_nft_more_than_stored(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        ts::next_tx(scenario, ALICE);
        governance::withdraw_nft(&mut governance, &mut project, alice_qty+1, ts::ctx(scenario));

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun withdraw_nft_but_stored_none(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        ts::next_tx(scenario, ADMIN);
        governance::withdraw_nft(&mut governance, &mut project, alice_qty+1, ts::ctx(scenario));

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    #[test]
    fun deposit_nft(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        ts::next_tx(scenario, ALICE);
        {
            let nft_value = governance::get_nft_value_in_store(&governance, ALICE);
            let nft = take_nft_from_store(scenario, &mut governance, &mut project, nft_value, ALICE);
            let to_take = 10;
            let split_nft = governance::take(&mut project, &mut nft, to_take, ts::ctx(scenario));

            let nfts = vector::singleton(nft);
            assert!(!governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == 0, 0); // should not be in nft_store
            assert!(governance::get_voting_power(&governance, ALICE) == 0, 0);

            governance::deposit_nft(&mut governance, &mut project, nfts, nft_value - to_take, ts::ctx(scenario));
            assert!(governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == nft_value - to_take, 0);
            assert!(governance::get_voting_power(&governance, ALICE) == nft_value - to_take, 0);

            ts::next_tx(scenario, ALICE);
            let nfts = vector::singleton(split_nft);
            governance::deposit_nft(&mut governance, &mut project, nfts, to_take, ts::ctx(scenario));
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == nft_value, 0);
            assert!(governance::get_voting_power(&governance, ALICE) == nft_value, 0)
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    // Successful delegate
    // Tests delegate and removing delegatee
    #[test]
    fun delegate() {
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        // A (100) -> B (53)
        // B's total voting power = 100 + 53 = 153
        ts::next_tx(scenario, ALICE);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        // A: 100 - 100 = 0
        // B: 53 + 100 = 153
        // C: 23
        // D: 10
        // E: 20
        // F: 30
        assert!(governance::get_voting_power(&governance, ALICE) == 0, 0);
        assert!(governance::get_voting_power(&governance, BOB) == alice_qty + bob_qty, 0);
        assert!(governance::is_delegated_to_address(&governance, ALICE, BOB), 0);
        assert!(governance::is_delegated_by(&governance, ALICE, BOB), 0);

        // C (23) -> A (0) -> B (153)
        // B's total voting power = 153 + 23
        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, ALICE, ts::ctx(scenario));
        };

        // A: 0 + 23 - 23 = 0
        // B: 153 + 23 = 176
        // C: 23 - 23 = 0
        // D: 10
        // E: 20
        // F: 30
        assert!(governance::get_voting_power(&governance, CAROL) == 0, 0);
        assert!(governance::get_voting_power(&governance, BOB) == alice_qty + bob_qty + carol_qty, 0);
        assert!(governance::is_delegated_to_address(&governance, CAROL, ALICE), 0);
        assert!(governance::is_delegated_by(&governance, CAROL, ALICE), 0);

        // E (20) -> A (0) -> B (176)
        // B's total voting power = 176 + 20
        ts::next_tx(scenario, ERIN);
        {
            governance::delegate(&mut governance, ALICE, ts::ctx(scenario));
        };

        // A: 0 + 20 - 20 = 0
        // B: 176 + 20 = 196
        // C: 0
        // D: 10
        // E: 20 - 20 = 0
        // F: 30
        assert!(governance::get_voting_power(&governance, ERIN) == 0, 0);
        assert!(governance::get_voting_power(&governance, BOB) == alice_qty + bob_qty + carol_qty + erin_qty, 0);
        assert!(governance::is_delegated_to_address(&governance, ERIN, ALICE), 0);
        assert!(governance::is_delegated_by(&governance, ERIN, ALICE), 0);

        // A -> null
        // B's total voting power = 153 + 23
        ts::next_tx(scenario, ALICE);
        {
            governance::remove_delegatee(&mut governance, ts::ctx(scenario));
        };

        // A: 0 + 143 = 143
        // B: 196 - 143 = 53
        // C: 0
        // D: 10
        // E: 0
        // F: 30
        assert!(governance::get_voting_power(&governance, ALICE) == alice_qty + carol_qty + erin_qty, 0);
        assert!(governance::get_voting_power(&governance, BOB) == bob_qty, 0);
        assert!(!governance::is_delegating(&governance, ALICE), 0);
        assert!(!governance::is_delegated_by(&governance, ALICE, BOB), 0);
        assert!(governance::is_delegated_by(&governance, CAROL, ALICE), 0);
        assert!(governance::is_delegated_by(&governance, ERIN, ALICE), 0);

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    // Test circular delegation A->B->C, C->A Fails
    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::ECircularDelegation)]
    fun circular_delegation() {
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        ts::next_tx(scenario, ALICE);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        assert!(governance::is_delegated_to_address(&governance, ALICE, BOB), 0);
        assert!(governance::is_delegated_by(&governance, ALICE, BOB), 0);

        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, CAROL, ts::ctx(scenario));
        };

        assert!(governance::is_delegated_to_address(&governance, BOB, CAROL), 0);
        assert!(governance::is_delegated_by(&governance, BOB, CAROL), 0);

        ts::next_tx(scenario, CAROL);
        {
            governance::delegate(&mut governance, ALICE, ts::ctx(scenario));
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    // User tries to delegate without any NFT in nft_store
    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_without_depositing() {
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        // Withdraw ALICE's nfts
        ts::next_tx(scenario, ALICE);
        {
            governance::withdraw_nft(&mut governance, &mut project, alice_qty, ts::ctx(scenario));

            // After withdrawing all nfts
            assert!(!governance::is_user_in_nft_store(&governance, ALICE), 0);
            assert!(!governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == 0, 0);
            assert!(governance::get_voting_power(&governance, ALICE) == 0, 0);
        };

        ts::next_tx(scenario, ALICE);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_to_user_without_nft() {
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        // Withdraw ALICE's nfts
        ts::next_tx(scenario, ALICE);
        {
            governance::withdraw_nft(&mut governance, &mut project, alice_qty, ts::ctx(scenario));

            // After withdrawing all nfts
            assert!(!governance::is_user_in_nft_store(&governance, ALICE), 0);
            assert!(!governance::is_user_in_delegations(&governance, ALICE), 0);
            assert!(governance::get_nft_value_in_store(&governance, ALICE) == 0, 0);
            assert!(governance::get_voting_power(&governance, ALICE) == 0, 0);
        };

        ts::next_tx(scenario, BOB);
        {
            governance::delegate(&mut governance, ALICE, ts::ctx(scenario));
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::governance::EInvalidAction)]
    fun delegate_on_refund_mode() {
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23, D -> 10, E -> 20, F -> 30
        let (alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty) = (100, 53, 23, 10, 20, 30);
        let (project, governance) = init_governance(scenario, alice_qty, bob_qty, carol_qty, david_qty, erin_qty, frank_qty);

        {
            governance::set_refund_mode(&mut governance, &mut project);
        };

        ts::next_tx(scenario, ALICE);
        {
            governance::delegate(&mut governance, BOB, ts::ctx(scenario));
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    //tc2 - deposit nft but amount mismatch i.e. nft{value:10} but amount = 5, or 15

    // remove delegatee fn
    // tc1 delegation freeze cuz of refund mode
    // tc2 sender must be in nft_store & di.delegate_to should be is_some() -> indicates that theres an existing delegatee
    // perform a check to make sure counts are correct

    // deposit_nft fn

}