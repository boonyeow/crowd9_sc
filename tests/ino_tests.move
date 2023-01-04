#[test_only]
module crowd9_sc::ino_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::sui::SUI;
    use sui::coin::{Self};
    use sui::transfer::{Self};
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use std::debug;

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    // #[test]
    fun init_campaign(scenario: &mut Scenario, user: address): (Campaign, OwnerCap){
        test_scenario::next_tx(scenario, user);
        ino::create_campaign(b"The One", b"Description", 1000, 10, 1, 20, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, user);
        let campaign = test_scenario::take_shared<Campaign>(scenario);
        let owner_cap = test_scenario::take_from_address<OwnerCap>(scenario, user);
        (campaign, owner_cap)
    }

    fun init_test_accounts(scenario: &mut Scenario, value: u64) {
        debug::print(&b"hi");
        test_scenario::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), CAROL);
    }

    #[test]
    fun start_campaign(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN);

        test_scenario::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, admin_cap);
        test_scenario::return_shared(campaign);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun start_campaign_not_owner(){
        let scenario_val = test_scenario::begin(ALICE);
        let scenario = &mut scenario_val;

        let (campaign, alice_cap) = init_campaign(scenario, ALICE);
        let (campaign1, bob_cap) = init_campaign(scenario, BOB);

        test_scenario::next_tx(scenario, ALICE);
        ino::start_campaign(&mut campaign1, &alice_cap, test_scenario::ctx(scenario));
        test_scenario::return_to_address(ALICE, alice_cap);
        test_scenario::return_shared(campaign);
        test_scenario::return_to_address(BOB, bob_cap);
        test_scenario::return_shared(campaign1);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun start_campaign_status_not_inactive(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN);

        test_scenario::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, admin_cap);
        test_scenario::return_shared(campaign);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun cancel_campaign(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN);

        test_scenario::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ADMIN);
        ino::cancel_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, admin_cap);
        test_scenario::return_shared(campaign);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun cancel_campaign_not_owner(){
        let scenario_val = test_scenario::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, alice_cap) = init_campaign(scenario, ALICE);
        let (campaign1, bob_cap) = init_campaign(scenario, BOB);

        test_scenario::next_tx(scenario, ADMIN);
        ino::start_campaign(&mut campaign, &alice_cap, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        ino::cancel_campaign(&mut campaign, &bob_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, alice_cap);
        test_scenario::return_to_address(BOB, bob_cap);
        test_scenario::return_shared(campaign);
        test_scenario::return_shared(campaign1);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EDisallowedAction)]
    fun cancel_campaign_status_not_active(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN);

        test_scenario::next_tx(scenario, ADMIN);
        ino::cancel_campaign(&mut campaign, &admin_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, admin_cap);
        test_scenario::return_shared(campaign);
        test_scenario::end(scenario_val);
    }

    // TODO write testcases for end_campaign
    // TODO write testcases for contribute
    // TODO write testcases for claim_funds
}
