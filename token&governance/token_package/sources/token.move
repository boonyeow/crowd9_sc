module token_package::token {
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};

    struct Card has key, store{
        id: UID,
    }

    struct Collection<phantom T> {
        uid: UID, //collection id
        name: vector<u8>, //str
        description: vector<u64>, // str
        current_supply: u32,
        funding_goal: u32,
        creator: address, //msg.sender -> whoever first called to create
        balance: Coin<SUI>,
        price: u32,
        status: vector<u8>,
        capability: UID, //capability.id, data type unsure
        start_timestamp: u32,
        duration: u32,
        owners: vector<Owner>,
    }
    struct Owner {
        id: UID,
        owner_address: address,
        owned_certificates: vector<address>
    }

    struct NftCertificate<phantom T> has key,store {
        id: UID,
        data_id: ID,
        quantity: u32,
    }

    struct _capability has key {
        id: UID
    }

    struct AdminCap has key {
        id: UID
    }

    // create campaign
    fun create_campaign(
        _name: vector<u8>,
        _description: vector<u64>,
        _current_supply: u32,
        _funding_goal: u32,
        _creator: address,
        _price: u32,
        _status: vector<u8>,
        ctx: &mut TxContext,
        _start_timestamp: u32,
        _duration: u32,
    ){ //sort of like deploying a new contract
        let collection = Collection{
            uid:  object::new(ctx), //collection id
            name: vector<u8>, //str
            description: vector<u64>, // str
            current_supply: u32,
            funding_goal: u32,
            creator: address, //msg.sender -> whoever first called to create
            balance: Coin<SUI>,
            price: u32,
            status: vector<u8>,
            capability: object::new(ctx), //capability.id, data type unsure
            start_timestamp: u32,
            duration: u32,
            owners: vector::empty<Owner>
        };
        //user to specify the params for creating collection
        transfer::transfer(_capability{id:object::new(ctx)}, sender(ctx)); // person who create the campaign
        transfer::share_object(collection);
    }

    public entry fun mint_card(ctx: &mut TxContext){
        let nft = Card { id: object::new(ctx)};
        transfer::transfer(nft, tx_context::sender(ctx));
    }
}
