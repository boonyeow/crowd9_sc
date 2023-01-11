module crowd9_sc::ownerlist_oracle {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use crowd9_sc::dict::{Self, Dict};

    /// ======= Constants =======
    // Error Codes
    const EGovRecordDoesNotExist:u64 = 1;
    const EUnauthorizedUser:u64 = 2;
    const EOwnerRecordDoesNotExist:u64 = 3;
    const EQuantityRemovedIncorrect:u64 = 4;
    const EGovRecordAlreadyExist:u64 = 1;


    struct AdminCap has key {
        id : UID
    }

    struct OwnerList has key{
        id:UID,
        governance_id: ID,
        owners: Dict<address, u64>, // owner_address to number of nft (total voting power) owned
        index: u64,
    }

    // each governance will hv its own authoritycap
    struct AuthorityCap has key, store{
        id: UID,
        governance_id: ID,
    }

    struct CapabilityBook has key{
        id: UID,
        book: Dict<ID, ID>, //governance_id to authority_id
        admin_cap: ID, 
    }

    // === Getters ===
    public fun get_ownerlist(t: &OwnerList): &Dict<address, u64>{
        &t.owners
    }

    // === For maintainer ===
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap{id: object::new(ctx)};
        let cap_book = CapabilityBook{id: object::new(ctx), book: dict::new(ctx), admin_cap: object::id(&admin_cap)};
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(cap_book);
    }

    // only admin can run this
    // this is run upon emit of the creation of a new governance for a campaign
    public entry fun add_to_capbook(admin_cap: &AdminCap, governance_id: ID, cap_book: &mut CapabilityBook, owner_table: Dict<address, u64>, ctx: &mut TxContext){  
        assert!(object::id(admin_cap) == cap_book.admin_cap, EUnauthorizedUser);
        assert!(!dict::contains(&cap_book.book, governance_id), EGovRecordAlreadyExist);

        let authority_cap = AuthorityCap { 
                id: object::new(ctx),
                governance_id,
        };
        
        let owner_list = OwnerList {
            id: object::new(ctx),
            governance_id,
            owners: owner_table,
            index: 0,
        };
        dict::add(&mut cap_book.book, governance_id, object::id(&authority_cap));
        transfer::transfer(authority_cap, tx_context::sender(ctx));
        transfer::share_object(owner_list);
    }

    // only admin can run this
    // event listner --> to watch for transfer events, upon detect transfer event, this function will be called to update the owner_list
    public entry fun update_ownerlist(authority_cap: &mut AuthorityCap, owner_list: &mut OwnerList, cap_book: &mut CapabilityBook, from: address, to: address, quantity: u64){
        let governance_id = authority_cap.governance_id;        
        assert!(dict::contains(&cap_book.book, governance_id), EGovRecordDoesNotExist);
        let cap_id = dict::borrow(&cap_book.book, governance_id);
        assert!(cap_id == &object::id(authority_cap), EUnauthorizedUser);
        assert!(dict::contains(&owner_list.owners, from), EOwnerRecordDoesNotExist);
        let from_quantity = *dict::borrow(&owner_list.owners, from);

        if(from_quantity - quantity == 0) {
            assert!(dict::remove(&mut owner_list.owners, from) == from_quantity, EQuantityRemovedIncorrect);
        } 
        else{
            *dict::borrow_mut(&mut owner_list.owners, from) = from_quantity - quantity;
        };

        if(dict::contains(&owner_list.owners, to)){
            let to_quantity = *dict::borrow(&owner_list.owners, to);
            *dict::borrow_mut(&mut owner_list.owners, to) = to_quantity + quantity;
        } 
        else{
            dict::add(&mut owner_list.owners, to, quantity);
        };

        owner_list.index = owner_list.index + 1;
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun get_capbook(capbook: &CapabilityBook): &Dict<ID, ID>{
        &capbook.book
    }

    #[test_only]
    public fun get_owners(ownerlist: &OwnerList): &Dict<address, u64>{
        &ownerlist.owners
    }
}