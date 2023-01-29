#[test_only]

module crowd9_sc::ob_tests{
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::nft::{Project, Nft, nft_value};
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

    fun create_new_bid(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project, user: address, cumulative_volume:u64, paid_amount:u64, price: u64, amount:u64, is_first: bool, updated_order_count:u64){
        ts::next_tx(scenario, user);
        let coins = take_coins<SUI>(scenario, user, paid_amount);
        if(is_first){
            assert!(!cb::has_key(ob::get_bids_tree(clob), price), 0);  // Expected: key (price) should not exist
        } else {
            assert!(cb::has_key(ob::get_bids_tree(clob), price), 0);  // Expected: key (price) should exist
        };

        ob::create_bid(clob, project, coins, amount, price, ts::ctx(scenario));
        assert!(cb::has_key(ob::get_bids_tree(clob), price), 0);  // Expected: key (price) should exist

        let (total_volume, orders) = ob::get_OO(ob::get_bids_tree(clob), price);
        assert!(total_volume == ob::get_bid_volume(orders), 0); // Check total_volume correspond to cumulative bid volume
        assert!(total_volume == cumulative_volume + amount, 0); // Check if total_volume is correct
        assert!(vector::length(orders) == updated_order_count, 0); // Check orders vector has been updated
    }

    fun init_bids(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project){
        /*
       // Initialized Bids
       Bids:{
           price_level: {
               OO(price=7, total_volume=9): [Bid(ALICE,3), Bid(BOB,6)],
               OO(price=6, total_volume=1): [Bid(CAROL,1)],
               OO(price=5, total_volume=10): [Bid(ALICE, 5), Bid(ALICE, 5)],
           }
       }
       */
        // Clean State
        let cumulative_volume_at_7 = 0;
        let cumulative_volume_at_6= 0;
        let cumulative_volume_at_5= 0;

        // Create bid where price_level=7
        {
            let price = 7;
            let amount = 3;
            create_new_bid(scenario, clob, project, ALICE, cumulative_volume_at_7, price*amount, price, amount, true, 1);
            cumulative_volume_at_7 = cumulative_volume_at_7 + amount;
        };

        // Create bid again where price_level=7
        {
            let price = 7;
            let amount = 6;
            create_new_bid(scenario, clob, project, BOB, cumulative_volume_at_7, price*amount, price, amount, false, 2);
            cumulative_volume_at_7 = cumulative_volume_at_7 + amount;
        };

        // Create bid where price_level=5
        {
            let price = 5;
            let amount = 5;
            create_new_bid(scenario, clob, project, ALICE, cumulative_volume_at_5, price*amount, price, amount, true, 1);
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };

        // Create bid again where price_level=5
        {
            let price = 5;
            let amount = 5;
            create_new_bid(scenario, clob, project, ALICE, cumulative_volume_at_5, price*amount, price, amount, false, 2);
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };

        // Create bid where price_level=6
        {
            let price = 6;
            let amount = 1;
            create_new_bid(scenario, clob, project, CAROL, cumulative_volume_at_6, price*amount, price, amount, true, 1);
            cumulative_volume_at_6 = cumulative_volume_at_6 + amount;
        };

        // sanity check
        assert!(cumulative_volume_at_5 == 10, 0);
        assert!(cumulative_volume_at_6 == 1, 0);
        assert!(cumulative_volume_at_7 == 9, 0);
    }

