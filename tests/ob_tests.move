#[test_only]

module crowd9_sc::ob_tests{
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::nft::{Project, Nft};
    // use crowd9_sc::my_module::{Self, Card};
    use crowd9_sc::ob::{Self, Market, CLOB};
    use std::debug;
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

    fun init_ob(scenario: &mut Scenario): (Project, Market, CLOB){
        ts::next_tx(scenario, ADMIN);
        ob::init_test(ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let market = ts::take_shared<Market>(scenario);
        debug::print(&market);
        debug::print(&market);
        debug::print(&market);

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

    use sui::table::{/*Self,*/ Table};
    use sui::object::{ID};

    struct TestStruct {
        test: Table<ID, ID>
    }

    #[test]
    fun test_fn(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);

        let (project, market, clob) = init_ob(scenario);
        ts::next_tx(scenario, ALICE);
        {
            let nft = ts::take_from_address<Nft>(scenario, ALICE); //own 100
            ob::create_ask(&mut clob, &mut project, nft,  100,5, ts::ctx(scenario));

            let nft = ts::take_from_address<Nft>(scenario, BOB); //own 53
            ob::create_ask(&mut clob, &mut project, nft, 53, 3, ts::ctx(scenario));

            let nft = ts::take_from_address<Nft>(scenario, CAROL); //own 23
            ob::create_ask(&mut clob, &mut project, nft, 23,2, ts::ctx(scenario));
        };
        debug::print(&b"0000000000000000000000000000000000000000000");
        debug::print(&clob);
        debug::print(&b"0000000000000000000000000000000000000000000");
        ts::next_tx(scenario, ADMIN);
        {
            ob::create_bid(&mut clob, &mut project, take_coins<SUI>(scenario, ADMIN, 3*76), 76, 3, ts::ctx(scenario));
        };
        debug::print(&clob);

        ts::return_shared(project);
        ts::return_shared(market);
        ts::return_shared(clob);
        ts::end(scenario_val);
    }
}