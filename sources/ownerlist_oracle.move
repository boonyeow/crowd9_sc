module crowd9_sc::ownerlist_oracle {
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::table::{Self, Table};
    // use std::option::{Self, Option};
    // use sui::transfer::{transfer, freeze_object};

    /// ======= Constants =======
    // Error Codes
    const EGovRecordDoesNotExist:u64 = 1;
    const EAuthenticationFailed:u64 = 2;

    struct OwnerList has key{
        id:UID,
        governance: ID,
        owners: Table<address, u64>, // owner_address to number of nft (total voting power) owned
        index: u64,
        next: ID
    }

    struct CapabilityBook has key{
        id: UID,
        book: Table<ID, ID> //gov_id to cap_id
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

    public fun add_to_capbook(governance_id: ID, cap_id: ID, cap_book: &mut CapabilityBook){   
        table::add(&mut cap_book.book, governance_id, cap_id);
    }

    // fun update_ownerlist( _cap_book: &mut CapabilityBook, _owners: vector<address>, _cap: GovernanceAdminCapability, ctx: &mut TxContext){
    //     let gov_id = _cap.governance_id;
    //     assert!(table::contains(&_cap_book.book, gov_id), EGovRecordDoesNotExist);
    //     let gov_admin_cap_id = table::borrow_mut(&mut _cap_book.book, gov_id);
    //     assert!(gov_admin_cap_id == object::id(_cap), EAuthenticationFailed);

    //     let next_uid = object::new(ctx);
    //     let next_id = object::uid_to_inner(&next_uid);
    //     let id = option::swap(&mut auth.next_id, next_uid);

    //     freeze_object(OwnerList{id, owners: _owners, index: auth.next_index, next: next_id,});
    //     auth.next_index = auth.next_index + 1;
    // }
}