module crowd9_sc::ob{
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, ID, UID};
    // use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::crit_bit_u64::{Self as cb, CB};
    use crowd9_sc::nft::{Self, Nft, Project};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;
    use std::option::{Self, Option};
    const MAX_BID_DEFAULT: u64 = 0;
    const MIN_ASK_DEFAULT: u64 = 0xffffffffffffffff;

    const S_CANCELLED:u8 = 0;
    const S_QUEUED:u8 = 1;
    const S_PARTIALLY_EXECUTED:u8 = 1;
    const S_EXECUTED:u8 = 1;

    struct Market has key, store{
        id: UID,
        data: Table<ID, ID>
    }

    struct CLOB has key, store{
        id: UID,
        asks: CB<OO<Ask>>,
        bids: CB<OO<Bid>>,
        registry: Table<ID, OrderInfo>
    }

    struct OO<T> has store{
        // OO - Open orders
        total_volume: u64,
        orders: vector<T>
    }

    struct Ask has key, store{
        id:UID,
        seller: address,
        price: u64,
        amount: u64, // nfts to sell
        nft: Nft
    }

    struct Bid has key, store{
        id: UID,
        buyer: address,
        price: u64,
        amount: u64, // nfts to buy
        offer: Balance<SUI> // balance.value = amount * price
    }

    struct OrderInfo has copy, drop, store {
        parent: Option<ID>,
        owner: address,
        price: u64,
        status: u8,
    }

    entry fun init(ctx: &mut TxContext){
        transfer::share_object(Market{
            id: object::new(ctx),
            data: table::new(ctx)
        });
    }

    #[test_only]
    public entry fun init_test(ctx: &mut TxContext){
        transfer::share_object(Market{
            id: object::new(ctx),
            data: table::new(ctx)
        });
    }

    public(friend) entry fun create_ob(project_id: ID, market: &mut Market, ctx: &mut TxContext){
        let clob = CLOB { id: object::new(ctx), asks: cb::empty(), bids: cb::empty(), registry: table::new(ctx) };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    #[test_only]
    public entry fun create_ob_test(project_id: ID, market: &mut Market, ctx: &mut TxContext){
        let clob = CLOB { id: object::new(ctx), asks: cb::empty(), bids: cb::empty(), registry: table::new(ctx) };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    public entry fun create_bid(clob: &mut CLOB, project: &mut Project, bid_offer: Coin<SUI>, amount:u64, price: u64, ctx: &mut TxContext){
        let bids_tree = &mut clob.bids;
        let registry = &mut clob.registry;
        let buyer = tx_context::sender(ctx);
        let offer = coin::into_balance(bid_offer);
        let bid = Bid { id: object::new(ctx), buyer, price, amount, offer };

        table::add(registry, object::id(&bid), OrderInfo {
            parent: option::none(),
            owner: buyer,
            price,
            status: S_QUEUED
        });

        let (crossed_asks, remaining_amount) = fetch_crossed_asks(&mut clob.asks, project, price, amount, ctx);

        if(!vector::is_empty(&crossed_asks)){
            fulfill_asks(&mut crossed_asks, &mut bid, project, registry, ctx);
        };
        vector::destroy_empty(crossed_asks);

        bid.amount = remaining_amount;
        if(bid.amount > 0){
            if(cb::has_key(bids_tree, price)){
                let price_level = cb::borrow_mut(bids_tree, price);
                price_level.total_volume = price_level.total_volume + amount;
                vector::push_back(&mut price_level.orders, bid);
            } else {
                cb::insert(bids_tree, price, OO{
                    total_volume: amount,
                    orders: vector::singleton(bid)
                });
            };
        } else {
            let Bid { id, buyer:_, price:_, amount:_, offer } = bid;
            let order_id = object::uid_to_inner(&id);
            object::delete(id);
            let offer_value = balance::value(&offer);
            if(offer_value > 0){
                transfer::transfer(coin::take(&mut offer, offer_value, ctx), buyer);
            };
            balance::destroy_zero(offer);
            let order_info = table::borrow_mut(registry, order_id);
            order_info.status = S_EXECUTED;
        };
    }

    fun fetch_crossed_asks(asks_tree: &mut CB<OO<Ask>>, project: &mut Project, bid_price: u64, bid_amount: u64, ctx: &mut TxContext): (vector<Ask>, u64){
        let min_ask = cb::min_key(asks_tree);
        let asks_to_fill = vector::empty();
        while(bid_price >= min_ask || bid_amount > 0){
            let price_level = cb::borrow_mut(asks_tree, min_ask);
            while(bid_amount != 0){
                let current_ask = vector::borrow_mut(&mut price_level.orders, 0);
                if(bid_amount >= current_ask.amount){
                    let removed_ask = vector::remove(&mut price_level.orders, 0);
                    bid_amount = bid_amount - removed_ask.amount;
                    vector::push_back(&mut asks_to_fill, removed_ask);
                } else {
                    current_ask.amount = current_ask.amount - bid_amount;
                    let split_ask = Ask {
                        id: object::new(ctx),
                        seller: current_ask.seller,
                        price: current_ask.price,
                        amount: bid_amount,
                        nft: nft::take(project, nft::balance_mut(&mut current_ask.nft), bid_amount, ctx)
                    };

                    vector::push_back(&mut asks_to_fill, split_ask);
                    bid_amount = 0;
                };

                if(vector::length(&price_level.orders) == 0){
                    let OO { total_volume:_, orders} = cb::pop(asks_tree, min_ask);
                    vector::destroy_empty(orders);
                    min_ask = cb::min_key(asks_tree);
                    break
                }
            };
        };
        (asks_to_fill, bid_amount)
    }

    fun fulfill_asks(asks: &mut vector<Ask>, bid: &mut Bid, project: &mut Project, registry: &mut Table<ID, OrderInfo>, ctx: &mut TxContext){
        let consolidated_nft = {
            let Ask {id, seller, price, amount, nft} = vector::pop_back(asks);
            let order_id = object::uid_to_inner(&id);
            table::borrow_mut(registry, order_id).status = S_EXECUTED;

            object::delete(id);
            transfer::transfer( coin::take(&mut bid.offer, price*amount, ctx), seller);
            nft
        };

        while(!vector::is_empty(asks)){
            let Ask {id, seller, price, amount, nft} = vector::pop_back(asks);
            let order_id = object::uid_to_inner(&id);
            table::borrow_mut(registry, order_id).status = S_EXECUTED;

            object::delete(id);
            transfer::transfer( coin::take(&mut bid.offer, price*amount, ctx), seller);
            nft::join(&mut consolidated_nft, nft, project);
        };
        transfer::transfer(consolidated_nft, bid.buyer);
    }

    #[test_only]
    public entry fun create_ask(clob: &mut CLOB, nft: Nft, price: u64, ctx: &mut TxContext){
        let seller = tx_context::sender(ctx);
        let asks_tree = &mut clob.asks;
        let nft_value = nft::nft_value(&nft);
        let ask = Ask { id: object::new(ctx), seller, price, amount:nft_value, nft };
        table::add(&mut clob.registry, object::id(&ask), OrderInfo{
            parent: option::none(),
            owner: seller,
            price,
            status: S_QUEUED
        });

        if(cb::has_key(asks_tree, price)){
            let price_level = cb::borrow_mut(asks_tree, price);
            vector::push_back(&mut price_level.orders, ask);
        } else {
            cb::insert(asks_tree, price, OO{
                total_volume: nft_value,
                orders:vector::singleton(ask)
            });
        };
    }

    /*
    public entry fun create_ask(clob: &mut CLOB, project: Project, nft: Nft, price: u64, ctx: &mut TxContext){
        let seller = tx_context::sender(ctx);
        // let bids_tree = &mut clob.bids;
        // let to_fill = nft::nft_value(&nft);
        // let bids_to_fill = vector::empty();

        // Add Ask to CLOB
        let asks_tree = &mut clob.asks;
        let ask = Ask { id: object::new(ctx), seller, price, amount:nft::nft_value(&nft) ,nft };
        table::add(&mut clob.registry, object::id(&ask), OrderInfo{
            parent: option::none(),
            owner: seller,
            price,
            status: S_QUEUED
        });

        if(cb::has_key(asks_tree, price)){
            let price_level = cb::borrow_mut(asks_tree, price);
            vector::push_back(&mut price_level.orders, ask);
        } else {
            let nft_value = nft::nft_value(&nft);
            cb::insert(asks_tree, price, OO{
                total_volume: nft_value,
                orders:vector::singleton(ask)
            });
        };

        // Call match_orders on CLOB
        match_order_asks(clob, price,ctx);
    }

    fun match_order_asks(clob: &mut CLOB, price: u64, ctx: &mut TxContext){
        let bids_tree = &mut clob.bids;
        let asks_tree = &mut clob.asks;
        // Match orders with max bid price >= ask price
        let max_bid_price = cb::max_key(&clob.bids);
        let ask_price_level = cb::borrow_mut(asks_tree, price);
        let bids_to_fill = vector::empty();
        let asks_to_fill = vector::empty();

        while (max_bid_price >= price) {
            let max_bid_price_level = cb::borrow_mut(bids_tree, max_bid_price);
            let volume_to_fill = ask_price_level.total_volume;
            let volume_filled = 0;

            // Add bids to fill to vector
            // if current bidding price level's volume is lower than asking price level's volume, add all bids to be fulfilled
            if (volume_to_fill >= max_bid_price_level.total_volume) {
                vector::append(&mut bids_to_fill, max_bid_price_level.orders);
                volume_filled = max_bid_price_level.total_volume;
                // Delete the OO for max_bid_price_level here (?)

            } else {
                // loop through bids at bidding price level until volume is filled or all bids fulfilled
                while (vector::length(&max_bid_price_level.orders) > 0) {
                    let current_bid = vector::borrow_mut(&mut max_bid_price_level.orders, 0);
                    let remaining_volume = volume_to_fill - volume_filled;
                    if (remaining_volume == 0) {
                        break;
                    };

                    // If current bid has lower volume, fulfil whatever's available, change the bid's amount to remainder
                    if (remaining_volume < current_bid.amount) {
                        current_bid.amount = current_bid.amount - remaining_volume;

                        let split_bid = Bid{
                            id: object::new(ctx),
                            buyer: current_bid.buyer,
                            price: current_bid.price,
                            amount: remaining_volume,
                            offer: balance::split(&mut current_bid.offer, remaining_volume*current_bid.price)
                        };

                        table::add(&mut clob.registry, object::id(&split_bid), OrderInfo{
                            parent: option::some(object::id(current_bid)),
                            owner: current_bid.buyer,
                            price: current_bid.price,
                            status: S_QUEUED
                        });

                        vector::push_back(&mut bids_to_fill, split_bid);
                        max_bid_price_level.total_volume = max_bid_price_level.total_volume - remaining_volume;
                        volume_filled = volume_filled + remaining_volume;
                    } else {
                        let removed_bid = vector::remove(&mut max_bid_price_level.orders, 0);
                        vector::push_back(&mut bids_to_fill, removed_bid);

                        max_bid_price_level.total_volume = max_bid_price_level.total_volume - removed_bid.amount;
                        volume_filled = volume_filled + removed_bid.amount;
                    };

                };
            };

            while (vector::length(&ask_price_level.orders) > 0) {
                if (volume_filled == 0) {
                    break;
                };

                let current_ask = vector::borrow_mut(&mut ask_price_level.orders, 0);
                if (volume_filled < current_ask.amount) {
                    current_ask.amount = current_ask.amount - volume_filled;

                    let split_ask = Ask{
                        id: object::new(ctx),
                        seller: current_ask.seller,
                        price: current_ask.price,
                        amount: volume_filled,
                        nft: current_ask.nft
                    };

                    table::add(&mut clob.registry, object::id(&split_ask), OrderInfo{
                        parent: option::some(object::id(current_ask)),
                        owner: current_ask.seller,
                        price: current_ask.price,
                        status: S_QUEUED
                    });

                    vector::push_back(&mut asks_to_fill, split_ask);
                    ask_price_level.total_volume = ask_price_level.total_volume - volume_filled;
                    volume_filled = 0;
                } else {
                    let removed_ask = vector::remove(&mut ask_price_level.orders, 0);
                    vector::push_back(&mut asks_to_fill, removed_ask);

                    ask_price_level.total_volume = ask_price_level.total_volume - removed_ask.amount;
                    volume_filled = volume_filled - removed_ask.amount;
                }
            };
            // not sure if still needed now that we changed the func to match_order_asks
            // if(vector::is_empty(&ask_price_level.orders)){
            //     let OO {total_volume:_, orders} = cb::pop(asks_tree, price);
            //     vector::destroy_empty(orders);
            //     min_ask_price = cb::min_key(asks_tree);
            // };

            // Reassign max_bid_price, delete if total_vol == 0
            if(vector::is_empty(&max_bid_price_level.orders)){
                let OO {total_volume:_, orders} = cb::pop(bids_tree, max_bid_price);
                vector::destroy_empty(orders);
                max_bid_price = cb::max_key(bids_tree);
            };
        };

        // Call fill orders
        fill_orders(bids_to_fill, asks_to_fill, price);
    }


    fun fill_orders(bids: vector<Bid>, asks: vector<Ask>, price: u64) {
        // Define a variable to store all NFTs from a vector

        // While loop thru the asks to get all the NFTs

        let nft = vector::pop_back(&mut asks);


        // While loop thru the bids to give the ask-er the $$, and xfer the NFT to bidder

        // Check if 0 balance in NFT
    }

    */
    // Ask:{ price=100, Nft:{balance:1000}}
    // new bid at 100 for 50 nft
    // fun will take 50 nft from the ask
    // 50 nft sent to bidder
    //


    // public entry fun cancel_ask(clob: &mut CLOB, order_id: ID){
    //     let oo_asks = &mut clob.asks;
    //     let order_info = table::borrow_mut(&mut clob.registry, order_id);
    //     // TODO orderinfo owner must be equal to sender to cancel
    //
    //     let price_level = cb::borrow_mut(oo_asks,order_info.price);
    //
    //     let i = 0;
    //     while(i < vector::length(&price_level.orders)){
    //         let current_ask = vector::borrow(&price_level.orders, i);
    //         if(object::uid_to_inner(&current_ask.id) == order_id){
    //             break;
    //         };
    //         i = i + 1;
    //     };
    //
    //     let Ask{ id, seller, price:_, nft} = vector::remove(&mut price_level.orders, i);
    //     order_info.status = S_CANCELLED;
    //
    //
    //
    //     // TODO emit event
    // }
}