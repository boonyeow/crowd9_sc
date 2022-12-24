#[test_only]
module crowd9_sc::marketplace_tests{
    use crowd9_sc::marketplace::{Self, Market};
    use crowd9_sc::my_module::{Self, Card};
    use std::debug::{Self};
    use sui::test_scenario::{Self, Scenario};
    // use sui::object::{Self};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    // ======= Constants =======
    const ENotOwner:u64 = 0; // Error code when user tries to access a restricted / owner-only function
    const EHasExistingOffer:u64 = 1; // Error code when user has already made an offer for a listing
    const EMustNotBeOwner:u64 = 2; // Error code when user tries to make an offer to his/her own listing
    const EAmountIncorrect:u64 = 3; // Error code when user supply incorrect coin amount to purchase NFT
    const POPTART:u8 = 0; // Used as a constant value to construct Set using Table i.e. Table<ID, POPTART>


    fun init_marketplace(scenario: &mut Scenario): Market<SUI>{
        test_scenario::next_tx(scenario, ADMIN);
        marketplace::test_init(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        test_scenario::take_shared<Market<SUI>>(scenario)
    }

    fun mint_nft(scenario: &mut Scenario, user:address): Card{
        test_scenario::next_tx(scenario, user);
        my_module::mint_card(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, user);
        test_scenario::take_from_address<Card>(scenario, user)
    }

    #[test]
    fun create_marketplace(){
        debug::print(&b"hi");
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun list_nft(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ADMIN);
        marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EMustNotBeOwner)]
    fun make_offer_to_own_listing(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        // let nft_id = object::id(&nft_obj);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ALICE);
        let test_coin: Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EHasExistingOffer)]
    fun make_multiple_offers_to_listing(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        // let nft_id = object::id(&nft_obj);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, BOB);
        let test_coin: Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        let test_coin2: Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin2, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun buy_without_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, BOB);
        let test_coin: Coin<SUI> = coin::mint_for_testing(10, test_scenario::ctx(scenario));
        let list_price = coin::value(&test_coin);
        marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        // check who owns it
        let bought_nft = test_scenario::take_from_address<Card>(scenario, BOB);
        debug::print(&bought_nft);
        test_scenario::return_to_address(BOB,bought_nft);

        // check if owner received proceeds
        let proceeds = test_scenario::take_from_address<Coin<SUI>>(scenario, ALICE);
        debug::print(&proceeds);
        assert!(coin::value(&proceeds) == list_price, EAmountIncorrect);
        test_scenario::return_to_address(ALICE, proceeds);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun buy_with_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        // let nft_id = object::id(&nft_obj);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, BOB);
        let test_coin: Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, CAROL);
        let test_coin1: Coin<SUI> = coin::mint_for_testing(9, test_scenario::ctx(scenario));
        marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin1, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ADMIN);
        let test_coin2: Coin<SUI> = coin::mint_for_testing(10, test_scenario::ctx(scenario));
        marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin2, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        let refunded_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, BOB);
        assert!(coin::value(&refunded_coin) == 5, 0);
        test_scenario::return_to_address(BOB,refunded_coin);

        test_scenario::next_tx(scenario, CAROL);
        let refunded_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, CAROL);
        assert!(coin::value(&refunded_coin) == 9, 0);
        test_scenario::return_to_address(CAROL,refunded_coin);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EMustNotBeOwner)]
    fun buy_own_listing(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ALICE);
        let test_coin: Coin<SUI> = coin::mint_for_testing(10, test_scenario::ctx(scenario));
        marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EAmountIncorrect)]
    fun buy_with_incorrect_amount(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 15, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, BOB);
        let test_coin: Coin<SUI> = coin::mint_for_testing(10, test_scenario::ctx(scenario));
        marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }
}