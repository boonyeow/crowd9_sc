module token_package::token {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::debug;
    use sui::event;

    //Error Codes
    const EINSUFFICIENT_FUNDS:u64 = 0;

    struct TokenObj has key, store{
        id: UID,
        value: u64,
    }

    struct NftCollection<T1> has key{
        id: UID, //collection id, with ID within UID to represent capability
        name: vector<u8>, //str
        description: vector<T1>, // str
        current_supply: u32,
        funding_goal: u32,
        creator: address, //msg.sender -> whoever first called to create
        balance: Balance<SUI>,
        price: u32,
        capability: ID,
        status: vector<u8>,
        start_timestamp: u64,
        duration: u64,
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

    struct CampaignStartedEvent has copy, drop {
        collection_id: ID,
        start_timestamp: u64,
        end_timestamp: u64,
    }

    // Executes once (same as constructor)
    fun init(ctx: &mut TxContext){
        transfer::transfer(AdminCap{id: object::new(ctx)}, tx_context::sender(ctx));
    }

    // create campaign
    fun create_campaign<T1: store>( 
        _name: vector<u8>,
        _description: T1,
        _funding_goal: u32,
        _price: u32,
        ctx: &mut TxContext,
        _duration: u64,
    ){  
        let owner_cap = Capability{id: object::new(ctx)};
        let desc = vector::empty<T1>();
        vector::push_back(&mut desc, _description);
        let collection = NftCollection{
            id:  object::new(ctx), //collection uid
            name:_name, //str
            description: desc, // str
            current_supply: 0,
            funding_goal:_funding_goal,
            creator:  tx_context::sender(ctx), //msg.sender -> whoever first called to create
            balance: balance::zero<SUI>(),
            price: _price,
            capability: object::id(&owner_cap),
            status: b"Inactive",
            start_timestamp: 0000000000,
            duration: _duration,
            owners: vector::empty<Owner>()
            };
        debug::print(&collection.capability);
        debug::print(&owner_cap.id);
        transfer::share_object(collection);
        transfer::transfer(owner_cap, tx_context::sender(ctx));
    }

    fun start_campaign(collection: &mut NftCollection<vector<u8>>, capability: ID ,ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == collection.creator, 1);
        assert!(capability == collection.capability, 1);
        assert!(collection.status == b"Inactive", 1);
        collection.status = b"Active";
        collection.start_timestamp = tx_context::epoch(ctx);
        event::emit(
            CampaignStartedEvent{
                collection_id: object::id(collection),
                start_timestamp: collection.start_timestamp,
                end_timestamp: collection.start_timestamp + collection.duration,
            }
        );
    }

    #[test]
    public fun test_and_edit_campaign() {
        // use sui::tx_context;
        // use sui::transfer;
        use sui::test_scenario;

        // create test addresses representing users
        let admin = @0xBABE;
        let creator = @0xCAFE;

        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };

        // second transaction
        test_scenario::next_tx(scenario, creator);
        let campaign_id = {
            let ctx = test_scenario::ctx(scenario);
            create_campaign(
            b"The One",
            b"Description",
            1000,
            10,
            ctx,
            20,
            );
            object::id_from_address(tx_context::last_created_object_id(ctx))
            // debug::print(&tx_context::last_created_object_id(ctx));
        };
        // third transaction
        test_scenario::next_tx(scenario, creator); 
        let camapign_obj:NftCollection<vector<u8>> = test_scenario::take_shared_by_id(scenario, campaign_id);
        debug::print(&camapign_obj);
        assert!(camapign_obj.name == b"The One" && camapign_obj.funding_goal == 1000 && camapign_obj.price == 10 && camapign_obj.duration == 20 && camapign_obj.status == b"Inactive", 1);

        // fourth transaction
        test_scenario::next_tx(scenario, creator);
        {   
            let cap = test_scenario::take_from_sender<Capability>(scenario);
            let cap_id = object::id(&cap);
            debug::print(&cap_id);
            let ctx = test_scenario::ctx(scenario);
            start_campaign(&mut camapign_obj, cap_id, ctx);
            // debug::print(&camapign_obj);
            test_scenario::return_to_sender(scenario, cap)
        };
        
        // fifth transaction
        test_scenario::next_tx(scenario, creator);
        debug::print(&camapign_obj);
        assert!(camapign_obj.status == b"Active", 1);



        test_scenario::return_shared(camapign_obj);
        test_scenario::end(scenario_val);
        }
   

    // public entry fun mint_card(ctx: &mut TxContext){
    //     let nft = TokenObj { id: object::new(ctx)};
    //     transfer::transfer(nft, tx_context::sender(ctx));
    // }
}