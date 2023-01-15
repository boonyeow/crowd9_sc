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
        asks: CB<vector<Ask>>,
        bids: CB<vector<Bid>>,
        orders: Table<address, Orders>,
    }

    struct Orders has copy, drop, store{
        asks: vector<ID>,
        bids: vector<ID>
    }

    struct Ask has store{
        seller: address,
        price: u64,
        nft: Nft
    }

    struct Bid has store{
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
        let clob = CLOB { id: object::new(ctx),
            asks: cb::empty(),
            bids: cb::empty(),
            orders: table::new(ctx),
        };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }

    public entry fun create_ask(clob: &mut CLOB, project: Project, nft: Nft, price: u64, ctx: &mut TxContext){
        let seller = tx_context::sender(ctx);
        let bids = &mut clob.bids;
        let to_fill = nft::nft_value(&nft);

        // TODO: keep track of bids/asks total_volume

        while(cb::length(&clob.bids) > 0 && cb::max_key(&clob.bids) > price){
            let current_max_bid = cb::max_key(&clob.bids);


            if(!(current_max_bid >= price && to_fill > 0)) {
                break;
            };

            let price_level = cb::borrow_mut(bids, current_max_bid);
            let consolidated_balance = balance::zero();

            // Iterate over bids at current price_level, FIFO
            while(vector::length(price_level) > 0){
                // TODO: Change to separate function
                let current_bid = vector::borrow_mut(price_level, 0);
                if(current_bid.amount > to_fill){
                    current_bid.amount = current_bid.amount - to_fill; // Update bid amount

                    balance::join(
                        &mut consolidated_balance,
                        balance::split(&mut current_bid.offer, (price*to_fill))
                    );
                    let nft_balance = nft::balance_mut(&mut nft);
                    nft::take(&mut project, nft_balance, to_fill, ctx);
                    to_fill = 0;
                    transfer::transfer(nft, current_bid.buyer);

                } else {
                    let removed_bid = vector::remove(price_level, 0);
                    to_fill = to_fill - removed_bid.amount;

                    balance::join(&mut consolidated_balance, removed_bid.offer);

                    if(to_fill == 0){
                        // Ask order completely filled
                        transfer::transfer(nft, removed_bid.buyer);
                        break;
                    } ;

                    let nft_balance = nft::balance_mut(&mut nft);
                    let to_transfer = nft::take(&mut project, nft_balance, removed_bid.amount, ctx);
                    transfer::transfer(to_transfer, current_bid.buyer);
                }
            };

            if(vector::is_empty(price_level)){
                cb::pop(&mut clob.bids, price); // remove price_level from cb
                // let next_max_bid = cb::max_key(&clob.bids);
                let ask = Ask { seller, price, nft};
                cb::insert(&mut clob.asks, price, vector::singleton(ask)); // create new ask
            };

            let value_to_transfer = balance::value(&consolidated_balance);
            if(value_to_transfer > 0){
                transfer::transfer(
                    coin::take(&mut consolidated_balance, value_to_transfer, ctx),
                    seller
                );
            };
        };

        // Order not completely filled even after executing bid orders
        if(to_fill > 0){
            let ask = Ask { seller, price, nft};
            if(cb::has_key(&clob.asks, price)){
                let price_level = cb::borrow_mut(&mut clob.asks, price);
                vector::push_back(price_level, ask);
            } else {
                cb::insert(&mut clob.asks, price, vector::singleton(ask));
            }
        }
    }
}