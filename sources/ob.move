module crowd9_sc::ob{
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, ID, UID};
    // use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::crit_bit_u64::{Self as cb, CB};
    use crowd9_sc::nft::{Self, Nft, Project};
    use crowd9_sc::linked_list::{Self, LinkedList};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;
    use std::option::{Self, Option};
    const MAX_BID_DEFAULT: u64 = 0;
    const MIN_ASK_DEFAULT: u64 = 0xffffffffffffffff;

    const EInsufficientAmountSupplied:u64 = 0;

    const S_CANCELLED:u8 = 0;
    const S_QUEUED:u8 = 1;
    const S_PARTIALLY_EXECUTED:u8 = 2;
    const S_EXECUTED:u8 = 3;

    const BUY_ORDER:u8 = 0;
    const SELL_ORDER:u8 = 1;

    struct Market has key, store{
        id: UID,
        data: Table<ID, ID>
    }

    struct CLOB has key, store{
        id: UID,
        asks: CB<OO<ID, Ask>>,
        bids: CB<OO<ID, Bid>>,
        registry: Table<ID, OrderInfo>
    }

    struct OO<K: copy + drop + store, V:store> has store{
        total_volume: u64,
        orders: LinkedList<K, V>
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

    public(friend) entry fun create_ob(project_id: ID, market: &mut Market, ctx: &mut TxContext){
        let clob = CLOB { id: object::new(ctx), asks: cb::empty(), bids: cb::empty(), registry: table::new(ctx) };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    fun add_to_oo<T: store>(oo: &mut OO<ID, T>, order: T, order_id: ID, amount: u64){
        oo.total_volume = oo.total_volume + amount;
        linked_list::push_back(&mut oo.orders, order_id, order);
    }

    fun remove_from_oo<T: store>(oo: &mut OO<ID, T>, order_id: ID, amount: u64): T{
        oo.total_volume = oo.total_volume - amount;
        linked_list::remove(&mut oo.orders, order_id)
    }

    public entry fun create_bid(clob: &mut CLOB, project: &mut Project, bid_offer: Coin<SUI>, amount:u64, price: u64, ctx: &mut TxContext){
        assert!(coin::value(&bid_offer) == price*amount, EInsufficientAmountSupplied);

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

        let (crossed_asks, remaining_amount) = {
            if(cb::is_empty(&clob.asks)){
                (vector::empty<Ask>(), amount)
            } else {
                // Asks found
                fetch_crossed_asks(&mut clob.asks, registry, project, price, amount, ctx)
            }
        };

        if(!vector::is_empty(&crossed_asks)){
            fulfill_asks(&mut crossed_asks, &mut bid, project, registry, ctx);
        };
        vector::destroy_empty(crossed_asks);

        bid.amount = remaining_amount;
        if(bid.amount > 0){
            let order_id = object::id(&bid);
            if(cb::has_key(bids_tree, price)){
                let price_level = cb::borrow_mut(bids_tree, price);
                add_to_oo(price_level, bid, order_id, amount);
            } else {
                let total_volume = *&bid.amount;
                let orders = linked_list::new(ctx);
                linked_list::push_back(&mut orders, order_id, bid);
                cb::insert(bids_tree, price, OO{ total_volume, orders });
            };
        } else {
            let Bid { id, buyer:_, price:_, amount:_, offer } = bid;
            let order_id = object::uid_to_inner(&id);
            object::delete(id);
            let offer_value = balance::value(&offer);
            if(offer_value > 0){
                // Transfer back to buyer because order was filled at a better price
                transfer::transfer(coin::take(&mut offer, offer_value, ctx), buyer);
            };
            balance::destroy_zero(offer);
            let order_info = table::borrow_mut(registry, order_id);
            order_info.status = S_EXECUTED;
        };
    }

    fun fetch_crossed_asks(asks_tree: &mut CB<OO<ID, Ask>>, registry: &mut Table<ID,OrderInfo>, project: &mut Project, bid_price: u64, bid_amount: u64, ctx: &mut TxContext): (vector<Ask>, u64){
        let min_ask = cb::min_key(asks_tree);
        let asks_to_fill = vector::empty<Ask>();
        let asks_tree_empty = cb::is_empty(asks_tree);

        while(bid_price >= min_ask && bid_amount > 0){
            let price_level = cb::borrow_mut(asks_tree, min_ask);
            while(bid_amount != 0){
                let order_id = option::destroy_some(linked_list::first(&price_level.orders));
                let current_ask = linked_list::borrow_mut<ID, Ask>(&mut price_level.orders, order_id);
                if(bid_amount >= current_ask.amount){
                    let removed_ask = remove_from_oo(price_level, order_id, current_ask.amount);
                    bid_amount = bid_amount - removed_ask.amount;
                    vector::push_back(&mut asks_to_fill, removed_ask);
                } else {
                    let split_ask = Ask {
                        id: object::new(ctx),
                        seller: current_ask.seller,
                        price: current_ask.price,
                        amount: bid_amount,
                        nft: nft::take(project, nft::balance_mut(&mut current_ask.nft), bid_amount, ctx)
                    };
                    table::add(registry, object::id(&split_ask),
                        OrderInfo{
                            parent: option::none(),
                            owner: split_ask.seller,
                            price: split_ask.price,
                            status: S_QUEUED
                        }
                    );

                    current_ask.amount = current_ask.amount - bid_amount;
                    price_level.total_volume = price_level.total_volume - bid_amount;
                    vector::push_back(&mut asks_to_fill, split_ask);
                    bid_amount = 0;
                };

                if(linked_list::length(&price_level.orders) == 0){
                    let OO { total_volume:_, orders} = cb::pop(asks_tree, min_ask);
                    linked_list::destroy_empty(orders);
                    asks_tree_empty = cb::is_empty(asks_tree);
                    if (!asks_tree_empty) {
                        min_ask = cb::min_key(asks_tree);
                    };
                    break
                }
            };
            if (asks_tree_empty){
                break
            }
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

    public entry fun create_ask(clob: &mut CLOB, project: &mut Project, nft: Nft, amount:u64, price:u64, ctx: &mut TxContext){
        let asks_tree = &mut clob.asks;
        let registry = &mut clob.registry;
        let seller = tx_context::sender(ctx);

        let nft_value = nft::nft_value(&nft);
        assert!(nft_value >= amount, 0);

        if(nft_value > amount){
            let nft_balance = nft::balance_mut(&mut nft);
            let value_to_transfer = nft_value - amount;
            transfer::transfer(
                nft::take(project, nft_balance, value_to_transfer, ctx),
                seller);
        };

        let ask = Ask { id: object::new(ctx), seller, price, amount, nft };
        table::add(registry, object::id(&ask), OrderInfo{
            parent: option::none(), // might not need anymore / check if we need to add this in during split
            owner: seller,
            price,
            status: S_QUEUED,
        });

        let (crossed_bids, remaining_amount) = {
            if(cb::is_empty(&clob.bids)){
                (vector::empty(), amount)
            } else {
                fetch_crossed_bids(&mut clob.bids, registry, price, amount, ctx)
            }
        };

        if(!vector::is_empty(&crossed_bids)){
            fulfill_bids(&mut crossed_bids, &mut ask, project, registry, ctx);
        };
        vector::destroy_empty(crossed_bids);

        ask.amount = remaining_amount;
        if(ask.amount > 0){
            let order_id = object::id(&ask);
            if(cb::has_key(asks_tree, price)){
                let price_level = cb::borrow_mut(asks_tree, price);
                add_to_oo(price_level, ask, order_id, amount);
            } else {
                let total_volume = *&ask.amount;
                let orders = linked_list::new(ctx);
                linked_list::push_back(&mut orders, order_id, ask);
                cb::insert(asks_tree, price, OO{ total_volume, orders });
            }
        } else {
            let Ask { id, seller:_, price:_, amount:_, nft} = ask;
            let order_id = object::uid_to_inner(&id);
            object::delete(id);
            nft::destroy_zero(project, nft);

            let order_info = table::borrow_mut(registry, order_id);
            order_info.status = S_EXECUTED;
        }
    }

    fun fetch_crossed_bids(bids_tree: &mut CB<OO<ID, Bid>>, registry: &mut Table<ID, OrderInfo>, ask_price: u64, ask_amount:u64, ctx: &mut TxContext): (vector<Bid>, u64){
        let max_bid = cb::max_key(bids_tree);
        let bids_to_fill = vector::empty();
        let bids_tree_empty = cb::is_empty(bids_tree);

        while(ask_price <= max_bid && ask_amount > 0){
            let price_level = cb::borrow_mut(bids_tree, max_bid);
            while(ask_amount != 0){
                let order_id = option::destroy_some(linked_list::first(&price_level.orders));
                let current_bid = linked_list::borrow_mut<ID, Bid>(&mut price_level.orders, order_id);
                if(ask_amount >= current_bid.amount){
                    let removed_bid = remove_from_oo(price_level, order_id, current_bid.amount);
                    ask_amount = ask_amount - removed_bid.amount;
                    vector::push_back(&mut bids_to_fill, removed_bid);
                } else {
                    current_bid.amount = current_bid.amount - ask_amount;
                    let split_bid = Bid{
                        id: object::new(ctx),
                        buyer: current_bid.buyer,
                        price: current_bid.price,
                        amount: ask_amount,
                        offer: coin::into_balance(coin::take(&mut current_bid.offer, ask_amount*current_bid.price, ctx))
                    };

                    table::add(registry, object::id(&split_bid),
                        OrderInfo{
                            parent: option::none(),
                            owner: split_bid.buyer,
                            price: split_bid.price,
                            status: S_QUEUED
                        }
                    );

                    price_level.total_volume = price_level.total_volume - ask_amount;
                    vector::push_back(&mut bids_to_fill, split_bid);
                    ask_amount = 0;
                };

                if(linked_list::length(&price_level.orders) == 0){
                    let OO { total_volume:_, orders} = cb::pop(bids_tree, max_bid);
                    linked_list::destroy_empty(orders);
                    bids_tree_empty = cb::is_empty(bids_tree);
                    if (!bids_tree_empty) {
                        max_bid = cb::max_key(bids_tree);
                    };
                    break
                }
            };
            if (bids_tree_empty){
                break
            }
        };
        (bids_to_fill, ask_amount)
    }

    fun fulfill_bids(bids: &mut vector<Bid>, ask: &mut Ask, project:&mut Project, registry: &mut Table<ID, OrderInfo>, ctx: &mut TxContext){
        let consolidated_balance = balance::zero();
        while(!vector::is_empty(bids)){
            let Bid {id, buyer, price:_, amount, offer} = vector::pop_back(bids);
            let order_id = object::uid_to_inner(&id);
            table::borrow_mut(registry, order_id).status = S_EXECUTED;

            object::delete(id);
            transfer::transfer(nft::take(project, nft::balance_mut(&mut ask.nft), amount, ctx),buyer);
            balance::join(&mut consolidated_balance, offer);
        };
        transfer::transfer(coin::from_balance(consolidated_balance, ctx), ask.seller);
    }

    // Ask:{ price=100, Nft:{balance:1000}}
    // new bid at 100 for 50 nft
    // fun will take 50 nft from the ask
    // 50 nft sent to bidder
    //

    public entry fun cancel_bid(clob: &mut CLOB, order_id: ID, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let oo_bids = &mut clob.bids;
        let order_info = table::borrow_mut<ID, OrderInfo>(&mut clob.registry, order_id);
        assert!(order_info.owner == sender, 0); // TODO error code later
        assert!(order_info.status != S_CANCELLED && order_info.status != S_EXECUTED, 0); // TODO error code later

        let price_level = cb::borrow_mut(oo_bids,order_info.price);
        let orders = &mut price_level.orders;
        let Bid { id, buyer, price:_, amount:_, offer} = linked_list::remove(orders, order_id);
        object::delete(id);

        order_info.status = S_CANCELLED;


        transfer::transfer(coin::from_balance(offer, ctx), buyer); // return coins to user
        // TODO emit event
    }
    public entry fun cancel_ask(clob: &mut CLOB, order_id: ID, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let oo_asks = &mut clob.asks;
        let order_info = table::borrow_mut<ID, OrderInfo>(&mut clob.registry, order_id);
        assert!(order_info.owner == sender, 0); // TODO error code later
        assert!(order_info.status != S_CANCELLED && order_info.status != S_EXECUTED, 0); // TODO error code later

        let price_level = cb::borrow_mut(oo_asks,order_info.price);
        let orders = &mut price_level.orders;
        let Ask { id, seller, price:_, amount:_, nft} = linked_list::remove(orders, order_id);
        object::delete(id);

        order_info.status = S_CANCELLED;

        transfer::transfer(nft, seller); // return nft to user
        // TODO emit event
    }

    #[test_only]
    public entry fun init_test(ctx: &mut TxContext){
        transfer::share_object(Market{
            id: object::new(ctx),
            data: table::new(ctx)
        });
    }

    #[test_only]
    public entry fun create_ob_test(project_id: ID, market: &mut Market, ctx: &mut TxContext){
        let clob = CLOB { id: object::new(ctx), asks: cb::empty(), bids: cb::empty(), registry: table::new(ctx) };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    #[test_only]
    public fun get_asks_tree(clob: &CLOB): &CB<OO<ID, Ask>>{
        &clob.asks
    }

    #[test_only]
    public fun get_bids_tree(clob: &CLOB): &CB<OO<ID, Bid>>{
        &clob.bids
    }

    #[test_only]
    public fun get_OO<T: store>(orders_tree: &CB<OO<ID, T>>, price: u64): (u64,&LinkedList<ID, T>){
        let open_orders: &OO<ID, T>  = cb::borrow(orders_tree, price);
        (open_orders.total_volume, &open_orders.orders)
    }

    #[test_only]
    public fun get_bid_volume(bids: &LinkedList<ID, Bid>): u64{
        let volume = 0;
        let prev_node = &linked_list::first(bids);
        let nodes = linked_list::get_nodes(bids);

        while(option::is_some(prev_node)){
            let current_ID = *option::borrow<ID>(prev_node);
            let current_node = table::borrow(nodes, current_ID);
            let bid = linked_list::get_node_value<ID, Bid>(current_node);
            volume = volume + bid.amount;

            prev_node = &linked_list::get_next_node<ID, Bid>(current_node);
        };
        volume
    }

    #[test_only]
    public fun get_ask_volume(asks: &LinkedList<ID, Ask>): u64{
        let volume = 0;
        let prev_node = &linked_list::first(asks);
        let nodes = linked_list::get_nodes(asks);

        while(option::is_some(prev_node)){
            let current_ID = *option::borrow<ID>(prev_node);
            let current_node = table::borrow(nodes, current_ID);
            let ask = linked_list::get_node_value<ID, Ask>(current_node);
            volume = volume + ask.amount;

            prev_node = &linked_list::get_next_node<ID, Ask>(current_node);
        };
        volume
    }
}