module crowd9_sc::ob{
    use sui::table::{Self, Table};
    use sui::balance::{/*Self,*/ Balance};
    // use sui::coin::{Self};
    use sui::sui::{SUI};
    use sui::object::{Self, ID, UID};
    // use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::crit_bit_u64::{Self as cb, CB};
    // use crowd9_sc::ino::{Self, Project};
    use crowd9_sc::nft::{/*Self,*/ Nft};
    use sui::tx_context::{/*Self,*/ TxContext};
    use sui::transfer;
    // use std::vector;

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
        maxBid: u64,
        minAsk: u64,
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
        size: u64,
        offer: Balance<SUI>
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
            maxBid: MAX_BID_DEFAULT,
            minAsk: MIN_ASK_DEFAULT
        };

        table::add(&mut market.data, project_id, object::id(&clob));
        transfer::share_object(clob);
    }
}