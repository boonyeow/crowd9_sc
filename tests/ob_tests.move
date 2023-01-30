#[test_only]

module crowd9_sc::ob_tests{
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::nft::{Self, Project, Nft};
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
    const DAVID: address = @0xAAAD;

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
        transfer::transfer(coin::mint_for_testing<SUI>(value, ts::ctx(scenario)), DAVID);
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

        // Create ask again where price_level=5
        {
            let price = 5;
            let amount = 2;
            create_new_ask(scenario, clob, project, BOB, cumulative_volume_at_5, price, amount, false, 3);
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
            let amount = 2;
            create_new_ask(scenario, clob, project, CAROL, cumulative_volume_at_6, price, amount, true, 1);
            cumulative_volume_at_6 = cumulative_volume_at_6 + amount;
        };

        // sanity check
        assert!(cumulative_volume_at_5 == 12, 0);
        assert!(cumulative_volume_at_6 == 2, 0);
        assert!(cumulative_volume_at_7 == 9, 0);
    }

    fun get_coin_balance(scenario: &mut Scenario, user: address): u64{
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_address<Coin<SUI>>(user);
        let balance = 0;
        while(!vector::is_empty(&ids)){
            let id = vector::pop_back(&mut ids);
            if(!ts::was_taken_from_address(user, id)){
                let coin = ts::take_from_address_by_id<Coin<SUI>>(scenario, user, id);
                balance = balance + coin::value(&coin);
                ts::return_to_address(user, coin);
            };
        };
        balance
    }

    fun get_nft_balance(scenario: &mut Scenario, user: address): u64{
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_address<Nft>(user);
        let balance = 0;
        while(!vector::is_empty(&ids)){
            let id = vector::pop_back(&mut ids);
            if(!ts::was_taken_from_address(user, id)){
                let nft = ts::take_from_address_by_id<Nft>(scenario, user, id);
                balance = balance + nft::nft_value(&nft);
                ts::return_to_address(user, nft);
            };
        };
        balance
    }

    /*
        Ask:{
            price_level: {
                OO(price=5, total_volume=12): [Ask(ALICE, 5), Ask(ALICE, 5), Ask(BOB, 2)],
                OO(price=6, total_volume=2): [Ask(CAROL,2)],
                OO(price=7, total_volume=9): [Ask(ALICE,3), Ask(BOB,6)],
            }
        }
     */

    #[test]
    fun no_asks_crossed(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        {
            let price = 4;
            let amount = 10;
            let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
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
    fun crossed_single_ask_complete(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 5;
        let amount = 5;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Check asks_tree
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
        assert!(total_volume == 7, 0); // initial volume where price=5 -> 12 but 5 got sold, so we're left with 7
        assert!(vector::length(orders) == 2, 0); // initial orders = 3, 1 got completely filled, so we're left with 2 order

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 5, Nft balance = 0 + 5 = 5
        assert!(get_nft_balance(scenario, DAVID) == 5, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Bid crossed order for 5 at 5/each = 1000 - 5*5 = 975
        assert!(get_coin_balance(scenario, DAVID) == 975, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 5 at 5/each = 900 + 5*5 = 925
        assert!(get_coin_balance(scenario, ALICE) == 925, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_single_ask_partial(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 5;
        let amount = 3;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Check asks_tree
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
        assert!(total_volume == 9, 0); // initial volume where price=5 -> 12 but 3 got sold, so we're left with 9
        assert!(vector::length(orders) == 3, 0); // initial orders = 3, 1 got partially filled, so we're still left with 3 orders

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 3, Nft balance = 0 + 3 = 3
        assert!(get_nft_balance(scenario, DAVID) == 3, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Bid crossed order for 5 at 5/each = 1000 - 5*3 = 985
        assert!(get_coin_balance(scenario, DAVID) == 985, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 5 at 5/each = 900 + 5*3 = 915
        assert!(get_coin_balance(scenario, ALICE) == 915, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_multiple_asks_price_level(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 5;
        let amount = 12;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Check asks_tree
        let asks_tree = ob::get_asks_tree(&clob);
        assert!(!cb::has_key(asks_tree, price), 0);

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 12, Nft balance = 0 + 12 = 12
        assert!(get_nft_balance(scenario, DAVID) == 12, 0);

        // Verify coin balance for CAROL
        // Initial coin balance = 1000
        // Bid crossed order for 12 at 5/each = 1000 - 5*12 = 940
        assert!(get_coin_balance(scenario, DAVID) == 940, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 5 at 5/each = 900 + 5*10 = 950
        assert!(get_coin_balance(scenario, ALICE) == 950, 0);

        // Verify coin balance for BOB
        // Initial coin balance = 1000
        // Minted 53 Nfts at 1/each = 1000 - 53 = 947
        // Bid crossed order for 2 at 5/each = 947 + 5*2 = 957
        assert!(get_coin_balance(scenario, BOB) == 957, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_multiple_asks_complete(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 5;
        let amount = 10;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Check asks_tree
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
        assert!(total_volume == 2, 0); // initial volume where price=5 -> 12 but 10 got sold, so we're left with 2
        assert!(vector::length(orders) == 1, 0); // initial orders = 3, 2 got completely filled, so we're left with 1 order

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 10, Nft balance = 0 + 10 = 10
        assert!(get_nft_balance(scenario, DAVID) == 10, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Bid crossed order for 10 at 5/each = 1000 - 5*10 = 950
        assert!(get_coin_balance(scenario, DAVID) == 950, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 10 at 5/each = 900 + 5*10 = 950
        assert!(get_coin_balance(scenario, ALICE) == 950, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_multiple_asks_partial(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 5;
        let amount = 11;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Check asks_tree
        let (total_volume, orders) = ob::get_OO(ob::get_asks_tree(&clob), price);
        assert!(total_volume == 1, 0); // initial volume where price=5 -> 12 but 11 got sold, so we're left with 1
        assert!(vector::length(orders) == 1, 0); // initial orders = 3, 2 got completely filled, 1 got partiall filled, so we're left with 1 order

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 11, Nft balance = 0 + 11 = 11
        assert!(get_nft_balance(scenario, DAVID) == 11, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Bid crossed order for 11 at 5/each = 1000 - 5*11 = 945
        assert!(get_coin_balance(scenario, DAVID) == 945, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 10 at 5/each = 900 + 5*10 = 950
        assert!(get_coin_balance(scenario, ALICE) == 950, 0);

        // Verify coin balance for BOB
        // Initial coin balance = 1000
        // Minted 53 Nfts at 1/each = 1000 - 53 = 947
        // Bid crossed order for 1 at 5/each = 947 + 5 = 952
        assert!(get_coin_balance(scenario, BOB) == 952, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_multiple_asks_complete_across_prices(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 6;
        let amount = 14;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 14, Nft balance = 0 + 14 = 14
        assert!(get_nft_balance(scenario, DAVID) == 14, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Placed bid for 14 at 6/each = 6 * 14 = 84
        // Bid crossed order for 12 at 5/each = 5*12 = 60
        // Bid crossed order for 2 at 6/each = 6*2 = 12
        // Final balance = 1000 - 60 - 12 = 928
        assert!(get_coin_balance(scenario, DAVID) == 928, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 10 at 5/each = 900 + 5*10 = 950
        assert!(get_coin_balance(scenario, ALICE) == 950, 0);

        // Verify coin balance for BOB
        // Initial coin balance = 1000
        // Minted 53 Nfts at 1/each = 1000 - 53 = 947
        // Bid crossed order for 2 at 5/each = 947 + 5*2 = 957
        assert!(get_coin_balance(scenario, BOB) == 957, 0);

        // Verify coin balance for CAROL
        // Initial coin balance = 1000
        // Minted 23 Nfts at 1/each = 1000 - 23 = 977
        // Bid crossed order for 2 at 6/each = 977 + 6*2 = 989
        assert!(get_coin_balance(scenario, CAROL) == 989, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun crossed_multiple_asks_partial_across_prices(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario, 100, 53, 23);
        init_asks(scenario, &mut clob, &mut project);

        // Create bid
        ts::next_tx(scenario, DAVID);
        let price = 6;
        let amount = 13;
        let bid_offer = take_coins<SUI>(scenario, DAVID, price*amount);
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree
        ob::create_bid(&mut clob, &mut project, bid_offer, amount, price, ts::ctx(scenario));
        assert!(!cb::has_key(ob::get_bids_tree(&clob), price), 0); // Expected: key (price) should not exist in bids_tree because crossed perfectly

        ts::next_tx(scenario, ADMIN);

        // Verify Nft balance for DAVID
        // Initial Nft balance = 0
        // Bid crossed order for 13, Nft balance = 0 + 13 = 13
        assert!(get_nft_balance(scenario, DAVID) == 13, 0);

        // Verify coin balance for DAVID
        // Initial coin balance = 1000
        // Placed bid for 13 at 6/each = 6 * 13 = 78
        // Bid crossed order for 12 at 5/each = 5*12 = 60
        // Bid crossed order for 1 at 6/each = 6*1 = 6
        // Final balance = 1000 - 60 - 6 = 934
        assert!(get_coin_balance(scenario, DAVID) == 934, 0);

        // Verify coin balance for ALICE
        // Initial coin balance = 1000
        // Minted 100 Nfts at 1/each = 1000 - 100 = 900
        // Bid crossed order for 10 at 5/each = 900 + 5*10 = 950
        assert!(get_coin_balance(scenario, ALICE) == 950, 0);

        // Verify coin balance for BOB
        // Initial coin balance = 1000
        // Minted 53 Nfts at 1/each = 1000 - 53 = 947
        // Bid crossed order for 2 at 5/each = 947 + 5*2 = 957
        assert!(get_coin_balance(scenario, BOB) == 957, 0);

        // Verify coin balance for CAROL
        // Initial coin balance = 1000
        // Minted 23 Nfts at 1/each = 1000 - 23 = 977
        // Bid crossed order for 1 at 6/each = 977 + 6 = 983
        assert!(get_coin_balance(scenario, CAROL) == 983, 0);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }

    #[test]
    fun no_bids_crossed(){
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