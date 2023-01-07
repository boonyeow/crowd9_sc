#[test_only]
module crowd9_sc::ino_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};
    use sui::balance;
    use crowd9_sc::ino::{Self, Campaign, OwnerCap, Project, Nft};
    use crowd9_sc::dict;
    use crowd9_sc::balance::{Self as c9_balance};
    use std::vector;
    use std::debug;

    // use std::vector;
    // use sui::table;

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    fun hello_world(){
        debug::print(&b"hi");
    }

    fun init_campaign(scenario: &mut Scenario, user: address, funding_goal:u64, price_per_nft: u64): (Campaign, OwnerCap){
        ts::next_tx(scenario, user);
        ino::create_campaign(b"The One", b"Description", funding_goal, price_per_nft, 1, 20, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let campaign = ts::take_shared<Campaign>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, user);
        (campaign, owner_cap)
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


    #[test]
    fun start_campaign(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);
        assert!(ino::get_campaign_status(&campaign) == 0, 0); // SInactive = 0

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));
        assert!(ino::get_campaign_status(&campaign) == 1, 0); // SActive = 1

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun start_campaign_not_owner(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let (campaign, alice_cap) = init_campaign(scenario, ALICE, 1000, 10);
        let (campaign1, bob_cap) = init_campaign(scenario, BOB, 1000, 10);

        ts::next_tx(scenario, ALICE);
        ino::start_campaign(&mut campaign1, &alice_cap, ts::ctx(scenario));
        ts::return_to_address(ALICE, alice_cap);
        ts::return_shared(campaign);
        ts::return_to_address(BOB, bob_cap);
        ts::return_shared(campaign1);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun start_campaign_status_not_inactive(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));
        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    fun cancel_campaign(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);
        assert!(ino::get_campaign_status(&campaign) == 0, 0); // SInactive = 0

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));
        assert!(ino::get_campaign_status(&campaign) == 1, 0); // SActive = 1

        ts::next_tx(scenario, ADMIN);
        ino::cancel_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));
        assert!(ino::get_campaign_status(&campaign) == 4, 0); // SCancelled = 4

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun cancel_campaign_not_owner(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, alice_cap) = init_campaign(scenario, ALICE, 1000, 10);
        let (campaign1, bob_cap) = init_campaign(scenario, BOB, 1000, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &alice_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::cancel_campaign(&mut campaign, &bob_cap, ts::ctx(scenario));

        ts::return_to_address(ADMIN, alice_cap);
        ts::return_to_address(BOB, bob_cap);
        ts::return_shared(campaign);
        ts::return_shared(campaign1);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun cancel_campaign_status_not_active(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);
        assert!(ino::get_campaign_status(&campaign) == 0, 0); // SInactive = 0

        ts::next_tx(scenario, ADMIN);
        ino::cancel_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));
        assert!(ino::get_campaign_status(&campaign) == 0, 0); // SInactive = 0

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun contribute_as_owner(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        ino::contribute(&mut campaign, 20, take_coins(scenario, ADMIN, 10), ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EIncorrectAmount)]
    fun contribute_paid_incorrect_amount(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 20, take_coins(scenario, BOB, 10), ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun contribute_status_not_active(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 20, take_coins(scenario, BOB, 10), ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun contribute(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 100, 1);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB); // contribute
        ino::contribute(&mut campaign, 5, take_coins(scenario, BOB, 5), ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        {
            let contributors = ino::get_contributors(&campaign);
            assert!(dict::contains(contributors, BOB), 0);
            assert!(!dict::contains(contributors, ALICE), 1);
            assert!(*dict::borrow(contributors, BOB) == 5, 2);
        };

        ts::next_tx(scenario, BOB); // contribute again
        ino::contribute(&mut campaign, 5, take_coins(scenario, BOB, 5), ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        {
            let contributors = ino::get_contributors(&campaign);
            assert!(dict::contains(contributors, BOB), 0);
            assert!(!dict::contains(contributors, ALICE), 1);
            assert!(*dict::borrow(contributors, BOB) == 10, 2);
        };

        ts::next_tx(scenario, ALICE);
        {
            let contributors = ino::get_contributors(&campaign);
            let _ = *dict::borrow(contributors, ALICE); // key doesn't exist
        };

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun end_campaign_not_active(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 1000, 10);

        ts::next_tx(scenario, BOB);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    fun end_campaign_success(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 10000000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 100, 1);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        {
            ino::contribute(&mut campaign, 1000000, take_coins(scenario, BOB, 1000000), ts::ctx(scenario));
            let contributors = ino::get_contributors(&mut campaign);
            assert!(*dict::borrow(contributors, BOB) == 1000000, 0);
        };

        ts::next_tx(scenario, CAROL);
        {
            ino::contribute(&mut campaign, 100, take_coins(scenario, CAROL, 100), ts::ctx(scenario));
            let contributors = ino::get_contributors(&mut campaign);
            assert!(*dict::borrow(contributors, CAROL) == 100, 0);
        };

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        let project = ts::take_shared<Project>(scenario);
        let project_balance = ino::get_project_balance(&project);
        let supply = ino::get_supply(&project);
        assert!(ino::get_campaign_status(&campaign) == 2, 0);
        assert!(c9_balance::supply_value(supply) == (1000000 + 100), 1);
        assert!(balance::value(project_balance) == (1000000 + 100), 2);

        {
            // check bob
            let nft: Nft = ts::take_from_address(scenario, BOB);
            let balance = ino::get_balance(&nft);
            assert!(c9_balance::value(balance) == 1000000, 3);
            ts::return_to_address(BOB, nft);
        };

        {
            // check carol
            let nft: Nft = ts::take_from_address(scenario, CAROL);
            let balance = ino::get_balance(&nft);
            assert!(c9_balance::value(balance) == 100, 4);
            ts::return_to_address(CAROL, nft);
        };

        ts::return_shared(project);
        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    fun end_campaign_failed_and_claim(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 100, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 1, take_coins(scenario, BOB, 10), ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        assert!(ino::get_campaign_status(&campaign) == 3, 0); //3 for SFailure

        ts::next_tx(scenario, BOB);
        {
            // before claiming
            let ids = ts::ids_for_address<Coin<SUI>>(BOB);
            let total_value = 0;
            while(!vector::is_empty(&ids)){
                let id = vector::pop_back(&mut ids);
                let coin = ts::take_from_address_by_id<Coin<SUI>>(scenario, BOB, id);
                total_value = total_value + coin::value(&coin);
                ts::return_to_address(BOB, coin);
            };
            assert!(total_value == 990, 1);
        };

        ino::claim_funds(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        {
            // after claiming
            let ids = ts::ids_for_address<Coin<SUI>>(BOB);
            let total_value = 0;
            while(!vector::is_empty(&ids)){
                let id = vector::pop_back(&mut ids);
                let coin = ts::take_from_address_by_id<Coin<SUI>>(scenario, BOB, id);
                total_value = total_value + coin::value(&coin);
                ts::return_to_address(BOB, coin);
            };
            assert!(total_value == 1000, 1);
        };

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun claim_from_not_failed_or_cancelled(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 100, 10);

        ts::next_tx(scenario, BOB);
        ino::claim_funds(&mut campaign, ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::ENoContributionFound)]
    fun claim_but_no_contribution(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN, 100, 10);

        ts::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 1, take_coins(scenario, BOB, 10), ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);
        assert!(ino::get_campaign_status(&campaign) == 3, 0); //3 for SFailure
        ino::claim_funds(&mut campaign, ts::ctx(scenario));

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }
}