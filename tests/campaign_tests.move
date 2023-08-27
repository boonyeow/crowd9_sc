#[test_only]
module crowd9_sc::campaign_tests {
    use crowd9_sc::campaign::{Self, Campaign, OwnerCap};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::sui::SUI;
    use std::option::{Self};

    const ADMIN: address = @0x000A;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const CAROL: address = @0xCCCC;


    /// Status Codes
    const SInactive: u8 = 0;
    const SActive: u8 = 1;
    const SSuccess: u8 = 2;
    const SFailure: u8 = 3;
    const SCancelled: u8 = 4;
    const SCompleted: u8 = 5;

    // Campaign Defaults
    const INITIAL_CAMPAIGN_NAME: vector<u8> = b"The One";
    const INITIAL_CAMPAIGN_DESCRIPTION: vector<u8> = b"Description";
    const INITIAL_CAMPAIGN_DURATION_TYPE: u8 = 1;
    const INITIAL_PRICE_PER_TOKEN: u64 = 10;
    const INITIAL_FUNDING_GOAL: u64 = 10000;

    fun init_scenario<T>(
        scenario: &mut Scenario,
        user: address,
        price_per_token: u64,
        funding_goal: u64
    ): (Campaign<T>, OwnerCap) {
        ts::next_tx(scenario, user);
        campaign::create_campaign<T>(
            INITIAL_CAMPAIGN_NAME,
            INITIAL_CAMPAIGN_DESCRIPTION,
            price_per_token,
            funding_goal,
            INITIAL_CAMPAIGN_DURATION_TYPE,
            ts::ctx(scenario)
        );

        ts::next_tx(scenario, user);
        let campaign = ts::take_shared<Campaign<T>>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, user);
        (campaign, owner_cap)
    }

    fun end_scenario<T>(user: address, owner_cap: OwnerCap, campaign: Campaign<T>, scenario_val: Scenario) {
        ts::return_to_address(user, owner_cap);
        ts::return_shared(campaign);
        ts::end(scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun update_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap) = init_scenario<SUI>(scenario, ALICE, INITIAL_PRICE_PER_TOKEN, INITIAL_FUNDING_GOAL);
        campaign::update_campaign_status(&mut campaign, SActive);
        campaign::update<SUI>(
            &mut campaign,
            option::some(b"hi"),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            &owner_cap
        );
        end_scenario(ALICE, owner_cap, campaign, scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun update_campaign_invalid_owner_cap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign1, owner_cap1) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );
        let (campaign2, owner_cap2) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        campaign::update<SUI>(
            &mut campaign1,
            option::some(b"hi"),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            &owner_cap2
        );
        ts::return_to_address(ALICE, owner_cap1);
        ts::return_shared(campaign1);
        end_scenario(ALICE, owner_cap2, campaign2, scenario_val);
    }

    #[test]
    fun update_campaign() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap) = init_scenario<SUI>(scenario, ALICE, INITIAL_PRICE_PER_TOKEN, INITIAL_FUNDING_GOAL);

        ts::next_tx(scenario, ALICE);
        {
            assert!(campaign::verify_campaign_details(
                &campaign,
                INITIAL_CAMPAIGN_NAME,
                INITIAL_CAMPAIGN_DESCRIPTION,
                INITIAL_PRICE_PER_TOKEN,
                INITIAL_FUNDING_GOAL,
                INITIAL_CAMPAIGN_DURATION_TYPE), 0);
            let new_campaign_name = b"Updated Name";
            let new_campaign_description = b"Updated Description";
            let new_campaign_price_per_token = 50;
            let new_campaign_funding_goal = 40000;
            let new_campaign_duration_type = 2;

            campaign::update(&mut campaign,
                option::some(new_campaign_name),
                option::some(new_campaign_description),
                option::some(new_campaign_price_per_token),
                option::some(new_campaign_funding_goal),
                option::some(new_campaign_duration_type),
                &owner_cap);

            assert!(
                campaign::verify_campaign_details(
                    &campaign,
                    new_campaign_name,
                    new_campaign_description,
                    new_campaign_price_per_token,
                    new_campaign_funding_goal,
                    new_campaign_duration_type
                ),
                1)
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val);
    }

    // start campaign
    #[test]
    fun start_campaign() {}

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun start_campaign_invalid_owner_cap() {}

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun start_campaign_disallowed_status() {}

    // contribute to campaign
    #[test]
    fun contribute_to_campaign_authorized_user() {}

    #[test]
    fun contribute_to_campaign_disallowed_status() {}

    #[test]
    fun contribute_to_campaign_invalid_coin_amount() {}

    #[test]
    fun contribute_to_campaign_unrequested_coin() {}

    #[test]
    fun contribute_to_campaign_after_campaign_duration() {}

    // cancel
    #[test]
    fun cancel_campaign() {}

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun cancel_campaign_invalid_owner_cap() {}

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun cancel_campaign_disallowed_status() {}

    // end, process_refund,
}