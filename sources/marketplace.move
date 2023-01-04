module crowd9_sc::marketplace {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use std::vector;
    use sui::coin::{Self, Coin};

    use sui::dynamic_object_field::{Self as ofield};
    use sui::balance::{Self, Balance};
    use sui::event::emit;
    use sui::table::{Self, Table};
    use std::debug::{Self};
    use sui::vec_set::{Self, VecSet};

    // ======= Constants =======
    const ENotOwner:u64 = 0; // Error code when user tries to access a restricted / owner-only function
    const EHasExistingOffer:u64 = 1; // Error code when user has already made an offer for a listing
    const EMustNotBeOwner:u64 = 2; // Error code when user tries to make an offer to his/her own listing
    const EAmountIncorrect:u64 = 3; // Error code when user supply incorrect coin amount to purchase NFT
    const EMustBeOwner:u64 = 4; // Error code when non-owner tries to delist
    const EOfferorDoesNotExist:u64 = 5; // Error code when offeror does not have an existing offer
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
        owner: address,
    }

    struct BuyEvent<phantom T> has copy, drop{
        listing_id:ID,
        price: u64,
        buyer: address,
    }

    struct OfferEvent<phantom T> has copy, drop{
        listing_id: ID,
        offer_value: u64,
        offeror:address
    }

    struct AcceptOfferEvent<phantom T> has copy, drop{
        listing_id: ID,
        offer_value: u64,
        offeror:address
    }

    // ======= Core Functionalities =======
    fun init(ctx: &mut TxContext){
        debug::print(&b"hihi");
        // create a shared marketplace that accepts SUI coin
        let id = object::new(ctx);
        let listing_ids = vec_set::empty<ID>();
        transfer::share_object(Market<SUI>{ id , listing_ids })
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext){
        // create a shared marketplace that accepts SUI coin
        let id = object::new(ctx);
        let listing_ids = vec_set::empty<ID>();
        transfer::share_object(Market<SUI>{ id , listing_ids })
    }

    public fun list<T: key + store, COIN>(market: &mut Market<COIN>, nft: T, price: u64, ctx: &mut TxContext): ID {
        let id = object::new(ctx);
        let nft_id = object::id(&nft);
        let owner = tx_context::sender(ctx);
        let offer_data = table::new(ctx);
        let offerors = vec_set::empty<address>();
        let listing = Listing { id, price, owner, offerors, offer_data };

        emit(ListEvent<T> {
            // emit an event when listed;
            listing_id: object::id(&listing),
            nft_id,
            owner,
            price
        });

        let listing_id = object::id(&listing);
        vec_set::insert(&mut market.listing_ids, listing_id);

        ofield::add(&mut listing.id, true, nft); //assigned true to indicate listed & set nft as child
        ofield::add(&mut market.id, listing_id, listing);
        return listing_id
    }

    public fun delist<T: key + store, COIN>(market:&mut Market<COIN>, listing_id: ID, ctx: &mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        let sender = tx_context::sender(ctx);

        assert!(listing.owner == sender, EMustBeOwner);

        emit(DelistEvent<T>{ listing_id, owner: listing.owner });

        refund_offerors(listing, ctx);
        vec_set::remove(&mut market.listing_ids, &listing_id);

        let Listing{id, price:_, owner:_, offerors:_, offer_data} = ofield::remove(&mut market.id, object::id(listing));
        object::delete(id);
        table::destroy_empty(offer_data);
    }

    public entry fun buy<T: key + store,COIN>(market: &mut Market<COIN>, listing_id: ID, paid: Coin<SUI>, ctx: &mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        let buyer = tx_context::sender(ctx);

        assert!(listing.owner != buyer, EMustNotBeOwner);
        assert!(listing.price == coin::value(&paid), EAmountIncorrect);

        emit(BuyEvent<T>{ listing_id, buyer, price: listing.price });

        refund_offerors(listing, ctx);
        transfer::transfer(paid,listing.owner); // transfer amount to seller
        let nft:T = ofield::remove(&mut listing.id, true);
        transfer::transfer(nft, buyer); // transfer nft to buyer
    }

    fun refund_offerors(listing: &mut Listing, ctx: &mut TxContext){
        let offerors = vec_set::into_keys(listing.offerors);

        // refund all offers
        while(!vector::is_empty(&offerors)){
            let offeror = vector::pop_back(&mut offerors);
            let offer_balance = table::remove(&mut listing.offer_data, offeror);
            transfer::transfer(coin::from_balance(offer_balance, ctx), offeror);
            // debug::print(&offeror);debug::print(&offeror);debug::print(&offeror);
        };
    }

    public entry fun make_offer<T: key + store, COIN>(market:&mut Market<COIN>, listing_id: ID, offered: Coin<SUI>, ctx:&mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        let offeror = tx_context::sender(ctx);
        assert!(listing.owner != offeror, EMustNotBeOwner);
        assert!(!table::contains(&listing.offer_data, offeror), EHasExistingOffer);
        // another scenario -> supplied coins > price -> to immediate purchase, or disallow
        // listing.price
        emit(OfferEvent<T>{ listing_id, offer_value: coin::value(&offered), offeror });

        vec_set::insert(&mut listing.offerors, offeror);
        table::add(&mut listing.offer_data, offeror, coin::into_balance(offered));
    }

    // // Accept offer function
    public entry fun accept_offer<T: key + store, COIN>(
        market: &mut Market<COIN>,
        listing_id: ID,
        accepted_offeror: address,
        ctx: &mut TxContext
    ) {
        // Get NFT listing
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        // Get address of transaction initiator (person who is accepting offer)
        let person_accepting = tx_context::sender(ctx);

        // Check if person accepting is NFT owner
        assert!(person_accepting == listing.owner, ENotOwner);
        // Check if person accepting is not accepted NFT offeror
        assert!(person_accepting != accepted_offeror, EMustNotBeOwner);
        // Check if accepted offeror has an existing offer
        assert!(table::contains(&listing.offer_data, accepted_offeror), EOfferorDoesNotExist);

        // Remove accepted offer from listing's offerors' VecSet, offer_data's Table
        vec_set::remove(&mut listing.offerors, &accepted_offeror);
        let accepted_price = table::remove(&mut listing.offer_data, accepted_offeror);

        // Emit event
        emit(AcceptOfferEvent<T>{
            listing_id,
            offer_value: balance::value(&accepted_price),
            offeror: accepted_offeror
        });

        // Transfer amount to NFT owner
        transfer::transfer(coin::from_balance(accepted_price, ctx), listing.owner);

        // Transfer NFT from listing struct to offeror
        let nft:T = ofield::remove(&mut listing.id, true);
        transfer::transfer(nft, accepted_offeror);

        // Refund offerors who were not accepted
        refund_offerors(listing, ctx);

        // Clean up
        let Listing{
            id,
            price:_,
            owner:_,
            offerors:_,
            offer_data
        } = ofield::remove(&mut market.id, object::id(listing));
        object::delete(id);
        table::destroy_empty(offer_data);
    }

    // Cancel offer function
    public entry fun cancel_offer<T: key + store, COIN>(
        market: &mut Market<COIN>,
        listing_id: ID,
        ctx: &mut TxContext
    ) {
        // Get NFT listing
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        // Get address of transaction initiator (person who is accepting offer)
        let person_canceling = tx_context::sender(ctx);

        // Check if person canceling has an existing offer made
        assert!(table::contains(&listing.offer_data, person_canceling), EOfferorDoesNotExist);

        // Remove offer, Refund user
        vec_set::remove(&mut listing.offerors, &person_canceling);
        let offered_price = table::remove(&mut listing.offer_data, person_canceling);
        transfer::transfer(coin::from_balance(offered_price, ctx), person_canceling);
    }


    // get all offers

    // get all listings
    #[test_only]
    public fun get_listing_id(marketplace: &Market<SUI>,listing_id: ID) : ID{
        let listing: &Listing = ofield::borrow(&marketplace.id, listing_id);
        object::uid_to_inner(&listing.id)
    }

    struct TestCapability has key {id:UID}


    const ADMIN: address = @0xCAFE;
    const BOB: address = @0xCAFA;
    #[test_only]
    fun testcap() {
        use sui::test_scenario::{Self};
        use sui::object::{Self};
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        transfer::transfer(TestCapability { id: object::new(test_scenario::ctx(scenario)) }, ADMIN);
        test_scenario::next_tx(scenario, ADMIN);
        {
        let x: TestCapability = test_scenario::take_from_address(scenario, ADMIN);
        debug::print(&x);
        transfer::transfer(x, BOB);
        };
        test_scenario::next_tx(scenario, BOB);
        {
        let x: TestCapability = test_scenario::take_from_address(scenario, ADMIN);
        debug::print(&x);
        test_scenario::return_to_address(BOB, x);
        };

        test_scenario::end(scenario_val);
    }
}
