module crowd9_sc::ino{
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    // use sui::coin::{Self, Coin};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    // use std::debug;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{VecSet};
    use sui::url::{Self, Url};
    // use crowd9_sc::errors::{};

    /// ======= Constants =======
    // Error Codes
    const EInsufficientFunds: u64 = 0000;
    const EUnauthorizedUser: u64 = 0001;
    const EDisallowedAction: u64 = 0002;

    // Status Codes
    const SInactive:u8 = 0;
    const SActive:u8 = 1;
    const SSucceeded:u8 = 2;
    const SFailed:u8 = 3;
    const SCancelled:u8 = 4;

    struct OwnerCap has key {
        id : UID
    }

    struct Campaign has key, store{
        id: UID,
        status: u8,
        funding_goal: u64,
        price_per_nft: u64,
        start_timestamp: u64,
        duration: u64,
        proposed_tap_rate: u64,
        balance: Balance<SUI>,
        contributors: vector<address>,
        contributors_data: Table<address, u64>,
        project_metadata: ProjectMetadata,
        owner_cap_id: ID,
    }

    struct ProjectMetadata has store{
        name: vector<u8>,
        description: Url,
        creator: address,
        current_supply: u64,
    }

    struct Project has key, store{
        id: UID,
        nft_ids: VecSet<ID>,
        last_withdrawn_timestamp: u64,
        tap_rate: u64,
        balance: Balance<SUI>,
        metadata: ProjectMetadata,
        owner_cap_id: ID
    }

    /// ======= Events =======
    struct CampaignCreated has copy, drop{
        campaign_id: ID,
        campaign_name: vector<u8>,
        creator: address,
    }

    struct CampaignStarted has copy, drop{
        campaign_id: ID,
        campaign_name: vector<u8>,
        creator: address,
        start_timestamp: u64,
        end_timestamp: u64,
    }

    struct CampaignSuccessful has copy, drop{
        campaign_id: ID,
        campaign_name: vector<u8>,
        creator: address,
        funding_goal: u64,
        funding_balance: u64,
    }

    struct CampaignFailed has copy, drop{
        campaign_id: ID,
        campaign_name: vector<u8>,
        creator: address,
        funding_goal: u64,
        funding_balance: u64,
    }

    public fun create_campaign(
        name: vector<u8>,
        description: vector<u8>,
        funding_goal: u64,
        price_per_nft: u64,
        duration: u64,
        proposed_tap_rate: u64,
        ctx: &mut TxContext): ID{
        let creator = tx_context::sender(ctx);
        let owner_cap = OwnerCap { id: object::new(ctx) };
        let metadata = ProjectMetadata { name, description: url::new_unsafe_from_bytes(description), creator, current_supply: 0};

        let campaign = Campaign{
            id: object::new(ctx),
            status: SInactive,
            funding_goal,
            price_per_nft,
            start_timestamp:0, // to update timestamp later
            duration,
            proposed_tap_rate,
            balance: balance::zero<SUI>(),
            contributors: vector::empty(),
            contributors_data: table::new(ctx),
            project_metadata: metadata,
            owner_cap_id: object::id(&owner_cap),
        };

        let campaign_id = object::id(&campaign);
        // TODO emit event
        event::emit(CampaignCreated{
            campaign_id,
            campaign_name: name,
            creator,
        });

        transfer::share_object(campaign);
        transfer::transfer(owner_cap, creator);
        campaign_id
    }

    public fun start_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, ctx: &mut TxContext) {
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SInactive, EDisallowedAction);

        campaign.status = SActive;
        // TODO update timestamp once released
        campaign.start_timestamp = tx_context::epoch(ctx);

        // TODO emit event
        let campaign_id = object::id(campaign);
        event::emit(CampaignStarted{
            campaign_id,
            campaign_name: campaign.project_metadata.name,
            creator: campaign.project_metadata.creator,
            start_timestamp: campaign.start_timestamp,
            end_timestamp: campaign.start_timestamp + campaign.duration,
        });

    }

    public fun cancel_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, _ctx: &mut TxContext){
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SActive || campaign.status == SInactive, EDisallowedAction);
        campaign.status = SCancelled;
    }

    // public fun end_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, _ctx: &mut TxContext) {
    //     assert!(object::id(owner_cap) == campaign.owner_cap_id, errors::unauthorized_user());
    //     assert!(campaign.status == SActive, errors::disallowed_action());
    //     let campaign_id = object::id(campaign);
    //     let campaign_balance = balance::value(&campaign.balance);
    //     if(campaign_balance < campaign.funding_goal){
    //         campaign.status = SFailed;
    //         event::emit(CampaignFailed{
    //             campaign_id,
    //             campaign_name: campaign.project_metadata.name,
    //             creator: campaign.project_metadata.creator,
    //             funding_goal: campaign.funding_goal,
    //             funding_balance: campaign_balance,
    //         });
    //     }
    //     else{
    //         campaign.status = SSucceeded;
    //         event::emit(CampaignSuccessful{
    //             campaign_id,
    //             campaign_name: campaign.project_metadata.name,
    //             creator: campaign.project_metadata.creator,
    //             funding_goal: campaign.funding_goal,
    //             funding_balance: campaign_balance,
    //         });
    //     }
    // }


}