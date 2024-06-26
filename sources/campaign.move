module crowd9_sc::campaign {
    use std::option::{Self, Option};
    use sui::linked_table::{Self, LinkedTable};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::clock::{Self, Clock};
    use sui::math::{Self};
    use sui::event::{Self};
    use crowd9_sc::coin_manager::{Self, CoinBag};
    use crowd9_sc::governance::{Self};
    use std::type_name::{Self};
    use std::ascii::String;


    /// ======= Constants =======
    /// Error Codes
    // const EIncorrectAmount: u64 = 0000;
    const EUnauthorizedUser: u64 = 0001;
    const EDisallowedAction: u64 = 0002;
    // const ENoContributionFound: u64 = 0004;
    const ECampaignEnded: u64 = 0005;
    const EInvalidDuration: u64 = 0006;
    const EInvalidCoinAmount: u64 = 0007;

    /// Status Codes
    const SInactive: u8 = 0;
    const SActive: u8 = 1;
    const SSuccess: u8 = 2;
    const SFailure: u8 = 3;
    const SCancelled: u8 = 4;
    const SCompleted: u8 = 5;

    /// Duration Length
    const MS_IN_A_DAY: u64 = 1000 * 60 * 60 * 24;

    struct OwnerCap has key {
        id: UID
    }

    struct Campaign<phantom X> has key, store {
        id: UID,
        creator: address,
        name: vector<u8>,
        description: vector<u8>,
        image_url: vector<u8>,
        price_per_token: u64,
        status: u8,
        funding_goal: u64,
        start_timestamp: u64,
        duration: u64,
        balance: Balance<X>,
        // Contributions maps address to tokens purchased
        contributions: Option<LinkedTable<address, u64>>,
        tokens_to_mint: u64,
        owner_cap_id: ID,
        governance_id: Option<ID>
    }

    /// ======= Events =======
    struct CampaignEvent has copy, drop {
        campaign_id: ID,
        status: u8,
    }

    struct CreateGovernanceEvent has copy, drop {
        campaign_id: ID,
        governance_id: ID,
        status: u8,
        coin_type: String
    }

    struct ContributeEvent has copy, drop {
        campaign_id: ID,
        contributor: address,
        amount_raised: u64,
    }

    fun get_duration(duration_type: u8): u64 {
        assert!(duration_type < 3, EInvalidDuration);
        if (duration_type == 0) {
            MS_IN_A_DAY * 7
        } else if (duration_type == 1) {
            MS_IN_A_DAY * 14
        } else {
            MS_IN_A_DAY * 21
        }
    }

    public entry fun create_campaign<X>(
        name: vector<u8>,
        description: vector<u8>,
        image_url: vector<u8>,
        price_per_token: u64,
        funding_goal: u64,
        duration_type: u8,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let owner_cap = OwnerCap { id: object::new(ctx) };
        let duration: u64 = get_duration(duration_type);
        let campaign = Campaign {
            id: object::new(ctx),
            creator,
            name,
            description,
            image_url,
            price_per_token,
            status: SInactive,
            funding_goal,
            start_timestamp: 0,
            duration,
            balance: balance::zero<X>(),
            contributions: option::some(linked_table::new(ctx)),
            tokens_to_mint: 0,
            owner_cap_id: object::id(&owner_cap),
            governance_id: option::none()
        };


        event::emit(CampaignEvent {
            campaign_id: object::id(&campaign),
            status: campaign.status
        });

        transfer::share_object(campaign);
        transfer::transfer(owner_cap, creator);
    }

    public entry fun update<X>(
        campaign: &mut Campaign<X>,
        name: Option<vector<u8>>,
        description: Option<vector<u8>>,
        image_url: Option<vector<u8>>,
        price_per_token: Option<u64>,
        funding_goal: Option<u64>,
        duration_type: Option<u8>,
        owner_cap: &OwnerCap
    ) {
        assert!(campaign.status == SInactive, EDisallowedAction);
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);

        if (option::is_some(&name)) {
            campaign.name = option::destroy_some(name)
        };

        if (option::is_some(&description)) {
            campaign.description = option::destroy_some(description)
        };

        if (option::is_some(&image_url)) {
            campaign.image_url = option::destroy_some(image_url)
        };

        if (option::is_some(&price_per_token)) {
            campaign.price_per_token = option::destroy_some(price_per_token)
        };

        if (option::is_some(&funding_goal)) {
            campaign.funding_goal = option::destroy_some(funding_goal)
        };

        if (option::is_some(&duration_type)) {
            campaign.duration = get_duration(option::destroy_some(duration_type))
        };
    }

    public entry fun start<X>(campaign: &mut Campaign<X>, owner_cap: &OwnerCap, clock: &Clock) {
        assert!(campaign.status == SInactive, EDisallowedAction);
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);

        campaign.status = SActive;
        campaign.start_timestamp = clock::timestamp_ms(clock);

        event::emit(CampaignEvent {
            campaign_id: object::id(campaign),
            status: campaign.status
        });
    }

    public entry fun contribute<X>(coins: Coin<X>, campaign: &mut Campaign<X>, clock: &Clock, ctx: &mut TxContext) {
        let contributor = tx_context::sender(ctx);
        let coin_value = coin::value(&coins);
        assert!(campaign.creator != contributor, EUnauthorizedUser);
        // TODO: uncomment later
        assert!(clock::timestamp_ms(clock) <= (campaign.start_timestamp + campaign.duration), ECampaignEnded);
        assert!(campaign.status == SActive, EDisallowedAction);
        assert!(coin_value % campaign.price_per_token == 0, EInvalidCoinAmount);

        coin::put(&mut campaign.balance, coins);
        let contributions = option::borrow_mut(&mut campaign.contributions);
        let tokens_purchased = coin_value / campaign.price_per_token;
        campaign.tokens_to_mint = campaign.tokens_to_mint + tokens_purchased;

        if (linked_table::contains(contributions, contributor)) {
            let existing_quantity = *linked_table::borrow(contributions, contributor);
            *linked_table::borrow_mut(contributions, contributor) = existing_quantity + tokens_purchased;
        }else {
            linked_table::push_back(contributions, contributor, tokens_purchased);
        };

        event::emit(ContributeEvent {
            campaign_id: object::id(campaign),
            contributor,
            amount_raised: balance::value(&campaign.balance)
        })
    }

    public entry fun cancel<X>(campaign: &mut Campaign<X>, owner_cap: &OwnerCap, ctx: &mut TxContext) {
        assert!(object::id(owner_cap) == campaign.owner_cap_id, EUnauthorizedUser);
        assert!(campaign.status == SActive, EDisallowedAction);
        campaign.status = SCancelled;
        process_refund<X>(campaign, ctx);

        event::emit(CampaignEvent {
            campaign_id: object::id(campaign),
            status: campaign.status
        });
    }

    // Cancel -> when proj status is active, only admin cap holder can call
    // Expire -> when current timestamp > proj duration && funds < goal, anyone can call it (to claim their locked funds)
    // End -> when current timestamp > proj duration && funds > goal, moving to next stage (governance), only proj creator can call
    public fun end<X>(campaign: &mut Campaign<X>, clock: &Clock, ctx: &mut TxContext) {
        // TODO: uncomment later
        assert!(
            campaign.status == SActive && clock::timestamp_ms(clock) > (campaign.start_timestamp + campaign.duration),
            EDisallowedAction
        );
        assert!(campaign.status == SActive, EDisallowedAction);
        let total_raised = balance::value(&campaign.balance);
        if (total_raised < campaign.funding_goal) {
            campaign.status = SFailure;
            process_refund<X>(campaign, ctx);
        } else {
            campaign.status = SSuccess;
        };

        event::emit(CampaignEvent {
            campaign_id: object::id(campaign),
            status: campaign.status
        });
    }

    // w/o time dependency, to remove after testing
    public fun end_force<X>(campaign: &mut Campaign<X>, _clock: &Clock, ctx: &mut TxContext) {
        assert!(campaign.status == SActive, EDisallowedAction);
        let total_raised = balance::value(&campaign.balance);
        if (total_raised < campaign.funding_goal) {
            campaign.status = SFailure;
            process_refund<X>(campaign, ctx);
        } else {
            campaign.status = SSuccess;
        };

        event::emit(CampaignEvent {
            campaign_id: object::id(campaign),
            status: campaign.status
        });
    }

    fun process_refund<T>(campaign: &mut Campaign<T>, ctx: &mut TxContext) {
        let contributions = option::extract(&mut campaign.contributions);
        while (!linked_table::is_empty(&contributions)) {
            let (contributor, no_of_tokens_purchased) = linked_table::pop_back(&mut contributions);
            let coin = coin::take(&mut campaign.balance, no_of_tokens_purchased * campaign.price_per_token, ctx);
            transfer::public_transfer(coin, contributor);
        };

        linked_table::destroy_empty(contributions);
    }

    public fun transition_to_governance<X, Y>(
        coin_bag: &mut CoinBag,
        campaign: &mut Campaign<X>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(campaign.status == SSuccess, 0); // must be success
        campaign.status = SCompleted; // indicate governance phase

        let (treasury_cap, metadata) = coin_manager::remove<Y>(coin_bag);
        let contributions = option::extract(&mut campaign.contributions);

        let decimals = coin::get_decimals<Y>(&metadata);
        let scale_factor = math::pow(10, decimals);

        let governance_token = coin::into_balance(
            coin::mint<Y>(&mut treasury_cap, campaign.tokens_to_mint * scale_factor, ctx)
        );

        let treasury_tokens = balance::withdraw_all(&mut campaign.balance);

        let campaign_id = object::id(campaign);
        let governance = governance::create_governance(
            campaign.creator,
            campaign.name,
            campaign.description,
            campaign.image_url,
            campaign_id,
            treasury_tokens,
            governance_token,
            contributions,
            scale_factor,
            clock,
            ctx
        );

        let governance_id = object::id(&governance);

        option::fill(&mut campaign.governance_id, governance_id);

        transfer::public_share_object(governance);
        transfer::public_freeze_object(treasury_cap);
        transfer::public_transfer(metadata, campaign.creator);

        event::emit(CreateGovernanceEvent {
            campaign_id: object::id(campaign),
            governance_id,
            status: campaign.status,
            coin_type: type_name::into_string(type_name::get<Y>())
        });
    }


    #[test_only]
    public entry fun update_campaign_status<X>(campaign: &mut Campaign<X>, status: u8) {
        campaign.status = status
    }

    #[test_only]
    public fun verify_campaign_details<T>(
        campaign: &Campaign<T>,
        name: vector<u8>,
        description: vector<u8>,
        image_url: vector<u8>,
        price_per_token: u64,
        funding_goal: u64,
        duration_type: u8
    ): bool {
        return campaign.name == name &&
            campaign.description == description &&
            campaign.image_url == image_url &&
            campaign.price_per_token == price_per_token &&
            campaign.funding_goal == funding_goal &&
            campaign.duration == get_duration(duration_type)
    }

    #[test_only]
    public fun verify_campaign_status<T>(campaign: &Campaign<T>, status: u8): bool {
        return campaign.status == status
    }

    #[test_only]
    public fun verify_contribution_amount<T>(
        campaign: &Campaign<T>,
        user: address,
        total_contribution_by_user: u64,
        total_contributions: u64,
    ): bool {
        let contributions = option::borrow(&campaign.contributions);
        return balance::value(&campaign.balance) == total_contributions
            && campaign.tokens_to_mint == total_contributions / campaign.price_per_token
            && linked_table::contains(contributions, user)
            && *linked_table::borrow(contributions, user) == total_contribution_by_user / campaign.price_per_token
    }
}