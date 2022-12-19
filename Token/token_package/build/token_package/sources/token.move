module token_package::token {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::debug;

    //Error Codes
    const EINSUFFICIENT_FUNDS:u64 = 0;

    struct TokenObj has key, store{
        id: UID,
        value: u64,
    }

    struct Collection has key{
        id: UID, //collection id, with ID within UID to represent capability
        name: vector<u8>, //str
        description: vector<u64>, // str
        current_supply: u32,
        funding_goal: u32,
        creator: address, //msg.sender -> whoever first called to create
        balance: Balance<SUI>,
        price: u32,
        capability: ID,
        status: vector<u8>,
        start_timestamp: u32,
        duration: u32,
        owners: vector<Owner>,
    }
    struct Owner has key, store{
        id: UID,
        owner_address: address,
        owned_certificates: vector<address>
    }

    struct NftCertificate has key, store {
        id: UID,
        data_id: ID,
        quantity: u32,
    }

    struct Capability has key {
        id: UID,
    }

    struct AdminCap has key {
        id: UID,
    }

    // Executes once (same as constructor)
    fun init(ctx: &mut TxContext){
        transfer::transfer(AdminCap{id: object::new(ctx)}, tx_context::sender(ctx));
    }


    // create campaign
    fun create_campaign(
        _name: vector<u8>,
        _description: vector<u64>,
        _funding_goal: u32,
        _price: u32,
        ctx: &mut TxContext,
        _start_timestamp: u32,
        _duration: u32,
    ){ //sort of like deploying a new contract
        let owner_cap = Capability{id: object::new(ctx)};
        let collection = Collection{
            id:  object::new(ctx), //collection id
            name:_name, //str
            description: _description, // str
            current_supply: 0,
            funding_goal:_funding_goal,
            creator:  tx_context::sender(ctx), //msg.sender -> whoever first called to create
            balance: balance::zero<SUI>(),
            price: _price,
            capability: object::id(&owner_cap),
            status: b"Inactive",
            // capability: object::new(ctx),
            start_timestamp: _start_timestamp,
            duration: _duration,
            owners: vector::empty<Owner>()
            };
        debug::print(&collection.capability);
        debug::print(&owner_cap.id);
        transfer::share_object(collection);
        transfer::transfer(owner_cap, tx_context::sender(ctx));
    }

     #[test]
    public fun test_campaign() {
        // use sui::tx_context;
        // use sui::transfer;
        use sui::test_scenario;
        use std::vector;

        // create test addresses representing users
        let admin = @0xBABE;
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };
        // second transaction executed by admin to create the sword
        test_scenario::next_tx(scenario, admin);
        {
            create_campaign(
            b"The One",
            vector::empty<u64>(),
            1000,
            10,
            test_scenario::ctx(scenario),
            20,
            20,
            );
        };

        test_scenario::end(scenario_val);
    }

    // public entry fun mint_card(ctx: &mut TxContext){
    //     let nft = TokenObj { id: object::new(ctx)};
    //     transfer::transfer(nft, tx_context::sender(ctx));
    // }
}