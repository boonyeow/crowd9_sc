#[test_only]
module crowd9_sc::marketplace_tests{
    use crowd9_sc::marketplace::{Self, Market};
    use crowd9_sc::my_module::{Self, Card};
    use std::debug::{Self};
    use sui::test_scenario::{Self, Scenario};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::transfer::{Self};
    // use sui::balance::{Self, Balance};
    use std::vector;

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    // ======= Constants =======
    const ENotOwner:u64 = 0; // Error code when user tries to access a restricted / owner-only function
    const EHasExistingOffer:u64 = 1; // Error code when user has already made an offer for a listing
    const EMustNotBeOwner:u64 = 2; // Error code when user tries to make an offer to his/her own listing
    const EAmountIncorrect:u64 = 3; // Error code when user supply incorrect coin amount to purchase NFT
    const EMustBeOwner:u64 = 4; // Error code when non-owner tries to delist
    const EOfferorDoesNotExist:u64 = 5; // Error code when offeror does not have an existing offer
    const POPTART:u8 = 0; // Used as a constant value to construct Set using Table i.e. Table<ID, POPTART>


    fun init_marketplace(scenario: &mut Scenario): Market<SUI>{
        test_scenario::next_tx(scenario, ADMIN);
        marketplace::test_init(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        test_scenario::take_shared<Market<SUI>>(scenario)
    }

    fun init_test_accounts(scenario: &mut Scenario, value: u64) {
        test_scenario::next_tx(scenario, ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ADMIN);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), ALICE);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), BOB);
        transfer::transfer(coin::mint_for_testing<SUI>(value, test_scenario::ctx(scenario)), CAROL);
    }

    fun mint_nft(scenario: &mut Scenario, user:address): Card{
        test_scenario::next_tx(scenario, user);
        my_module::mint_card(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, user);
        test_scenario::take_from_address<Card>(scenario, user)
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user:address, amount: u64) : Coin<T>{
        test_scenario::next_tx(scenario, user);
        let coins = test_scenario::take_from_address<Coin<T>>(scenario, user);
        let split_coin= coin::split(&mut coins, amount, test_scenario::ctx(scenario));
        test_scenario::return_to_address(user, coins);
        split_coin
    }

    fun get_coins_balance<T: drop>(scenario: &mut Scenario, user: address): u64{
        test_scenario::next_tx(scenario, user);
        let ids = test_scenario::ids_for_sender<Coin<T>>(scenario);
        let combined_balance = 0;

        while(!vector::is_empty(&ids)){
            let id = vector::pop_back(&mut ids);
            let coin = test_scenario::take_from_address_by_id<Coin<T>>(scenario, user, id);
            combined_balance = combined_balance + coin::value(&coin);
            test_scenario::return_to_address(user, coin);
        };
        combined_balance
    }

    #[test]
    fun check_init_test_accounts(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let coins_to_mint = 100;

        init_test_accounts(scenario, coins_to_mint);
        test_scenario::next_tx(scenario, ADMIN);

        let admin_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, ADMIN);
        let alice_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, ALICE);
        let bob_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, BOB);
        let carol_coin = test_scenario::take_from_address<Coin<SUI>>(scenario, CAROL);

        assert!(coin::value(&admin_coin) == coins_to_mint, 0);
        assert!(coin::value(&alice_coin) == coins_to_mint, 0);
        assert!(coin::value(&bob_coin) == coins_to_mint, 0);
        assert!(coin::value(&carol_coin) == coins_to_mint, 0);

        test_scenario::return_to_address(ADMIN, admin_coin);
        test_scenario::return_to_address(ALICE, alice_coin);
        test_scenario::return_to_address(BOB, bob_coin);
        test_scenario::return_to_address(CAROL, carol_coin);

        test_scenario::end(scenario_val);
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

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ALICE);
        {
            let test_coin = take_coins(scenario, ALICE, 5);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));

        };

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EHasExistingOffer)]
    fun make_multiple_offers_to_listing(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, BOB, 5);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, BOB, 5);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun buy_without_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin = take_coins(scenario, BOB, listing_price);
            marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, BOB);
        {
            // check who owns it
            let bought_nft = test_scenario::take_from_address<Card>(scenario, BOB); // will not fetch nft if theres error
            test_scenario::return_to_address(BOB,bought_nft);

            // check if owner received proceeds
            let proceeds = test_scenario::take_from_address<Coin<SUI>>(scenario, ALICE);
            debug::print(&proceeds);
            assert!(coin::value(&proceeds) == listing_price, EAmountIncorrect);
            test_scenario::return_to_address(ALICE, proceeds);
        };

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun buy_with_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, BOB, 5);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin: Coin<SUI> = take_coins(scenario,CAROL, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ADMIN);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, ADMIN, listing_price);
            marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        assert!(get_coins_balance<SUI>(scenario, BOB) == 100, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, CAROL) == 100, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, ADMIN) == 90, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, ALICE) == 110, EAmountIncorrect);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EMustNotBeOwner)]
    fun buy_own_listing(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ALICE);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, ALICE, listing_price);
            marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EAmountIncorrect)]
    fun buy_with_incorrect_amount(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 15;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, BOB, 10);
            marketplace::buy<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };
        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun delist_without_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ALICE);
        // let retrieved_id = marketplace::get_listing_id(&marketplace_obj, listing_id);
        // debug::print(&retrieved_id);
        marketplace::delist<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));
        let retrieved_id1 = marketplace::get_listing_id(&marketplace_obj, listing_id);
        debug::print(&retrieved_id1);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun delist_with_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin: Coin<SUI> = take_coins(scenario, BOB, 5);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin: Coin<SUI> = take_coins(scenario,CAROL, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj,  listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ALICE);
        marketplace::delist<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));

        assert!(get_coins_balance<SUI>(scenario, BOB) == 100, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, CAROL) == 100, EAmountIncorrect);

        let retrieved_id1 = marketplace::get_listing_id(&marketplace_obj, listing_id);
        debug::print(&retrieved_id1);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EMustBeOwner)]
    fun delist_but_not_owner(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);
        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        marketplace::delist<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun accept_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, BOB, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, CAROL, 20);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ALICE);
        marketplace::accept_offer<Card, SUI>(&mut marketplace_obj, listing_id, CAROL, test_scenario::ctx(scenario));

        // Check everyone's coin balance
        assert!(get_coins_balance<SUI>(scenario, ALICE) == 120, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, BOB) == 100, EAmountIncorrect);
        assert!(get_coins_balance<SUI>(scenario, CAROL) == 80, EAmountIncorrect);

        let purchased_nft = test_scenario::take_from_address<Card>(scenario, CAROL);
        test_scenario::return_to_address<Card>(CAROL, purchased_nft);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);

        /*
        test_scenario::next_tx(scenario, ADMIN);

        this is for scenario where ADMIN initially does not own any card
        test_scenario::take_from_address<Card>(scenario, ADMIN); // if this is successful -> ADMIN owns the card
        this is for scenario where ADMIN owns multiple card
        test_scenario::take_from_address_by_id<Card>(scenario, ADMIN, <id_of_nft>);

        test_scenario::return_to_address(ADMIN, <obj>);
        object::delete(<obj>.id);
        */
    }


    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::ENotOwner)]
    fun accept_but_not_owner(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, BOB, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, CAROL, 20);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ADMIN);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, ADMIN, 25);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, BOB);
        marketplace::accept_offer<Card, SUI>(&mut marketplace_obj, listing_id, BOB, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }


    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EMustNotBeOwner)]
    fun accept_but_buyer_is_owner(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, BOB, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, CAROL, 20);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ALICE);
        marketplace::accept_offer<Card, SUI>(&mut marketplace_obj, listing_id, ALICE, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }


    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EOfferorDoesNotExist)]
    fun accept_but_no_offer_from_offeror(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, BOB, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, CAROL);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, CAROL, 20);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, BOB);
        {
            marketplace::cancel_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, ALICE);
        marketplace::accept_offer<Card, SUI>(&mut marketplace_obj, listing_id, BOB, test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun cancel_offer(){
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            let test_coin : Coin<SUI> = take_coins(scenario, BOB, 15);
            marketplace::make_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_coin, test_scenario::ctx(scenario));
        };

        assert!(get_coins_balance<SUI>(scenario, BOB) == 85, EAmountIncorrect);

        marketplace::cancel_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));

        assert!(get_coins_balance<SUI>(scenario, BOB) == 100, EAmountIncorrect);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::marketplace::EOfferorDoesNotExist)]
    fun cancel_without_offer() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;

        init_test_accounts(scenario, 100);
        let marketplace_obj = init_marketplace(scenario);
        let nft_obj = mint_nft(scenario, ALICE);

        let listing_price = 10;
        let listing_id = marketplace::list(&mut marketplace_obj, nft_obj, listing_price, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, BOB);
        {
            marketplace::cancel_offer<Card, SUI>(&mut marketplace_obj, listing_id, test_scenario::ctx(scenario));
        };

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }
}