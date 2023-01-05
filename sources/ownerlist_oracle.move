module crowd9_sc::ownerlist_oracle {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::transfer::{freeze_object};

    /// ======= Constants =======
    // Error Codes
    const EGovRecordDoesNotExist:u64 = 1;
    const EAuthenticationFailed:u64 = 2;

    struct OwnerList has key{
        id:UID,
        project_id: ID,
        owners: Table<address, u64>, // owner_address to number of nft (total voting power) owned
        index: u64,
        next: ID
    }

    struct AuthorityCap has key, store{
        id: UID,
        next_id: Option<UID>,
        next_index: u64,
        project_id: ID,
    }

    struct CapabilityBook has key{
        id: UID,
        book: Table<ID, ID> //project_id to cap_id
    }

    // === Getters ===
    public fun get_ownerlist(t: &OwnerList): &Table<address, u64>{
        &t.owners
    }

    // === For maintainer ===
    fun init(ctx: &mut TxContext) {
        let cap_book = CapabilityBook{id: object::new(ctx), book: table::new(ctx)};
        transfer::share_object(cap_book);
    }

    public fun add_to_capbook(project_id: ID, cap_book: &mut CapabilityBook, ctx: &mut TxContext){   
        let authority_cap = AuthorityCap { 
                id: object::new(ctx),
                next_id: option::some(object::new(ctx)),
                next_index: 0,
                project_id: project_id,
        };
        table::add(&mut cap_book.book, project_id, object::id(&authority_cap));
        transfer::transfer(authority_cap, tx_context::sender(ctx));
    }

    fun update_ownerlist(_: &mut AuthorityCap, cap_book: &mut CapabilityBook, owner_list: Table<address, u64>, ctx: &mut TxContext){
        let project_id = _.project_id;        
        assert!(table::contains(&cap_book.book, project_id), EGovRecordDoesNotExist);
        let cap_id = table::borrow(&cap_book.book, project_id);
        assert!(cap_id == &object::id(_), EAuthenticationFailed);

        let next_uid = object::new(ctx);
        let next_id = object::uid_to_inner(&next_uid);
        let id = option::swap(&mut _.next_id, next_uid);

        freeze_object(OwnerList{id, project_id, owners: owner_list, index: _.next_index, next: next_id});
        _.next_index = _.next_index + 1;
    }
}