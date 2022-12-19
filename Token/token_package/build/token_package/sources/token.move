module token_package::token {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use std::vector;
    // use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    //Error Codes
    const EINSUFFICIENT_FUNDS:u64 = 0;

    struct TokenObj has key, store{
        id: UID,
        value: u64,
    }

    struct Collection has key{
        id: UID, //collection id
        name: vector<u8>, //str
        description: vector<u64>, // str
        current_supply: u32,
        funding_goal: u32,
        creator: address, //msg.sender -> whoever first called to create
        balance: Balance<SUI>,
        price: u32,
        status: vector<u8>,
        capability: u32, //capability.id, data type unsure
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

    struct Capability has key, store {
        id: UID
    }

    struct AdminCap has key {
        id: UID
    }

    // Executes once (same as constructor)
    fun init(ctx: &mut TxContext){
        transfer::transfer(AdminCap{id: object::new(ctx)}, tx_context::sender(ctx));
    }

    // create campaign
     fun create_campaign(
        _name: vector<u8>,
        _description: vector<u64>,
        _current_supply: u32,
        _funding_goal: u32,
        // _creator: address,
        _price: u32,
        _status: vector<u8>,
        ctx: &mut TxContext,
        _start_timestamp: u32,
        _duration: u32,
    ){ //sort of like deploying a new contract
        let capability = Capability{id: object::new(ctx)};
        transfer::transfer(capability, sender(ctx));
        let collection = Collection{
            id:  object::new(ctx), //collection id
            name:_name, //str
            description: _description, // str
            current_supply: _current_supply,
            funding_goal:_funding_goal,
            creator:  tx_context::sender(ctx), //msg.sender -> whoever first called to create
            balance: balance::zero<SUI>(),
            price: _price,
            status: _status,
            // capability: capability, // getting errors here if use the capability object
            capability: 1, //replace with a static value just for now
            start_timestamp: _start_timestamp,
            duration: _duration,
            owners: vector::empty<Owner>()
            };
        transfer::share_object(collection);

    }
    


    // public entry fun mint_card(ctx: &mut TxContext){
    //     let nft = TokenObj { id: object::new(ctx)};
    //     transfer::transfer(nft, tx_context::sender(ctx));
    // }
}
