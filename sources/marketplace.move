module crowd9_sc::marketplace {
    // use sui::object::{Self, ID, UID, id_to_address};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    // use std::vector;
    use sui::coin::{Self, Coin};

    // use std::option::{Self, Option};
    use sui::dynamic_object_field::{Self as ofield};
    use sui::balance::{/*Self,*/Balance};
    use sui::event::emit;
    use sui::table::{Self, Table};
    // use std::debug::{Self};
    use sui::vec_set::{Self, VecSet};

    // ======= Constants =======
    const ENotOwner:u64 = 0; // Error code when user tries to access a restricted / owner-only function
    const EHasExistingOffer:u64 = 1; // Error code when user has already made an offer for a listing
    const EMustNotBeOwner:u64 = 2; // Error code when user tries to make an offer to his/her own listing
    const POPTART:u8 = 0; // Used as a constant value to construct Set using Table i.e. Table<ID, POPTART>

    // ======= Types =======
    struct Market<phantom COIN> has key {
        id: UID,
        listing_ids: VecSet<ID>
    }

    struct Listing has key, store{
        id: UID,
        price: u64,
        owner: address,
        offerors: VecSet<address>,
        offer_data: Table<address, Balance<SUI>>
    }

    // ======= Events =======
    struct ListEvent<phantom T> has copy, drop{
        listing_id: ID,
        nft_id:ID,
        owner: address,
        price: u64,
    }

    struct DelistEvent<phantom T> has copy, drop{
        listing_id:ID,
        nft_id: ID,
    }

    struct OfferEvent<phantom T> has copy, drop{
        nft_id: ID,
        offer_value: u64,
        offeror:address
    }


    // ======= Core Functionalities =======
    fun init(ctx: &mut TxContext){
        // create a shared marketplace that accepts SUI coin
        let id = object::new(ctx);
        let listing_ids = vec_set::empty<ID>();
        transfer::share_object(Market<SUI>{ id , listing_ids })
    }

    public fun list<T: key + store, COIN>(market: &mut Market<COIN>, nft: T, price: u64, ctx: &mut TxContext): ID{
        let id = object::new(ctx);
        let nft_id = object::id(&nft);
        let owner = tx_context::sender(ctx);
        let offer_data = table::new(ctx);
        let offerors = vec_set::empty<address>();
        let listing = Listing { id, price, owner, offerors, offer_data};

        emit(ListEvent<T> {  // emit an event when listed;
            listing_id: object::id(&listing),
            nft_id,
            owner,
            price
        });

        let listing_id = object::id(&listing);
        vec_set::insert(&mut market.listing_ids, listing_id);

        ofield::add(&mut listing.id, true, nft); //assigned true to indicate listed & set nft as child
        ofield::add(&mut market.id, nft_id, listing);
        return listing_id
    }

    // Make offer function
    public entry fun make_offer<T: key + store, COIN>(market:&mut Market<COIN>, nft_id: ID, offered: Coin<SUI>, ctx:&mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, nft_id);
        let offeror = tx_context::sender(ctx);

        assert!(listing.owner != offeror, EMustNotBeOwner);
        assert!(!table::contains(&listing.offer_data, offeror), EHasExistingOffer);
        // another scenario -> supplied coins > price -> to immediate purchase, or disallow 

        emit(OfferEvent<T>{
            nft_id,
            offer_value: coin::value(&offered),
            offeror,
        });

        vec_set::insert(&mut listing.offerors, offeror);
        table::add(&mut listing.offer_data, offeror, coin::into_balance(offered));
    }

    // To do
    // Purchase NFT Function
    public entry fun buy(){}

    // Accept offer function
    public entry fun accept_offer(){}

    // get all offers

    // get all listings


    // ======= Unit Tests =======

    #[test]
    fun testing1(){
        use std::debug::{Self};
        use sui::test_scenario::{Self};
        // use sui::coin;
        use crowd9_sc::my_module;
        let admin = @0xCAFE;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // initialize marketplace
        let marketplace_id = {
            let ctx = test_scenario::ctx(scenario);
            init(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };
        debug::print(&marketplace_id);

        // create NFT
        let user1 = @0xAAAA;
        test_scenario::next_tx(scenario, user1);
        let nft_id = {
            let ctx = test_scenario::ctx(scenario);
            my_module::mint_card(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };

        // list NFT
        test_scenario::next_tx(scenario, user1);
        let marketplace_obj = test_scenario::take_shared<Market<SUI>>(scenario);
        debug::print(&marketplace_obj);

        let nft_obj: my_module::Card = test_scenario::take_from_address_by_id(scenario, user1, nft_id);
        debug::print(&nft_obj);

        debug::print(&b"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy");
        debug::print(&marketplace_obj);
        debug::print(&b"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy");

        debug::print(&b"000000000000000000000000000000000000000000000000000000000000000000000000000000");
        list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));

        let listing_id =  object::id_from_address(tx_context::last_created_object_id(test_scenario::ctx(scenario)));
        debug::print(&listing_id);

        debug::print(&b"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy");
        debug::print(&marketplace_obj);
        debug::print(&b"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy");

        let user2 = @0xAAAB;
        test_scenario::next_tx(scenario, user2);

        let test_coins:Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        make_offer<my_module::Card, SUI>(&mut marketplace_obj, nft_id, test_coins,test_scenario::ctx(scenario));


        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code =  crowd9_sc::marketplace::EMustNotBeOwner)]
    fun test_owner_make_offer(){
        use sui::test_scenario::{Self};
        use crowd9_sc::my_module;
        let admin = @0xCAFE;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // initialize marketplace
        {
            let ctx = test_scenario::ctx(scenario);
            init(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };

        // create NFT
        let user1 = @0xAAAA;
        test_scenario::next_tx(scenario, user1);
        let nft_id = {
            let ctx = test_scenario::ctx(scenario);
            my_module::mint_card(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };

        // list NFT
        test_scenario::next_tx(scenario, user1);
        let marketplace_obj = test_scenario::take_shared<Market<SUI>>(scenario);

        let nft_obj: my_module::Card = test_scenario::take_from_address_by_id(scenario, user1, nft_id);

        list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user1);

        let test_coins:Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        make_offer<my_module::Card, SUI>(&mut marketplace_obj, nft_id, test_coins,test_scenario::ctx(scenario));


        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code =  crowd9_sc::marketplace::EHasExistingOffer)]
    fun test_has_existing_offer(){
        use sui::test_scenario;
        use crowd9_sc::my_module;
        let admin = @0xCAFE;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // initialize marketplace
        {
            let ctx = test_scenario::ctx(scenario);
            init(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };

        // create NFT
        let user1 = @0xAAAA;
        test_scenario::next_tx(scenario, user1);
        let nft_id = {
            let ctx = test_scenario::ctx(scenario);
            my_module::mint_card(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };

        // list NFT
        test_scenario::next_tx(scenario, user1);
        let marketplace_obj = test_scenario::take_shared<Market<SUI>>(scenario);

        let nft_obj: my_module::Card = test_scenario::take_from_address_by_id(scenario, user1, nft_id);
        list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));
        let user2 = @0xAAAB;
        test_scenario::next_tx(scenario, user2);

        let test_coins:Coin<SUI> = coin::mint_for_testing(5, test_scenario::ctx(scenario));
        make_offer<my_module::Card, SUI>(&mut marketplace_obj, nft_id, test_coins,test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user2);
        let test_coins1:Coin<SUI> = coin::mint_for_testing(10, test_scenario::ctx(scenario));
        make_offer<my_module::Card, SUI>(&mut marketplace_obj, nft_id, test_coins1,test_scenario::ctx(scenario));

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }
}
