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
    use crowd9_sc::nft::{Self,Project, Nft};
    use crowd9_sc::governance::{Self};
    use crowd9_sc::dict::{Self};
    // use crowd9_sc::governance::{Governance, Proposal};
    // use std::debug;

    /// Constants
    // Status Codes
    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const ADMIN: address = @0xCAFE;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xAAAB;
    const CAROL: address = @0xAAAC;
    const DAVID: address = @0xAAAD;

    fun init_test_accounts(scenario: &mut Scenario, value: u64) {
        ts::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), CAROL);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), DAVID);
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user:address, amount: u64) : Coin<T>{
        ts::next_tx(scenario, user);
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin= coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun init_governance(scenario: &mut Scenario, alice_qty:u64, bob_qty:u64, carol_qty:u64): (Project, Governance){
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

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let project = ts::take_shared<Project>(scenario);
        let governance = ts::take_shared<Governance>(scenario);

        ts::next_tx(scenario, ALICE);
        governance::withdraw_nft(&mut governance, &mut project, alice_qty, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        governance::withdraw_nft(&mut governance, &mut project, bob_qty, ts::ctx(scenario));

        ts::next_tx(scenario, CAROL);
        governance::withdraw_nft(&mut governance, &mut project, carol_qty, ts::ctx(scenario));

        ts::return_to_address(ADMIN, owner_cap);
        ts::return_shared(campaign);
        (project, governance)
    }

    use std::vector;
    #[test]
    fun deposit_nft(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        // A -> 100, B -> 53, C -> 23
        let (project, governance) = init_governance(scenario, 100, 53, 23);

        ts::next_tx(scenario,ADMIN);
        let nft_store = governance::get_nft_store(&mut governance);

        ts::next_tx(scenario, ALICE);
        {
            let nft = ts::take_from_address<Nft>(scenario, ALICE);
            std::debug::print(&nft);
            let nft_value = nft::nft_value(&nft);
            let nfts = vector::singleton(nft);
            assert!(!dict::contains(nft_store, ALICE), 0); // should not be in nft_store
            governance::deposit_nft(&mut governance, &mut project, nfts, nft_value, ts::ctx(scenario));
            assert!(dict::contains(nft_store, ALICE), 0); // should be in nft_store
        };

        ts::return_shared(governance);
        ts::return_shared(project);
        ts::end(scenario_val);
    }

    //tc2 - deposit nft but amount mismatch i.e. nft{value:10} but amount = 5, or 15



    // delegate fn
    // tc1 delegation successful
    // tc2 tried to delegate but governance is currently on refund mode
    // tc3 tried to delegate but user has not deposited any nft
    // tc4 tried to delegate to someone who has not deposited any nft
    // tc5 tried to delegate but theres circular delegation i.e. A->B, B->C, C tries to delegate to A

    // remove delegatee fn
    // tc1 delegation freeze cuz of refund mode
    // tc2 sender must be in nft_store & di.delegate_to should be is_some() -> indicates that theres an existing delegatee
    // perform a check to make sure counts are correct

    // deposit_nft fn

}