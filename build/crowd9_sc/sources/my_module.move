module crowd9_sc::my_module {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Card has key, store{
        id: UID,
    }

    public entry fun mint_card(ctx: &mut TxContext){
        let nft = Card { id: object::new(ctx)};
        transfer::transfer(nft, tx_context::sender(ctx));
    }
}