    fun create_new_ask(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project, user:address, cumulative_volume: u64,  price:u64, amount:u64, is_first: bool, updated_order_count: u64){
        ts::next_tx(scenario, user);
        let nft = ts::take_from_address<Nft>(scenario, user);
        if(is_first){
            assert!(!cb::has_key(ob::get_asks_tree(clob), price), 0);  // Expected: key (price) should not exist
        } else {
            assert!(cb::has_key(ob::get_asks_tree(clob), price), 0); // Expected: key (price) should exist
        };

        ob::create_ask(clob, project, nft, amount, price, ts::ctx(scenario));
        assert!(cb::has_key(ob::get_asks_tree(clob), price), 0); // Expected: key (price) should exist

        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(clob), price);
        assert!(total_volume == ob::get_ask_volume(orders), 0); // Check total_volume correspond to cumulative ask volume
        assert!(total_volume == cumulative_volume + amount, 0); // Check if total_volume is correct
        assert!(vector::length(orders) == updated_order_count, 0); // Check orders vector has been updated
    }

    fun init_asks(scenario: &mut Scenario, clob: &mut CLOB, project: &mut Project){
        /*
        // Initialized Asks
        Ask:{
            price_level: {
                OO(price=5, total_volume=10): [Ask(ALICE, 5), Ask(ALICE, 5)],
                OO(price=6, total_volume=1): [Ask(CAROL,1)],
                OO(price=7, total_volume=9): [Ask(ALICE,3), Ask(BOB,6)],
            }
        }
        */

        // Clean State
        let cumulative_volume_at_5= 0;
        let cumulative_volume_at_6= 0;
        let cumulative_volume_at_7 = 0;

        // Create ask where price_level=5
        {
            let price = 5;
            let amount = 5;
            create_new_ask(scenario, clob, project, ALICE, cumulative_volume_at_5, price, amount, true, 1);
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };

        // Create ask again where price_level=5
        {
            let price = 5;
            let amount = 5;
            create_new_ask(scenario, clob, project, ALICE, cumulative_volume_at_5, price, amount, false, 2);
            cumulative_volume_at_5 = cumulative_volume_at_5 + amount;
        };

        // Create ask where price_level=7
        {
            let price = 7;
            let amount = 3;
            create_new_ask(scenario, clob, project, ALICE, cumulative_volume_at_7, price, amount, true, 1);
            cumulative_volume_at_7 = cumulative_volume_at_7 + amount;
        };

        // Create ask again where price_level=7
        {
            let price = 7;
            let amount = 6;
            create_new_ask(scenario, clob, project, BOB, cumulative_volume_at_7, price, amount, false, 2);
            cumulative_volume_at_7 = cumulative_volume_at_7 + amount;
        };

        // Create ask where price_level=6
        {
            let price = 6;
            let amount = 1;
            create_new_ask(scenario, clob, project, CAROL, cumulative_volume_at_6, price, amount, true, 1);
            cumulative_volume_at_6 = cumulative_volume_at_6 + amount;
        };

        // sanity check
        assert!(cumulative_volume_at_5 == 10, 0);
        assert!(cumulative_volume_at_6 == 1, 0);
        assert!(cumulative_volume_at_7 == 9, 0);
    }

    #[test]
    fun create_bid_crossed_none(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, CAROL);
        {
            let price = 4;
            let amount = 10;
            let bid_offer = take_coins<SUI>(scenario, CAROL, price*amount);
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
            assert!(cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist
        };

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun create_bid_crossed_specific_ask(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, CAROL);
        {
            let price = 5;
            let amount = 5;
            let bid_offer = take_coins<SUI>(scenario, CAROL, price*amount);
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist because crossed perfectly
        };

        ts::next_tx(scenario, ADMIN);
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), 5);
        assert!(total_volume == 5, 0);
        assert!(vector::length(orders) == 1, 0);

        {
            // Get most recent Coin<SUI> received by ALICE
            let coins = ts::take_from_address<Coin<SUI>>(scenario, ALICE);
            assert!(coin::value(&coins) == 25, 0);
            ts::return_to_address(ALICE, coins);
        };

        {
            // Get most recent Nft received by CAROL
            let nfts = ts::take_from_address<Nft>(scenario, CAROL);
            assert!(nft_value(&nfts) == 5, 0);
            ts::return_to_address(CAROL, nfts);
        };

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun create_bid_crossed_entire_asks(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, CAROL);
        {
            let price = 5;
            let amount = 10;
            let bid_offer = take_coins<SUI>(scenario, CAROL, price*amount);
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
            assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist because crossed perfectly
        };

        ts::next_tx(scenario, ADMIN);
        let asks_tree = ob::get_asks_tree(&clob);
        assert!(!cb::has_key(asks_tree, 5), 0);

        // {
        //     // Get most recent Coin<SUI> received by ALICE
        //     let coins = ts::take_from_address<Coin<SUI>>(scenario, ALICE);
        //     assert!(coin::value(&coins) == 25, 0);
        //     ts::return_to_address(ALICE, coins);
        // };
        //
        // {
        //     // Get most recent Nft received by CAROL
        //     let nfts = ts::take_from_address<Nft>(scenario, CAROL);
        //     assert!(nft_value(&nfts) == 5, 0);
        //     ts::return_to_address(CAROL, nfts);
        // };

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun create_ask_crossed_none(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_bids(scenario, &mut clob, &mut project);

        // Create ask
        {
            let price = 10;
            let amount = 3;
            let nft = ts::take_from_address<Nft>(scenario, CAROL);
            assert!(!cb::has_key(ob::get_asks_tree(&clob), price), 0); // Expected: key (price) should not exist
            ob::create_ask(&mut clob, &mut project, nft, amount, price, ts::ctx(scenario));
            assert!(cb::has_key(ob::get_asks_tree(&clob), price), 0); // Expected: key (price) should exist
        };

        ts::next_tx(scenario, ADMIN);
        let asks_tree = ob::get_asks_tree(&clob);
        assert!(cb::has_key(asks_tree, 10), 0);
        let (total_volume, orders) = ob::get_OO(asks_tree, 10);
        assert!(total_volume == 3, 0);
        assert!(vector::length(orders) == 1, 0);


        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }
}