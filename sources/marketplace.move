module crowd9_sc::marketplace {
    // use sui::object::{Self, ID, UID, id_to_address};
    use sui::object::{Self, ID, UID, id_to_address};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use std::vector;
    // use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as ofield;
    use sui::balance::Balance;
    use sui::event::emit;
    // use std::debug::{Self};

    // ======= Constants =======
    const ENotOwner:u8 = 0; // Error code for restricted access function

    // ======= Types =======
    struct Market<phantom COIN> has key {
        id: UID,
        listed: vector<address>
    }

    struct Listing has key, store{
        id: UID,
        price: u64,
        owner: address,
        offers: vector<Offer>
    }

    struct Offer has key, store{
        id: UID,
        offeror: address,
        amount_offered: Balance<SUI>
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

    // ======= Core Functionalities =======
    fun init(ctx: &mut TxContext){
        // create a shared marketplace that accepts SUI coin
        let id = object::new(ctx);
        let listed = vector::empty();
        transfer::share_object(Market<SUI>{ id , listed })
    }

    public entry fun list<T: key + store, COIN>(
        market: &mut Market<COIN>,
        nft: T,
        price: u64,
        ctx: &mut TxContext
    ){
        let id = object::new(ctx);
        let nft_id = object::id(&nft);
        let owner = tx_context::sender(ctx);
        let offers = vector::empty();
        let listing = Listing { id, price, owner, offers};

        emit(ListEvent<T> {  // emit an event when listed;
            listing_id: object::id(&listing),
            nft_id,
            owner,
            price
        });

        vector::push_back(&mut market.listed, id_to_address(&nft_id)); // keep track of listed NFTs
        ofield::add(&mut id, true, nft); //assigned true to indicate listed & set nft as child
        ofield::add(&mut market.id, nft_id, listing);
    }

    public fun delist<T: key + store, COIN>(
        market: &mut Market<COIN>,
        listing_id: ID,
        ctx: &mut TxContext
    ){
        // removing or unwrapping dynamic field
        let Listing {id, price: _, owner, offers: _} = ofield::remove<ID, Listing>(&mut market.id, listing_id);
        let nft = ofield::remove(&mut id, true);

        // restrict delist capability to only owner
        assert!(tx_context::sender(ctx) == owner, ENotOwner);

        //emit delist event
        emit(DelistEvent<T>{
            listing_id,
            nft_id: object::id(&nft)
        });

        // clean up unused ids & pop from vector
        object::delete(id);
        // vector::pop_back(&mut market.listed, id_to_address(id));

        return nft
    }

    // To do
    // Purchase NFT Function
    public entry fun buy(){}

    // Make offer function
    public entry fun make_offer(){}

    // Accept offer function
    public entry fun accept_offer(){}

    // get all offers

    // get all listings



    // ======= Unit Tests =======
    #[test]
    fun testing1(){
        use std::debug::{Self};
        use sui::test_scenario::{Self};
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
        debug::print(&nft_id);

        // list NFT
        test_scenario::next_tx(scenario, user1);

        let marketplace_obj:Market<SUI> = test_scenario::take_shared_by_id(scenario, marketplace_id);
        debug::print(&marketplace_obj);

        let nft_obj: my_module::Card = test_scenario::take_from_address_by_id(scenario, user1, nft_id);
        debug::print(&nft_obj);

        list(&mut marketplace_obj, nft_obj, 10, test_scenario::ctx(scenario));


        test_scenario::next_tx(scenario, user1);

        debug::print(&marketplace_obj);

        test_scenario::next_tx(scenario, user1);
        let nft_id1 = {
            let ctx = test_scenario::ctx(scenario);
            my_module::mint_card(ctx);
            object::id_from_address(tx_context::last_created_object_id(ctx))
        };
        debug::print(&nft_id1);

        test_scenario::next_tx(scenario, user1);
        let nft_obj1: my_module::Card = test_scenario::take_from_address_by_id(scenario, user1, nft_id1);
        debug::print(&nft_obj1);

        list(&mut marketplace_obj, nft_obj1, 10, test_scenario::ctx(scenario));


        debug::print(&marketplace_obj);

        test_scenario::return_shared(marketplace_obj);
        test_scenario::end(scenario_val);
    }
}
