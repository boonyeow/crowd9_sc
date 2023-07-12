module crowd9_sc::coin_manager {
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field;
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    friend crowd9_sc::campaign;

    struct CoinBag has key, store {
        id: UID,
        size: u64
    }

    struct Currency<phantom T> has store {
        treasury_cap: TreasuryCap<T>,
        metadata: CoinMetadata<T>
    }

    struct AdminCap has key {
        id: UID,
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        // TODO: add admin_cap in remove
        // transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(admin_cap);
        transfer::share_object(CoinBag { id: object::new(ctx), size: 0 });
    }

    public entry fun add<T>(coin_bag: &mut CoinBag, treasury_cap: TreasuryCap<T>, metadata: CoinMetadata<T>) {
        assert!(coin::total_supply(&treasury_cap) == 0, 0);
        dynamic_field::add(&mut coin_bag.id, coin_bag.size, Currency { treasury_cap, metadata });
        coin_bag.size = coin_bag.size + 1;
    }

    public(friend) fun remove<T>(coin_bag: &mut CoinBag): (TreasuryCap<T>, CoinMetadata<T>) {
        let currency: Currency<T> = dynamic_field::remove(&mut coin_bag.id, coin_bag.size - 1);
        coin_bag.size = coin_bag.size - 1;
        let Currency { treasury_cap, metadata } = currency;
        (treasury_cap, metadata)
    }
}