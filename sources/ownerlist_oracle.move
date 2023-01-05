module crowd9_sc::ownerlist_oracle {
    // use crowd9_sc::ino::{Self, AuthorityCap};
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::table::{Self, Table};
    // use sui::transfer::{transfer, freeze_object};

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

    public fun add_to_capbook(project_id: ID, cap_id: ID, cap_book: &mut CapabilityBook){   
        table::add(&mut cap_book.book, project_id, cap_id);
    }

    // fun update_ownerlist(cap_book: &mut CapabilityBook, owner_list: Table<address, u64>, cap: AuthorityCap, ctx: &mut TxContext){
    //     let project_id = cap.project_id;
    //     assert!(table::contains(&cap_book.book, project_id), EGovRecordDoesNotExist);
    //     let book_cap = table::borrow(&cap_book.book, project_id);
    //     assert!(book_cap == object::id(cap), EAuthenticationFailed);

    //     let next_uid = object::new(ctx);
    //     let next_id = object::uid_to_inner(&next_uid);
    //     let id = option::swap(&mut cap.next_id, next_uid);

    //     freeze_object(OwnerList{id, project_id, owners: owner_list, index: cap.next_index, next: next_id});
    //     cap.next_index = cap.next_index + 1;
    // }
}