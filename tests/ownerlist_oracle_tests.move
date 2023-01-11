#[test_only]
module crowd9_sc::ownerlist_oracle_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer::{Self};
    use crowd9_sc::dict;
    use crowd9_sc::governance::{Self, Governance};
    use crowd9_sc::ino::{Self, Campaign, OwnerCap, Project};
    use std::debug;
    use sui::object::{Self, ID};
    use crowd9_sc::ownerlist_oracle::{Self, OwnerList, AuthorityCap, CapabilityBook, AdminCap};

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;
    const DANIEL:address = @0xAAAD;

    
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

    fun init_settings(scenario: &mut Scenario, user: address): (Governance){
        ts::next_tx(scenario, user);

        ino::create_campaign(b"The One", b"Description", 100, 10, 1, 20, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let campaign = ts::take_shared<Campaign>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, user);
        ino::start_campaign(&mut campaign, &owner_cap, ts::ctx(scenario));
        ts::next_tx(scenario, ALICE);
        ino::contribute(&mut campaign, 5, take_coins(scenario, ALICE, 50), ts::ctx(scenario));
        ts::next_tx(scenario, BOB);
        ino::contribute(&mut campaign, 10, take_coins(scenario, BOB, 100), ts::ctx(scenario));
        ts::next_tx(scenario, CAROL);
        ino::contribute(&mut campaign, 15, take_coins(scenario, CAROL, 150), ts::ctx(scenario));
        ts::next_tx(scenario, user);
        ino::end_campaign(&mut campaign, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let project = ts::take_shared<Project>(scenario);
        governance::create_governance(&mut project, 8511, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let governance = ts::take_shared<Governance>(scenario);

        ts::return_to_address(user, owner_cap);
        ts::return_shared(project);
        ts::return_shared(campaign);
        governance
    }

    fun init_ownerlist_oracle(scenario: &mut Scenario, user: address, governance: ID):(AdminCap, CapabilityBook, OwnerList, AuthorityCap){
        ts::next_tx(scenario, user);
        ownerlist_oracle::init_for_testing(ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let cap_book = ts::take_shared<CapabilityBook>(scenario);
        let admin_cap = ts::take_from_address<AdminCap>(scenario, user);
        ts::next_tx(scenario, user);
        let dict = dict::new(ts::ctx(scenario));
        // add fields
        dict::add(&mut dict, ALICE, 5);
        dict::add(&mut dict, BOB, 10);
        dict::add(&mut dict, CAROL, 15);
        ownerlist_oracle::add_to_capbook(&admin_cap, governance, &mut cap_book, dict, ts::ctx(scenario));
        ts::next_tx(scenario, user);
        let ownerlist = ts::take_shared<OwnerList>(scenario);
        let authority_cap = ts::take_from_address<AuthorityCap>(scenario, user);
        (admin_cap, cap_book, ownerlist, authority_cap)
    }

    #[test]
    fun add_to_capbook_test(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);
        ts::return_shared(cap_book);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ownerlist_oracle::EUnauthorizedUser)]
    fun add_to_capbook_test_not_admin(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);
        
        ts::next_tx(scenario, DANIEL);
        let governance1 = init_settings(scenario, DANIEL);
        let gov_id1 = object::id(&governance1);
        let (admin_cap1, cap_book1, ownerlist1, authority_cap1) = init_ownerlist_oracle(scenario, DANIEL, gov_id1);

        ts::next_tx(scenario, ADMIN);
        ownerlist_oracle::add_to_capbook(&admin_cap, gov_id, &mut cap_book1, dict::new(ts::ctx(scenario)), ts::ctx(scenario));
        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);

        ts::return_to_address(DANIEL, authority_cap1);
        ts::return_to_address(DANIEL, admin_cap1);

        ts::return_shared(cap_book);
        ts::return_shared(cap_book1);
        ts::return_shared(ownerlist1);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::return_shared(governance1);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ownerlist_oracle::EGovRecordAlreadyExist)]
    fun add_to_capbook_test_record_existed(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);
        
        ownerlist_oracle::add_to_capbook(&admin_cap, gov_id, &mut cap_book, dict::new(ts::ctx(scenario)), ts::ctx(scenario));
        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);

        ts::return_shared(cap_book);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::end(scenario_val);
    }

    #[test]
    fun update_ownerlist_test(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);

        ts::next_tx(scenario, CAROL);
        {
            ownerlist_oracle::update_ownerlist(&mut authority_cap, &mut ownerlist, &mut cap_book, CAROL, BOB, 5);
            let owners = ownerlist_oracle::get_owners(&ownerlist);
            assert!(*dict::borrow(owners, CAROL) == 10, 0);
        };

        ts::next_tx(scenario, BOB);
        {
            ownerlist_oracle::update_ownerlist(&mut authority_cap, &mut ownerlist, &mut cap_book, BOB, ALICE, 5);
            let owners = ownerlist_oracle::get_owners(&ownerlist);
            assert!(*dict::borrow(owners, BOB) == 10, 0);
            assert!(*dict::borrow(owners, ALICE) == 10, 0);
        };

        ts::next_tx(scenario, BOB);
        {
            ownerlist_oracle::update_ownerlist(&mut authority_cap, &mut ownerlist, &mut cap_book, BOB, DANIEL, 10);
            let owners = ownerlist_oracle::get_owners(&ownerlist);
            assert!(*dict::borrow(owners, DANIEL) == 10, 0);
            assert!(!dict::contains(owners, BOB), 0);
        };
        let owners = ownerlist_oracle::get_owners(&ownerlist);
        debug::print(owners);

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);
        ts::return_shared(cap_book);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ownerlist_oracle::EGovRecordDoesNotExist)]
    fun update_ownerlist_test_unexisted_gov(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);

        ts::next_tx(scenario, DANIEL);
        let governance1 = init_settings(scenario, DANIEL);
        let gov_id1 = object::id(&governance1);
        let (admin_cap1, cap_book1, ownerlist1, authority_cap1) = init_ownerlist_oracle(scenario, DANIEL, gov_id1);

        ts::next_tx(scenario, CAROL);
        {
            ownerlist_oracle::update_ownerlist(&mut authority_cap1, &mut ownerlist1, &mut cap_book, CAROL, BOB, 5);
            let owners = ownerlist_oracle::get_owners(&ownerlist1);
            assert!(*dict::borrow(owners, CAROL) == 10, 0);
        };

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);

        ts::return_to_address(DANIEL, authority_cap1);
        ts::return_to_address(DANIEL, admin_cap1);

        ts::return_shared(cap_book);
        ts::return_shared(cap_book1);
        ts::return_shared(ownerlist1);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::return_shared(governance1);
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ownerlist_oracle::EOwnerRecordDoesNotExist)]
    fun update_ownerlist_test_unexisted_owner(){
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 1000;
        init_test_accounts(scenario, coins_to_mint);
        let governance = init_settings(scenario, ADMIN);
        let gov_id = object::id(&governance);
        let (admin_cap, cap_book, ownerlist, authority_cap) = init_ownerlist_oracle(scenario, ADMIN, gov_id);

        ts::next_tx(scenario, BOB);
        {
            ownerlist_oracle::update_ownerlist(&mut authority_cap, &mut ownerlist, &mut cap_book, DANIEL, BOB, 10);
            let owners = ownerlist_oracle::get_owners(&ownerlist);
            assert!(*dict::borrow(owners, DANIEL) == 10, 0);
            assert!(!dict::contains(owners, BOB), 0);
        };
        let owners = ownerlist_oracle::get_owners(&ownerlist);
        debug::print(owners);

        ts::return_to_address(ADMIN, admin_cap);
        ts::return_to_address(ADMIN, authority_cap);
        ts::return_shared(cap_book);
        ts::return_shared(ownerlist);
        ts::return_shared(governance);
        ts::end(scenario_val);
    }
    
}