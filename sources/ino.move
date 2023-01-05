module crowd9_sc::ino{
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    // use std::debug;
    use sui::event;
    use sui::table::{Self, Table};
    // use sui::vec_set::{Self};
    use sui::url::{Self, Url};
    // use crowd9_sc::errors::{};

    /// ======= Constants =======
    // Error Codes
    const EIncorrectAmount: u64 = 0000;
    const EUnauthorizedUser: u64 = 0001;
    const EDisallowedAction: u64 = 0002;
    const ENoContributionFound: u64 = 0004;
    const ECampaignEnded: u64 = 0005;

    // Status Codes
    const SInactive:u8 = 0;
    const SActive:u8 = 1;
    const SSuccess:u8 = 2;
    const SFailure:u8 = 3;
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
        project_metadata: Option<ProjectMetadata>,
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
        nft_ids: vector<ID>,
        last_withdrawn_timestamp: u64,
        tap_rate: u64,
        balance: Balance<SUI>,
        metadata: ProjectMetadata,
        owner_cap_id: ID
    }

    struct Nft has key, store{
        id: UID,
        project_id: ID
    }

    struct Certificate has key{
        id: UID,
        campaign_id: ID,
        quantity: u64
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
            project_metadata: option::some(metadata),
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

        let metadata = option::borrow(&campaign.project_metadata);
        // TODO emit event
        let campaign_id = object::id(campaign);
        event::emit(CampaignStarted{
            campaign_id,
            campaign_name: metadata.name,
            creator: metadata.creator,
            start_timestamp: campaign.start_timestamp,
            end_timestamp: campaign.start_timestamp + campaign.duration,
        });
    }

    public fun cancel_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, _ctx: &mut TxContext){
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SActive, EDisallowedAction);
        campaign.status = SCancelled;
        // TODO emit cancel event
    }

    public fun end_campaign(campaign: &mut Campaign, ctx: &mut TxContext) {
        assert!(campaign.status == SActive, EDisallowedAction);

        let total_raised = balance::value(&campaign.balance);
        if(total_raised < campaign.funding_goal){
            campaign.status = SFailure;
            // TODO emit CampaignFailure
        }
        else{
            // TODO emit CampaignSuccess
            campaign.status = SSuccess;
            let nft_ids = vector::empty();
            let project_id = object::new(ctx);
            airdrop(campaign, &mut nft_ids, object::uid_to_inner(&project_id), ctx);

            let balance_value = balance::value(&campaign.balance);
            let balance = coin::into_balance(coin::take(&mut campaign.balance, balance_value, ctx));
            let metadata = option::extract(&mut campaign.project_metadata);

            let project = Project {
                id: project_id,
                nft_ids,
                last_withdrawn_timestamp: 0,
                tap_rate: campaign.proposed_tap_rate,
                balance,
                metadata,
                owner_cap_id: campaign.owner_cap_id,
            };

            transfer::share_object(project);
        }
    }

    fun airdrop(campaign: &mut Campaign, nft_ids: &mut vector<ID>, project_id: ID, ctx: &mut TxContext){
        while(!vector::is_empty(&campaign.contributors)){
            let contributor = vector::pop_back(&mut campaign.contributors);
            let quantity_to_mint = table::remove(&mut campaign.contributors_data, contributor);
            while(quantity_to_mint > 0){
                let id = object::new(ctx);
                vector::push_back(nft_ids, object::uid_to_inner(&id));
                transfer::transfer(Nft{ id, project_id }, contributor);
                quantity_to_mint = quantity_to_mint - 1;
            }
        }
    }

    public fun contribute(campaign: &mut Campaign, quantity: u64, paid: Coin<SUI>, ctx: &mut TxContext){
        // assert!(tx_context::epoch(ctx) <= collection.start_timestamp + collection.duration, ECampaignEnded);
        assert!(campaign.status == SActive, EDisallowedAction);

        let metadata = option::borrow_mut(&mut campaign.project_metadata);
        let contributor = tx_context::sender(ctx);
        assert!(metadata.creator != contributor, EUnauthorizedUser);

        let paid_value = coin::value(&paid);
        let to_receive = campaign.price_per_nft * quantity;
        assert!(paid_value == to_receive, EIncorrectAmount);

        coin::put(&mut campaign.balance, paid);
        metadata.current_supply = metadata.current_supply + quantity;

        let campaign_id = object::id(campaign);
        let certificate = Certificate{
            id: object::new(ctx),
            campaign_id,
            quantity
        };

        if(table::contains(&campaign.contributors_data, contributor)){
            let existing_quantity = table::remove(&mut campaign.contributors_data, contributor);
            table::add(&mut campaign.contributors_data, contributor, existing_quantity+ quantity);
        }
        else{
            vector::push_back(&mut campaign.contributors, contributor);
            table::add(&mut campaign.contributors_data, contributor, quantity);
        };

        // TODO emit event

        transfer::transfer(certificate, contributor); // transfer sbt
    }

    public fun claim_funds(campaign: &mut Campaign, ctx: &mut TxContext){
        assert!(campaign.status == SFailure || campaign.status == SCancelled, EDisallowedAction);

        let contributor = tx_context::sender(ctx);
        assert!(table::contains(&campaign.contributors_data, contributor), ENoContributionFound);
        // no need to cleanup campaign.contributors because we don't need it anymore

        // TODO emit event

        let quantity_contributed = table::remove(&mut campaign.contributors_data, contributor);
        let refund_amt = quantity_contributed * campaign.price_per_nft;
        transfer::transfer(coin::take(&mut campaign.balance, refund_amt, ctx), contributor);
    }

    /// Getters
    public fun get_campaign_total_NFT_supply(_project: &Project): u64 {
        _project.metadata.current_supply
    }
}