module crowd9_sc::ob{
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self};
    use sui::sui::{SUI};
    use sui::object::{Self, ID, UID};
    // use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::crit_bit_u64::{Self as cb, CB};
    use crowd9_sc::nft::{Self, Nft, Project};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;

    const MAX_BID_DEFAULT: u64 = 0;
    const MIN_ASK_DEFAULT: u64 = 0xffffffffffffffff;

    struct Market has key, store{
        id: UID,
        data: Table<ID, ID>
    }

    struct CLOB has key, store{
        id: UID,
        asks: CB<OO<Ask>>,
        bids: CB<OO<Bid>>,
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
        nft: Nft
    }

    struct Bid has key, store{
        id: UID,
        buyer: address,
        price: u64,
        amount: u64, // nfts to buy
        offer: Balance<SUI> // balance.value = amount * price
    }

    entry fun init(ctx: &mut TxContext){
        transfer::share_object(Market{
            id: object::new(ctx),
            data: table::new(ctx)
        });
    }

    public(friend) entry fun create_ob(project_id: ID, market: &mut Market, ctx: &mut TxContext){
        let clob = CLOB { id: object::new(ctx), asks: cb::empty(), bids: cb::empty() };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    public entry fun create_ask(clob: &mut CLOB, project: Project, nft: Nft, price: u64, ctx: &mut TxContext){
        let seller = tx_context::sender(ctx);
        let oo_bids = &mut clob.bids;
        let to_fill = nft::nft_value(&nft);

        let bids_to_fill = vector::empty();
        // While there are open bids, loop over all of them
        while (cb::length(oo_bids) > 0) {
            let to_destroy_OO = false;
            let current_max_bid = cb::max_key(&clob.bids);
            // Check if current max bid offers an amount lower than asking price
            // OR
            // if asking amount is all filled
            if (current_max_bid < price || to_fill <= 0) {
                break;
            };

            let price_level = cb::borrow_mut(oo_bids, current_max_bid);

            while(vector::length(&price_level.orders) > 0){
                /*
                got 3 cases,
                first one is if total volume at price point A is < to_fill,
                second is if current level we dk where the shit at + EXACT match for to_fill
                (price point=80, bids be like 10 + 20 + 30 + 40, and ask is exactly 30)
                third is if total_volume > to_fill, then borrow mut
                (price point=80, bids be like 10 + 20 + 30 + 40, and ask is 31 or smth funny)
                */
                if(to_fill >= price_level.total_volume) {
                    vector::append(&mut bids_to_fill, price_level.orders);
                    to_fill = to_fill - price_level.total_volume;
                    to_destroy_OO = true;
                } else {
                    let current_bid = vector::borrow_mut(&mut price_level.orders, 0);
                    if(to_fill < current_bid.amount){
                        current_bid.amount = current_bid.amount - to_fill;
                        vector::push_back(&mut bids_to_fill, Bid{
                            id: object::new(ctx),
                            buyer: current_bid.buyer,
                            price: current_bid.price,
                            amount: to_fill,
                            offer: balance::split(&mut current_bid.offer, to_fill*current_bid.price)
                        });
                        price_level.total_volume = price_level.total_volume - to_fill;
                        to_fill = 0;
                        break;
                    } else {
                        let removed_bid = vector::remove(&mut price_level.orders, 0);
                        vector::push_back(&mut bids_to_fill, removed_bid);

                        price_level.total_volume = price_level.total_volume - removed_bid.amount;
                        to_fill = to_fill - removed_bid.amount;

                        if(to_fill == 0) {
                            break;
                        }
                    }
                }
            };

            if(to_destroy_OO){
                let OO {total_volume:_, orders }  = cb::pop( &mut clob.bids, current_max_bid);
                vector::destroy_empty(orders);
            }
        };

        if(!vector::is_empty(&bids_to_fill)){
            fill_bids(&mut project, bids_to_fill, &mut nft, seller, ctx);
        };

        // Proceed to create ask order if order not complete
        if(to_fill > 0){
            let id = object::new(ctx);
            let ask = Ask {  id, seller, price, nft};
            if(cb::has_key(&clob.asks, price)){
                let oo_asks = cb::borrow_mut(&mut clob.asks, price);
                oo_asks.total_volume = oo_asks.total_volume + nft::nft_value(&nft);
                vector::push_back(&mut oo_asks.orders, ask);
            } else {
                let oo_asks = OO {
                    total_volume: nft::nft_value(&nft),
                    orders: vector::singleton(ask)
                };
                cb::insert(&mut clob.asks, price, oo_asks);
            }
        }
    }

    fun fill_bids(project: &mut Project, bids: vector<Bid>, nft: &mut Nft, seller:address, ctx: &mut TxContext){
        let consolidated_balance = balance::zero();
        while(!vector::is_empty(&bids)){
            let Bid { id, buyer, price: _, amount, offer } = vector::pop_back(&mut bids);
            object::delete(id);

            balance::join(&mut consolidated_balance, offer);

            let nft_balance = nft::balance_mut(nft);
            let to_transfer = nft::take(project, nft_balance, amount, ctx);
            transfer::transfer(to_transfer, buyer);
        };

        let consolidated_value = balance::value(&consolidated_balance);
        transfer::transfer(coin::take(&mut consolidated_balance, consolidated_value, ctx),  seller)
    }

    public entry fun cancel_ask(clob: &mut CLOB, order_id: ID){
        let oo_asks = &mut clob.asks;
        // Upon creating an order, keep track of which price level it is at
        // Approach 1 -> keep track using user-owned object i.e. each user will keep track of all orders (bid, ask) created
        /*  orders:{ buy:{ order_id=1 : price=80 }, sell:{} }
         *  if order gets filled, user-owned object will no longer be accurate but does it matter?
         *  on frontend side, when we iterate over the object, if order_id is not inside OO -> we can safely assume its filled?
         *  this way we can have tx history as well
         *
         */
        // Approach 2 -> keep track using shared object
        /* ID->price = k=ID,v=price ; ID maps to price
         * orders: {buy:{ address1=xxxx: vector[ID->price, ID->price] }
         *
         */

    }
}