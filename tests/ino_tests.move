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
        test_scenario::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), CAROL);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::ino::EUnauthorizedUser)]
    fun cancel_campaign_with_wrong_cap(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 100;

        init_test_accounts(scenario, coins_to_mint);
        let (campaign, admin_cap) = init_campaign(scenario, ADMIN);
        debug::print(&campaign);
        debug::print(&admin_cap);

        let (campaign1, alice_cap) = init_campaign(scenario, ALICE);
        debug::print(&alice_cap);

        test_scenario::next_tx(scenario, ALICE);
        ino::cancel_campaign(&mut campaign, &alice_cap, test_scenario::ctx(scenario));

        test_scenario::return_to_address(ADMIN, admin_cap);
        test_scenario::return_to_address(ALICE, alice_cap);
        test_scenario::return_shared(campaign);
        test_scenario::return_shared(campaign1);

        test_scenario::end(scenario_val);
    }

    // fun cancel_campaign_thats_inactive_or_active(){
    //
    // }
}
