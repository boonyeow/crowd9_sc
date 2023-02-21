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
    use sui::vec_set::{Self, VecSet};
    // use sui::url::{Self, Url};
    use crowd9_sc::balance::{Self as c9_balance/*, NftSupply , NftBalance*/};
    use crowd9_sc::dict::{Self, Dict};
    use crowd9_sc::nft::{Self, ProjectMetadata /*, Nft*/};


    /// ======= Constants =======
    /// Error Codes
    const EIncorrectAmount: u64 = 0000;
    const EUnauthorizedUser: u64 = 0001;
    const EDisallowedAction: u64 = 0002;
    const ENoContributionFound: u64 = 0004;
    const ECampaignEnded: u64 = 0005;

    /// Status Codes
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
        contributors: Dict<address, u64>,
        certificate_supply: u64,
        project_metadata: Option<ProjectMetadata>,
        owner_cap_id: ID,
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
        start_timestamp: u64,
        end_timestamp: u64,
    }

    struct CampaignCancelled has copy, drop{
        campaign_id: ID,
        funding_goal: u64,
        funding_balance: u64,
    }

    struct CampaignSuccess has copy, drop{
        campaign_id: ID,
        funding_goal: u64,
        funding_balance: u64,
        project_created: ID,
    }

    struct CampaignFailure has copy, drop{
        campaign_id: ID,
        funding_goal: u64,
        funding_balance: u64,
    }

    struct Contribute has copy, drop {
        campaign_id: ID,
        contributor: address,
        contributed_amount: u64
    }

    struct ClaimRefund has copy, drop{
        campaign_id: ID,
        contributor: address,
        refund_amount: u64
    }

    public entry fun create_campaign(name: vector<u8>, description: vector<u8>, funding_goal: u64, price_per_nft: u64, duration: u64, proposed_tap_rate: u64, ctx: &mut TxContext){
        let creator = tx_context::sender(ctx);
        let owner_cap = OwnerCap { id: object::new(ctx) };
        let metadata = nft::create_metadata(name, description, creator);

        let campaign = Campaign{
            id: object::new(ctx),
            status: SInactive,
            funding_goal,
            price_per_nft,
            start_timestamp:0, // TODO - Update timestamp once released
            duration,
            proposed_tap_rate,
            balance: balance::zero<SUI>(),
            contributors: dict::new(ctx),
            certificate_supply: 0,
            project_metadata: option::some(metadata),
            owner_cap_id: object::id(&owner_cap),
        };

        let campaign_id = object::id(&campaign);
        event::emit(CampaignCreated{
            campaign_id,
            campaign_name: name,
            creator,
        });

        transfer::share_object(campaign);
        transfer::transfer(owner_cap, creator);
    }

    public entry fun start_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, ctx: &mut TxContext) {
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SInactive, EDisallowedAction);

        event::emit(CampaignStarted{
            campaign_id: object::id(campaign),
            start_timestamp: campaign.start_timestamp,
            end_timestamp: campaign.start_timestamp + campaign.duration,
        });

        campaign.status = SActive;
        campaign.start_timestamp = tx_context::epoch(ctx); // TODO - Update timestamp once released
    }

    public entry fun cancel_campaign(campaign: &mut Campaign, owner_cap: &OwnerCap, _ctx: &mut TxContext){
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SActive, EDisallowedAction);

        event::emit(CampaignCancelled{
            campaign_id: object::id(campaign),
            funding_goal: campaign.funding_goal,
            funding_balance: balance::value(&campaign.balance),
        });

        campaign.status = SCancelled;
    }

    public entry fun contribute(campaign: &mut Campaign, quantity: u64, paid: Coin<SUI>, ctx: &mut TxContext){
        // assert!(tx_context::epoch(ctx) <= collection.start_timestamp + collection.duration, ECampaignEnded);
        // TODO - Update timestamp once released
        assert!(campaign.status == SActive, EDisallowedAction);

        let metadata = option::borrow(&campaign.project_metadata);
        let contributor = tx_context::sender(ctx);
        assert!(nft::project_creator(metadata) != contributor, EUnauthorizedUser);

        let paid_value = coin::value(&paid);
        let to_receive = campaign.price_per_nft * quantity;
        assert!(paid_value == to_receive, EIncorrectAmount);

        event::emit(Contribute{
            campaign_id: object::id(campaign),
            contributor,
            contributed_amount: to_receive
        });

        coin::put(&mut campaign.balance, paid);
        campaign.certificate_supply = campaign.certificate_supply + quantity;

        let campaign_id = object::id(campaign);
        let certificate = Certificate{
            id: object::new(ctx),
            campaign_id,
            quantity
        };

        if(dict::contains(&campaign.contributors, contributor)){
            let existing_quantity = *dict::borrow(&campaign.contributors, contributor);
            *dict::borrow_mut(&mut campaign.contributors, contributor) = existing_quantity + quantity;
        }
        else{
            dict::add(&mut campaign.contributors, contributor, quantity);
        };

        transfer::transfer(certificate, contributor);
    }

    public fun end_campaign(campaign: &mut Campaign, ctx: &mut TxContext) {
        assert!(campaign.status == SActive, EDisallowedAction);

        let total_raised = balance::value(&campaign.balance);
        if(total_raised < campaign.funding_goal){
            event::emit(CampaignFailure{
                campaign_id: object::id(campaign),
                funding_goal: campaign.funding_goal,
                funding_balance: balance::value(&campaign.balance)
            });

            campaign.status = SFailure;
        }
        else
        {
            let project_id = object::new(ctx);

            campaign.status = SSuccess;

            let nft_ids = vec_set::empty<ID>();
            let metadata = option::extract(&mut campaign.project_metadata);

            airdrop(campaign, &mut metadata, &mut nft_ids, object::uid_to_inner(&project_id), ctx);
            
            event::emit(CampaignSuccess{
                campaign_id: object::id(campaign),
                funding_goal: campaign.funding_goal,
                funding_balance: balance::value(&campaign.balance),
                project_created: object::uid_to_inner(&project_id),
            });

            let balance_value = balance::value(&campaign.balance);
            let balance = coin::into_balance(coin::take(&mut campaign.balance, balance_value, ctx));

            let project = nft::create_project(project_id, nft_ids, campaign.proposed_tap_rate, balance, metadata, campaign.owner_cap_id);

            // rmb to call gov contract to create governance object and share it
            transfer::share_object(project);
        }
    }

    fun airdrop(campaign: &mut Campaign, metadata: &mut ProjectMetadata, nft_ids: &mut VecSet<ID>, project_id: ID, ctx: &mut TxContext){
        let keys = dict::get_keys(&campaign.contributors);
        while(!dict::is_empty(&campaign.contributors)){
            let contributor = vector::pop_back(&mut keys);
            let balance = dict::remove(&mut campaign.contributors, contributor);
            let id = object::new(ctx);

            vec_set::insert(nft_ids, object::uid_to_inner(&id));
            let nft = nft::mint(id, project_id, c9_balance::increase_supply(nft::project_supply_mut(metadata), balance));
            transfer::transfer(nft, contributor);
        };
    }

    public fun claim_funds(campaign: &mut Campaign, ctx: &mut TxContext){
        assert!(campaign.status == SFailure || campaign.status == SCancelled, EDisallowedAction);

        let contributor = tx_context::sender(ctx);
        assert!(dict::contains(&campaign.contributors, contributor), ENoContributionFound);

        let quantity_contributed = dict::remove(&mut campaign.contributors, contributor);
        let refund_amount = quantity_contributed * campaign.price_per_nft;

        event::emit(ClaimRefund{
            campaign_id: object::id(campaign),
            contributor,
            refund_amount
        });

        transfer::transfer(coin::take(&mut campaign.balance, refund_amount, ctx), contributor);
    }



    #[test_only]
    public fun get_campaign_status(campaign: &Campaign): u8{
        campaign.status
    }

    #[test_only]
    public fun get_contributors(campaign: &Campaign): &Dict<address, u64>{
        &campaign.contributors
    }
}