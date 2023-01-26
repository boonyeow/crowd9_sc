#[test_only]

module crowd9_sc::ob_tests{
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::nft::{Project, Nft};
    // use crowd9_sc::my_module::{Self, Card};
    use crowd9_sc::ob::{Self, Market, CLOB};
    use crowd9_sc::crit_bit_u64::{Self as cb};
    use std::debug;
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::object::{Self};
    use sui::transfer::{Self};

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    fun hello_world(){
        debug::print(&b"hi");
    }

    fun init_campaign(scenario: &mut Scenario): (Campaign, OwnerCap){
        ts::next_tx(scenario, ADMIN);
        ino::create_campaign(b"The One", b"Description", 100, 1, 1, 20, ts::ctx(scenario));
        ts::next_tx(scenario, ADMIN);
        let campaign = ts::take_shared<Campaign>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, ADMIN);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &owner_cap, ts::ctx(scenario));

        ts::next_tx(scenario, ALICE);
        ino::contribute(&mut campaign, 100, take_coins(scenario, ALICE, 100), ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 53, take_coins(scenario, BOB, 53), ts::ctx(scenario));

        ts::next_tx(scenario, CAROL);
        ino::contribute(&mut campaign, 23, take_coins(scenario, CAROL, 23), ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));
        (campaign, owner_cap)
    }

    /// funding_goal = 100, price_per_nft = 1;
    /// ALICE = 100, BOB = 53, CAROL = 23
    fun init_ob(scenario: &mut Scenario, alice_qty:u64, bob_qty:u64, carol_qty:u64): (Project, Market, CLOB){
        ts::next_tx(scenario, ADMIN);
        ob::init_test(ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let market = ts::take_shared<Market>(scenario);

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
        ts::return_to_address(ADMIN, owner_cap);
        ts::return_shared<Campaign>(campaign);
        let project = ts::take_shared<Project>(scenario);

        ts::next_tx(scenario, ADMIN);
        let project_id = object::id(&project);
        ob::create_ob_test(project_id, &mut market, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let clob = ts::take_shared<CLOB>(scenario);

        (project, market, clob)
    }

    fun init_test_accounts(scenario: &mut Scenario, value: u64) {
        ts::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), CAROL);
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user:address, amount: u64) : Coin<T>{
        ts::next_tx(scenario, user);
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin= coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun init_ask(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project, user:address, price:u64, amount:u64){
        let nft = ts::take_from_address<Nft>(scenario, user);
        ob::create_ask(clob, project, nft, amount, price, ts::ctx(scenario));
        assert!(cb::has_key(ob::get_asks_tree(clob), price), 0);
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(clob), price);
        assert!(total_volume == amount, 0);
        assert!(ob::get_ask_volume(orders) == amount, 0);
    }

    fun init_bid(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project, user:address, paid_amount:u64, price:u64,  bid_amount:u64){
        let coins = take_coins<SUI>(scenario, user, paid_amount);
        assert!(!cb::has_key(ob::get_bids_tree(clob), price), 0);
        ob::create_bid(clob, project, coins, bid_amount, price, ts::ctx(scenario));
        assert!(cb::has_key(ob::get_bids_tree(clob), price), 0);
        let (total_volume, orders) = ob::get_OO(ob::get_bids_tree(clob), price);
        assert!(total_volume == bid_amount, 0);
        assert!(ob::get_bid_volume(orders) == bid_amount, 0);
    }

    #[test]
    fun create_bids(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);

        // Clean State
        let cumulative_volume_at_5= 0;
        let cumulative_volume_at_7 = 0;

        // Create ask for the first time
        ts::next_tx(scenario, ALICE);
        {
            let nft = ts::take_from_address<Nft>(scenario, ALICE);
            let price = 5;
            let amount = 5;
            assert!(!cb::has_key(ob::get_asks_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_ask(&mut clob, &mut project, nft, amount, price, ts::ctx(scenario));

            assert!(cb::has_key(ob::get_asks_tree(&clob), price), 0); // Expected: key (price) should exist
            let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
            assert!(total_volume == ob::get_ask_volume(orders), 0); // Check total_volume correspond to cumulative ask volume
            assert!(total_volume == cumulative_volume_at_5 + amount, 0); // Check if total_volume is correct
            assert!(vector::length(orders) == 1, 0); // Check orders vector has been updated
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };
        assert!(cumulative_volume_at_5 == 5, 0);

        // Create ask again at the same price_level
        ts::next_tx(scenario, ALICE);
        {
            let nft = ts::take_from_address<Nft>(scenario, ALICE);
            let price = 5;
            let amount = 5;
            assert!(cb::has_key(ob::get_asks_tree(&clob), price), 1); // Expected: key (price) should exist
            ob::create_ask(&mut clob, &mut project, nft, amount, price, ts::ctx(scenario));
            let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
            assert!(total_volume == ob::get_ask_volume(orders), 0); // Check total_volume correspond to cumulative ask volume
            assert!(total_volume == cumulative_volume_at_5 + amount, 0); // Check total_volume is correct
            assert!(vector::length(orders) == 2, 0); // Check orders vector has been updated
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };
        assert!(cumulative_volume_at_5 == 10, 0);

        // Create ask again at a different price_level
        ts::next_tx(scenario, ALICE);
        {
            let nft = ts::take_from_address<Nft>(scenario, ALICE);
            let price = 7;
            let amount = 5;
            assert!(!cb::has_key(ob::get_asks_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_ask(&mut clob, &mut project, nft, amount, price, ts::ctx(scenario));
            let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
            assert!(total_volume == ob::get_ask_volume(orders), 0); // Check total_volume correspond to cumulative ask volume
            assert!(total_volume == cumulative_volume_at_7 + amount, 0); // Check total_volume is correct
            assert!(vector::length(orders) == 1, 0); // Check orders vector has been updated
            cumulative_volume_at_7 = cumulative_volume_at_7 + amount;
        };
        assert!(cumulative_volume_at_7 == 5, 0);


        /*
        // Order book
        Ask:{
            price_level: {
                OO(price=5, total_volume=10): [Ask(ALICE, 5), Ask(ALICE, 5)],
                OO(price=7, total_volume=5): [Ask(ALICE,5)]
            }
        }
        */

        // Create bid
        ts::next_tx(scenario, BOB);
        {
            let price = 4;
            let amount = 10;
            let bid_offer = take_coins<SUI>(scenario, BOB, price*amount);
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
            assert!(cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist

        };


        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    // #[test]
    // fun create_multiple_bids_same_price_same_user(){
    //
    // }
    //
    // #[test]
    // fun create_multiple_bids_same_price_different_user(){
    //
    // }
    //
    // #[test]
    // fun create_multiple_bids_different_price(){
    //
    // }
    //
    //
    // #[test]
    // fun test_fn(){
    //     let scenario_val = ts::begin(ADMIN);
    //     let scenario = &mut scenario_val;
    //     let coins_to_mint = 1000;
    //     init_test_accounts(scenario, coins_to_mint);
    //
    //     let (project, market, clob) = init_ob(scenario, 100, 53, 23);
    //     ts::next_tx(scenario, ALICE);
    //
    //     init_ask(scenario, &mut clob, &mut project, ALICE, 5, 100);
    //     init_ask(scenario, &mut clob, &mut project, BOB, 3, 53);
    //     init_ask(scenario, &mut clob, &mut project, CAROL, 2,23);
    //
    //     ts::next_tx(scenario, ADMIN);
    //     ob::create_bid(&mut clob, &mut project, take_coins<SUI>(scenario, ADMIN, 3*76), 76, 3, ts::ctx(scenario));
    //
    //     // perform check here
    //
    //     // debug::print(&clob);
    //
    //     ts::return_shared(project);
    //     ts::return_shared(market);
    //     ts::return_shared(clob);
    //     ts::end(scenario_val);
    // }
}