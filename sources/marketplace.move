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
    const EAmountIncorrect:u64 = 3; // Error code when user supply incorrect coin amount to purchase NFT
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
        listing_id: ID,
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

    #[test_only]
    public fun test_init(ctx: &mut TxContext){
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
        ofield::add(&mut market.id, listing_id, listing);
        return listing_id
    }

    // use std::debug;
    use std::vector;
    public entry fun buy<T: key + store,COIN>(market: &mut Market<COIN>, listing_id: ID, paid: Coin<SUI>, ctx: &mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        let buyer = tx_context::sender(ctx);

        assert!(listing.owner != buyer, EMustNotBeOwner);
        assert!(listing.price == coin::value(&paid), EAmountIncorrect);
        let offerors = vec_set::into_keys(listing.offerors);

        // refund all offers
        while(!vector::is_empty(&offerors)){
            let offeror = vector::pop_back(&mut offerors);
            let offer_balance = table::remove(&mut listing.offer_data, offeror);
            transfer::transfer(coin::from_balance(offer_balance, ctx), offeror);
            // debug::print(&offeror);debug::print(&offeror);debug::print(&offeror);
        };

        transfer::transfer(paid,listing.owner); // transfer amount to seller
        let nft:T = ofield::remove(&mut listing.id, true);
        transfer::transfer(nft, buyer); // transfer nft to buyer

        // clean up
        let Listing{id, price:_, owner:_, offerors:_, offer_data} = ofield::remove(&mut market.id, object::id(listing));
        object::delete(id);
        table::destroy_empty(offer_data);
    }

    public entry fun make_offer<T: key + store, COIN>(market:&mut Market<COIN>, listing_id: ID, offered: Coin<SUI>, ctx:&mut TxContext){
        let listing = ofield::borrow_mut<ID, Listing>(&mut market.id, listing_id);
        let offeror = tx_context::sender(ctx);
        assert!(listing.owner != offeror, EMustNotBeOwner);
        assert!(!table::contains(&listing.offer_data, offeror), EHasExistingOffer);
        // another scenario -> supplied coins > price -> to immediate purchase, or disallow

        emit(OfferEvent<T>{
            listing_id,
            offer_value: coin::value(&offered),
            offeror,
        });

        vec_set::insert(&mut listing.offerors, offeror);
        table::add(&mut listing.offer_data, offeror, coin::into_balance(offered));
    }

    // Accept offer function
    public entry fun accept_offer(){}

    // get all offers

    // get all listings

}
