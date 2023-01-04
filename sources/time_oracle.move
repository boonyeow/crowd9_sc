module crowd9_sc::time_oracle {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};


    struct Timestamp has key{
        id: UID,
        unix_ms: u64,
        index: u64,
        next: ID
    }

    struct AuthorityCap has key, store{
        id: UID,
        next_id: Option<UID>,
        next_index: u64,
        last_unix_ms:u64,
        last_timestamp_id: Option<ID>,
    }

    public fun unix_ms(t: &Timestamp): u64 {
        t.unix_ms
    }

    public fun index(t: &Timestamp): u64 {
        t.index
    }

    public fun next_object(t: &Timestamp): ID {
        t.next
    }

    public fun last_timestamp_id(auth:&AuthorityCap): Option<ID> {
        auth.last_timestamp_id
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(AuthorityCap {
            id: object::new(ctx),
            next_id: option::some(object::new(ctx)),
            next_index: 0,
            last_unix_ms: 0,
            last_timestamp_id: option::none(),
        }, tx_context::sender(ctx));
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext){
        transfer::transfer(AuthorityCap {
            id: object::new(ctx),
            next_id: option::some(object::new(ctx)),
            next_index: 0,
            last_unix_ms: 0,
            last_timestamp_id: option::none()
        }, tx_context::sender(ctx));
    }

    public entry fun stamp(
        unix_ms_now: u64,
        auth: &mut AuthorityCap,
        ctx: &mut TxContext,
    ) {
        assert!(unix_ms_now > auth.last_unix_ms, 0);

        let next_uid = object::new(ctx);
        let next_id = object::uid_to_inner(&next_uid);
        let id = option::swap(&mut auth.next_id, next_uid);
        let _id = object::uid_to_inner(&id);

        transfer::freeze_object(Timestamp {
            id,
            unix_ms: unix_ms_now,
            index: auth.next_index,
            next: next_id,
        });

        auth.next_index = auth.next_index + 1;
        auth.last_unix_ms = unix_ms_now;

        _ = option::swap_or_fill(&mut auth.last_timestamp_id, _id);
    }
}
