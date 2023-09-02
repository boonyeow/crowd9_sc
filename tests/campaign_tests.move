#[test_only]
module crowd9_sc::campaign_tests {
    use crowd9_sc::campaign::{Self, Campaign, OwnerCap, verify_campaign_status};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::sui::SUI;
    use std::option::{Self};
    use sui::tx_context;
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};
    use sui::clock::{Self, Clock};
    use std::vector::{Self};

    const ADMIN: address = @0x000A;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const CAROL: address = @0xCCCC;

    // TODO: Test the clock for contribute function

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
    const INITIAL_STARTING_COINS: u64 = 100000;

    const MS_IN_A_DAY: u64 = 1000 * 60 * 60 * 24;

    fun mint_coins_to_user<CoinType>(scenario: &mut Scenario, amount_to_mint: u64, user: address) {
        ts::next_tx(scenario, user);
        transfer::public_transfer(
            coin::mint_for_testing<CoinType>(amount_to_mint, ts::ctx(scenario)), user
        );
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user: address, amount: u64): Coin<T> {
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin = coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun get_coins_balance<T: drop>(scenario: &mut Scenario, user: address): u64 {
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_sender<Coin<T>>(scenario);
        let combined_balance = 0;
        while (!vector::is_empty(&ids)) {
            let id = vector::pop_back(&mut ids);
            let coin = ts::take_from_address_by_id<Coin<T>>(scenario, user, id);
            combined_balance = combined_balance + coin::value(&coin);
            ts::return_to_address(user, coin);
        };
        combined_balance
    }

    fun init_scenario<T>(
        scenario: &mut Scenario,
        user: address,
        price_per_token: u64,
        funding_goal: u64
    ): (Campaign<T>, OwnerCap, Clock) {
        ts::next_tx(scenario, user);
        campaign::create_campaign<T>(
            INITIAL_CAMPAIGN_NAME,
            INITIAL_CAMPAIGN_DESCRIPTION,
            price_per_token,
            funding_goal,
            INITIAL_CAMPAIGN_DURATION_TYPE,
            ts::ctx(scenario)
        );

        mint_coins_to_user<SUI>(scenario, INITIAL_STARTING_COINS, ALICE);
        mint_coins_to_user<SUI>(scenario, INITIAL_STARTING_COINS, BOB);
        mint_coins_to_user<SUI>(scenario, INITIAL_STARTING_COINS, CAROL);

        ts::next_tx(scenario, user);
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::share_for_testing(clock);

        ts::next_tx(scenario, ALICE);
        let clock = ts::take_shared<Clock>(scenario);

        let campaign = ts::take_shared<Campaign<T>>(scenario);
        let owner_cap = ts::take_from_address<OwnerCap>(scenario, user);
        (campaign, owner_cap, clock)
    }

    fun end_scenario<T>(
        user: address,
        owner_cap: OwnerCap,
        campaign: Campaign<T>,
        scenario_val: Scenario,
        clock: Clock
    ) {
        ts::return_to_address(user, owner_cap);
        ts::return_shared(campaign);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun update_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );
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
        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun update_campaign_invalid_owner_cap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign1, owner_cap1, clock1) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );
        let (campaign2, owner_cap2, clock2) = init_scenario<SUI>(
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
        ts::return_shared(clock1);
        end_scenario(ALICE, owner_cap2, campaign2, scenario_val, clock2);
    }

    #[test]
    fun update_campaign() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

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

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    // start campaign
    #[test]
    fun start_campaign() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            assert!(campaign::verify_campaign_status(&campaign, SInactive), 1);
            campaign::start(&mut campaign, &owner_cap, &clock);
            assert!(campaign::verify_campaign_status(&campaign, SActive), 1);
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun start_campaign_invalid_owner_cap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign1, owner_cap1, clock1) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        let (campaign2, owner_cap2, clock2) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign1, &owner_cap2, &clock1);
        };

        ts::return_to_address(ALICE, owner_cap1);
        ts::return_shared(campaign1);
        ts::return_shared(clock1);
        end_scenario(ALICE, owner_cap2, campaign2, scenario_val, clock2);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun start_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    // contribute to campaign
    #[test]
    fun contribute_to_campaign_authorized_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 100;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
            assert!(campaign::verify_contribution_amount(&campaign, user, contribution_amount, contribution_amount), 1);
        };

        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
            assert!(
                campaign::verify_contribution_amount(&campaign, user, contribution_amount * 2, contribution_amount * 2),
                1
            );
        };

        ts::next_tx(scenario, CAROL);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
            assert!(
                campaign::verify_contribution_amount(&campaign, user, contribution_amount, contribution_amount * 3),
                1
            );
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun contribute_to_campaign_disallowed_user() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 100;
        ts::next_tx(scenario, ALICE);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun contribute_to_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        let contribution_amount = 100;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount), &mut campaign, &clock, ts::ctx(scenario)
            )
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EInvalidCoinAmount)]
    fun contribute_to_campaign_invalid_coin_amount() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 99;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    // not sure if even possible to call?
    // #[test]
    // fun contribute_to_campaign_unrequested_coin() {
    //     let scenario_val = ts::begin(ALICE);
    //     let scenario = &mut scenario_val;
    //     let (campaign, owner_cap, clock) = init_scenario<SUI>(
    //         scenario,
    //         ALICE,
    //         INITIAL_PRICE_PER_TOKEN,
    //         INITIAL_FUNDING_GOAL
    //     );
    //
    //     ts::next_tx(scenario, ALICE);
    //     {
    //         campaign::start(&mut campaign, &owner_cap, &clock);
    //     };
    //
    //     let contribution_amount = 99;
    //     ts::next_tx(scenario, BOB);
    //     {
    //         let user = tx_context::sender(ts::ctx(scenario));
    //         campaign::contribute(
    //             take_coins<BTC>(scenario, user, contribution_amount),
    //             &mut campaign,
    //             &clock,
    //             ts::ctx(scenario)
    //         );
    //     };
    //
    //     end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    // }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::ECampaignEnded)]
    fun contribute_to_campaign_after_campaign_duration() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 100;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        clock::increment_for_testing(&mut clock, MS_IN_A_DAY * 14 + 1);

        ts::next_tx(scenario, CAROL);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    // cancel
    #[test]
    fun cancel_campaign() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 100;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, CAROL);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        assert!(get_coins_balance<SUI>(scenario, ALICE) == INITIAL_STARTING_COINS, 1);
        assert!(get_coins_balance<SUI>(scenario, BOB) == INITIAL_STARTING_COINS - 2 * contribution_amount, 1);
        assert!(get_coins_balance<SUI>(scenario, CAROL) == INITIAL_STARTING_COINS - contribution_amount, 1);

        ts::next_tx(scenario, ALICE);
        {
            campaign::cancel(&mut campaign, &owner_cap, ts::ctx(scenario));
            assert!(verify_campaign_status(&campaign, SCancelled), 1);
            assert!(get_coins_balance<SUI>(scenario, ALICE) == INITIAL_STARTING_COINS, 1);
            assert!(get_coins_balance<SUI>(scenario, BOB) == INITIAL_STARTING_COINS, 1);
            assert!(get_coins_balance<SUI>(scenario, CAROL) == INITIAL_STARTING_COINS, 1);
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EUnauthorizedUser)]
    fun cancel_campaign_invalid_owner_cap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign1, owner_cap1, clock1) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );
        let (campaign2, owner_cap2, clock2) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign1, &owner_cap1, &clock1);
        };

        ts::next_tx(scenario, ALICE);
        {
            campaign::cancel(&mut campaign1, &owner_cap2, ts::ctx(scenario));
        };

        ts::return_to_address(ALICE, owner_cap1);
        ts::return_shared(campaign1);
        ts::return_shared(clock1);
        end_scenario(ALICE, owner_cap2, campaign2, scenario_val, clock2);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun cancel_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        ts::next_tx(scenario, ALICE);
        {
            campaign::cancel(&mut campaign, &owner_cap, ts::ctx(scenario));
        };

        ts::next_tx(scenario, ALICE);
        {
            campaign::cancel(&mut campaign, &owner_cap, ts::ctx(scenario));
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    // end, process_refund
    #[test]
    fun end_campaign_goal_reached() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 5000;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, CAROL);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        clock::increment_for_testing(&mut clock, MS_IN_A_DAY * 14 + 1);
        ts::next_tx(scenario, ALICE);
        {
            campaign::end(&mut campaign, &clock, ts::ctx(scenario));
            assert!(verify_campaign_status(&campaign, SSuccess), 1);
            assert!(get_coins_balance<SUI>(scenario, ALICE) == INITIAL_STARTING_COINS, 1);
            assert!(get_coins_balance<SUI>(scenario, BOB) == INITIAL_STARTING_COINS - contribution_amount * 2, 1);
            assert!(get_coins_balance<SUI>(scenario, CAROL) == INITIAL_STARTING_COINS - contribution_amount, 1);
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test]
    fun end_campaign_goal_failed() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 5000;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        assert!(get_coins_balance<SUI>(scenario, ALICE) == INITIAL_STARTING_COINS, 1);
        assert!(get_coins_balance<SUI>(scenario, BOB) == INITIAL_STARTING_COINS - contribution_amount, 1);
        assert!(get_coins_balance<SUI>(scenario, CAROL) == INITIAL_STARTING_COINS, 1);

        clock::increment_for_testing(&mut clock, MS_IN_A_DAY * 14 + 1);
        ts::next_tx(scenario, ALICE);
        {
            campaign::end(&mut campaign, &clock, ts::ctx(scenario));
            assert!(verify_campaign_status(&campaign, SFailure), 1);
            assert!(get_coins_balance<SUI>(scenario, ALICE) == INITIAL_STARTING_COINS, 1);
            assert!(get_coins_balance<SUI>(scenario, BOB) == INITIAL_STARTING_COINS, 1);
            assert!(get_coins_balance<SUI>(scenario, CAROL) == INITIAL_STARTING_COINS, 1);
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun end_campaign_disallowed_status() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        clock::increment_for_testing(&mut clock, MS_IN_A_DAY * 14 + 1);
        ts::next_tx(scenario, ALICE);
        {
            campaign::end(&mut campaign, &clock, ts::ctx(scenario));
        };

        ts::next_tx(scenario, ALICE);
        {
            campaign::end(&mut campaign, &clock, ts::ctx(scenario));
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }

    #[test, expected_failure(abort_code = crowd9_sc::campaign::EDisallowedAction)]
    fun end_campaign_before_stipulated_duration() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (campaign, owner_cap, clock) = init_scenario<SUI>(
            scenario,
            ALICE,
            INITIAL_PRICE_PER_TOKEN,
            INITIAL_FUNDING_GOAL
        );

        ts::next_tx(scenario, ALICE);
        {
            campaign::start(&mut campaign, &owner_cap, &clock);
        };

        let contribution_amount = 5000;
        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, BOB);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        ts::next_tx(scenario, CAROL);
        {
            let user = tx_context::sender(ts::ctx(scenario));
            campaign::contribute(
                take_coins<SUI>(scenario, user, contribution_amount),
                &mut campaign,
                &clock,
                ts::ctx(scenario)
            );
        };

        clock::increment_for_testing(&mut clock, MS_IN_A_DAY * 7);
        ts::next_tx(scenario, ALICE);
        {
            campaign::end(&mut campaign, &clock, ts::ctx(scenario));
        };

        end_scenario(ALICE, owner_cap, campaign, scenario_val, clock);
    }
}