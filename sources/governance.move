module crowd9_sc::governance {
    use crowd9_sc::nft::{Self, Project, Nft};
    use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::dict::{Self, Dict};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use std::option::{Self, Option};
    // use crowd9_sc::crit_bit_u64::is_empty;
    friend crowd9_sc::ino;

    /// ======= Constants =======
    const SCALE_FACTOR: u64 = 1000000000;
    // OUT OF 100
    const QUORUM_THRESHOLD: u64 = 25 ;
    const PROPOSE_THRESHOLD: u64 = 5;

    // Status Codes
    const EDuplicatedVotes: u64 = 001;
    const EUnauthorizedUser: u64 = 002;
    const EInvalidAction: u64 = 003;
    const ENonExistingAction: u64 = 004;
    const EUnexpectedError: u64 = 005;
    const ERepeatedDelegation: u64 = 006;
    const EInvalidDelegatee: u64 = 007;
    const ENoPermission: u64 = 008;
    const EInsufficientBalance: u64 = 008;


    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const VAgainst: u8 = 0;
    const VFor: u8 = 1;
    const VAbstain: u8 = 2;
    const VNoVote: u8 = 3;

    const SActive:u8 = 0;
    const SSuccess:u8 = 1;
    const SFailure:u8 = 2;
    const SAborted:u8 = 4;


    struct Governance has key {
        id: UID,
        project_id: ID,
        start_timestamp: u64,
        ongoing: bool,
        proposal_data: Dict<ID, Proposal>,
        delegations: Table<address, DelegationInfo>,
        voting_power: Dict<address, u64>,
        nft_store: Dict<address, Nft>,
    }

    struct DelegationInfo has copy, drop, store {
        delegate_to: Option<address>,
        delegated_by: vector<address>
    }

    struct Proposal has key, store {
        id: UID,
        proposer: address,
        type: u8,
        status: u8,
        proposed_tap_rate: Option<u64>,
        for: Vote,
        against: Vote,
        abstain: Vote,
        no_vote: Vote,
        snapshot: Dict<address, u64>
    }

    struct Vote has store {
        holders: VecSet<address>,
        count: u64,
    }

    /// ======= Core Functionalities =======
    public entry fun create_governance(
        project: &mut Project,
        current_timestamp: u64,
        nft_store: Dict<address, Nft>,
        voting_power: Dict<address, u64>,
        delegations: Table<address, DelegationInfo>,
        ctx: &mut TxContext
    ) {
        let governance = Governance {
            id: object::new(ctx),
            project_id: object::id(project),
            start_timestamp: current_timestamp,
            ongoing: true,
            proposal_data: dict::new(ctx),
            delegations,
            voting_power,
            nft_store
        };
        // ino::set_stopwatch(collection, ctx);
        transfer::share_object(governance);
    }

    public (friend) fun create_delegation_info(delegate_to: Option<address>, delegated_by: vector<address>): DelegationInfo{
        DelegationInfo{
            delegate_to,
            delegated_by
        }
    }

    public entry fun create_proposal(
        project: &Project,
        governance: &mut Governance,
        type: u8,
        proposed_tap_rate: Option<u64>,
        ctx: &mut TxContext,
    ) {
        let proposer = tx_context::sender(ctx);
        let total_supply = c9_balance::supply_value(nft::project_supply(project));
        // let threshold = total_supply * SCALE_FACTOR * PROPOSE_THRESHOLD;
        let threshold = total_supply * PROPOSE_THRESHOLD/100 * 1000000000;

        // debug::print(&threshold);
        let nft = dict::borrow(&governance.nft_store, proposer);
        let nft_value = nft::nft_value(nft);

        // TODO: check the minimum criteria for creating prop
        assert!((nft_value * SCALE_FACTOR) >= threshold, ENoPermission);    // Must own at least 5% of the total supply to propose
        assert!(governance.ongoing, EInvalidAction);    // Governance must be ongoing and not refunded

        let snapshot = create_snapshot(governance, ctx);
        let (snapshot, address_list) = create_address_list(snapshot);
        let proposal = Proposal {
            id: object::new(ctx),
            proposer,
            type,
            status: SActive,
            proposed_tap_rate,
            for: Vote { holders: vec_set::empty<address>(), count: 0 },
            against: Vote { holders: vec_set::empty<address>(), count: 0 },
            abstain: Vote { holders: vec_set::empty<address>(), count: 0 },
            no_vote: Vote { holders: address_list, count:total_supply },
            snapshot,
        };
        dict::add(&mut governance.proposal_data,object::id(&proposal), proposal);
    }

    fun create_address_list(snapshot: Dict<address,u64>): (Dict<address, u64>, VecSet<address>){
        let voters = dict::get_keys(&snapshot);
        let address_list = vec_set::empty<address>();
        while (!vector::is_empty(&voters)) {
            let voter = vector::pop_back((&mut voters));
            vec_set::insert(&mut address_list, voter);
        };
        (snapshot, address_list)
    }

    fun create_snapshot(governance: &mut Governance, ctx: &mut TxContext): Dict<address, u64>{
        let nft_store = &governance.nft_store;
        let owners = dict::get_keys(nft_store);
        let snapshot = dict::new(ctx);
        while(!vector::is_empty(&owners)){
            let owner = vector::pop_back(&mut owners);
            dict::add(&mut snapshot, owner, nft::nft_value(dict::borrow(nft_store, owner)));
        };
        vector::destroy_empty(owners);
        snapshot
    }

    // Caller has to loop thru the all addresses
    fun get_delegated_votes(
        delegations: &Table<address, DelegationInfo>,
        delegated_address: address,
        nft_store: &Dict<address, Nft>,
        _ctx: &mut TxContext
    ): u64 {
        let queue = vector::singleton(delegated_address);
        let total_value:u64 = 0;
        let working_queue = vector::empty();
        while (!vector::is_empty(&queue)){
            let current_address = vector::pop_back(&mut queue);
            let nft_value = nft::nft_value(dict::borrow(nft_store, current_address));
            total_value = total_value + nft_value;
            let current_address_delegations = table::borrow(delegations, current_address);

            // Can probably just add it straight to the Q.
            // Current method is to go level by level (1 node away from original, then 2, and so on..)
            vector::append(&mut working_queue, current_address_delegations.delegated_by);
            if (vector::is_empty(&queue)){
                vector::append(&mut queue, working_queue);
                working_queue = vector::empty();
            }
        };

        return total_value
    }

    const ECircularDelegation:u64 = 0001;
    fun get_delegation_root(delegations: &Table<address, DelegationInfo>, delegator: address, delegatee: address): address {
        assert!(delegatee != delegator, ECircularDelegation);
        let root_di = *table::borrow(delegations, delegatee);
        let root_address = delegatee;
        while(option::is_some(&root_di.delegate_to)){
            let current_delegatee = *option::borrow(&root_di.delegate_to);
                assert!(current_delegatee != delegator, ECircularDelegation);
            root_di = *table::borrow(delegations, current_delegatee);
            root_address = current_delegatee;
        };
        root_address
    }

    fun get_current_delegation_root(delegations: &Table<address, DelegationInfo>, root_address: address): address {
        let root_di = *table::borrow(delegations, root_address);
        while(option::is_some(&root_di.delegate_to)){
            let current_delegatee = *option::borrow(&root_di.delegate_to);
            root_di = *table::borrow(delegations, current_delegatee);
            root_address = current_delegatee;
        };
        root_address
    }

    public entry fun delegate(governance: &mut Governance, delegatee: address, ctx: &mut TxContext) {
        assert!(governance.ongoing, EInvalidAction);
        let sender = tx_context::sender(ctx);
        let nft_store = &governance.nft_store;
        let delegations = &mut governance.delegations;
        let voting_power = &mut governance.voting_power;

        assert!(dict::contains(nft_store, delegatee) && table::contains(delegations, delegatee), EInvalidAction); // TODO change error code
        assert!(dict::contains(nft_store, sender) && table::contains(delegations, sender), EInvalidAction); // TODO change error code

        // Check for circular delegation & get address of the FINAL ROOT delegatee.
        // To add voting power to this address
        let root = get_delegation_root(delegations, sender, delegatee);

        // Get sender's accumulated voting power
        let accumulated_voting_power = get_delegated_votes(delegations, sender, nft_store, ctx);
        // Add accumulated voting_power to root
        if(dict::contains(voting_power, root)){
            let root_voting_power = dict::borrow(voting_power, root);
            *dict::borrow_mut(voting_power, root) = *root_voting_power + accumulated_voting_power;
        } else {
            dict::add(voting_power, root, accumulated_voting_power);
        };

        // If alr delegating to someone, remove prev delegation details
        // Things to change:
        // 1. Update prev delegatee's root's voting power
        // 2. remove sender from prev delegatee's delegated_by vector

        let prev_delegatee = table::borrow(delegations, sender).delegate_to;
        if (option::is_some(&prev_delegatee)){
            // Update previous root's voting power
            let prev_delegatee_address = option::extract(&mut prev_delegatee);
            let prev_root = get_current_delegation_root(delegations, prev_delegatee_address);
            let prev_root_voting_power = dict::borrow_mut(voting_power, prev_root);
            *prev_root_voting_power = *prev_root_voting_power - accumulated_voting_power;

            // Update prev delegatee's DI - remove sender from prev delegatee's delegated by
            let prev_delegatee_di = table::borrow_mut(delegations, prev_delegatee_address);
            let (_, idx) = vector::index_of(&prev_delegatee_di.delegated_by, &sender);
            vector::swap_remove(&mut prev_delegatee_di.delegated_by, idx);
        } else {
            // If not already delegating to someone, remove voting power from sender
            // Update delegator's voting power
            assert!(*dict::borrow(voting_power, sender) == accumulated_voting_power, 0); // sanity check, should be the same
            let sender_voting_power = dict::borrow_mut(voting_power, sender);
            *sender_voting_power = *sender_voting_power - accumulated_voting_power;

            if(*sender_voting_power == 0){
                dict::remove(voting_power, sender);
            };
        };

        // Update delegator's DI
        let sender_info = table::borrow_mut(delegations, sender);
        if(option::is_some(&sender_info.delegate_to)){
            *option::borrow_mut(&mut sender_info.delegate_to) = delegatee;
        } else {
            option::fill(&mut sender_info.delegate_to, delegatee);
        };

        // Update delegatee's DI
        let delegatee_info = table::borrow_mut(delegations, delegatee);
        vector::push_back(&mut delegatee_info.delegated_by, sender);
    }

    public entry fun remove_delegatee(governance: &mut Governance, ctx: &mut TxContext){
        assert!(governance.ongoing, EInvalidAction);
        let sender = tx_context::sender(ctx);
        let nft_store = &governance.nft_store;
        let voting_power = &mut governance.voting_power;
        let delegations = &mut governance.delegations;

        assert!(dict::contains(nft_store, sender), EInvalidAction); // TODO change error code

        let di = table::borrow_mut(delegations, sender);
        let delegatee = option::extract(&mut di.delegate_to);

        let sender_voting_power = get_delegated_votes(delegations, sender, nft_store, ctx);

        // Update old delegatee's voting power
        let delegatee_voting_power = dict::borrow_mut(voting_power, delegatee);
        *delegatee_voting_power = *delegatee_voting_power - sender_voting_power;
        if (*delegatee_voting_power == 0){
            dict::remove(voting_power, delegatee);
        };

        // Update sender's voting power
        // there shouldn't be an entry in dict because delegated previously so no checks required here
        dict::add(voting_power, sender, sender_voting_power);

        // Update old delegatee's DI
        let delegatee_di = table::borrow_mut(delegations, delegatee);
        let (_, idx) = vector::index_of(&delegatee_di.delegated_by, &delegatee);
        vector::swap_remove(&mut delegatee_di.delegated_by, idx);
    }

    entry fun merge_and_transfer(project: &mut Project, nfts: vector<Nft>, to: address) {
        if(!vector::is_empty(&nfts)){
            let consolidated_nft = vector::pop_back(&mut nfts);
            while(!vector::is_empty(&nfts)){
                let nft = vector::pop_back(&mut nfts);
                nft::join(&mut consolidated_nft, nft, project);
            };
            transfer::transfer(consolidated_nft, to);
        };
        vector::destroy_empty(nfts);
    }

    public entry fun deposit_nft(governance: &mut Governance, project: &mut Project, nfts: vector<Nft>, amount: u64, ctx: &mut TxContext) {
        assert!(!vector::is_empty(&nfts), EUnexpectedError);
        let sender = tx_context::sender(ctx);
        let consolidated_nft = vector::pop_back(&mut nfts);
        let consolidated_value = nft::nft_value(&consolidated_nft);
        if(consolidated_value > amount) {
            let nft_balance = nft::balance_mut(&mut consolidated_nft);
            vector::push_back(&mut nfts, nft::take(project, nft_balance, consolidated_value - amount, ctx));
        } else if (consolidated_value < amount){
            let amount_taken = consolidated_value;
            while(amount_taken != amount){
                assert!(!vector::is_empty(&nfts), EInsufficientBalance);
                let nft = vector::pop_back(&mut nfts);
                let current_value = nft::nft_value(&nft);
                if(amount_taken + current_value > amount){
                    let nft_balance = nft::balance_mut(&mut nft);
                    let excess = amount_taken + current_value - amount;
                    vector::push_back(&mut nfts, nft::take(project, nft_balance, excess, ctx));
                    nft::join(&mut consolidated_nft, nft, project);
                } else {
                    amount_taken = amount_taken + current_value;
                    nft::join(&mut consolidated_nft, nft, project);
                }
            };
        };

        merge_and_transfer(project, nfts, sender);

        if (dict::contains(&governance.nft_store, sender)) {
            let deposited_nft = dict::borrow_mut(&mut governance.nft_store, sender);
            nft::join(deposited_nft, consolidated_nft, project);
        } else {
            dict::add(&mut governance.nft_store, sender, consolidated_nft);
            table::add(
                &mut governance.delegations,
                sender,
                DelegationInfo {
                    delegate_to: option::none(),
                    delegated_by: vector::empty()
                }
            );
        };

        let root = get_current_delegation_root(&governance.delegations, sender);
        let voting_power = &mut governance.voting_power;


        if(!dict::contains(voting_power, root)){
            dict::add(voting_power, root, amount);
        } else {
            let root_voting_power = *dict::borrow(voting_power, root);
            *dict::borrow_mut(voting_power, root) = root_voting_power + amount;
        }
    }

    public entry fun withdraw_nft(governance: &mut Governance, project: &mut Project, amount:u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(dict::contains(&governance.nft_store, sender), EInvalidAction); // Check if sender is in nft_store

        let nft = dict::borrow(&governance.nft_store, sender);
        let nft_value = nft::nft_value(nft);
        assert!(amount <= nft_value, EUnexpectedError); // Check if amount to claim is greater than max withdrawable

        let nft_store = &mut governance.nft_store;
        let delegations = &mut governance.delegations;
        let voting_power = &mut governance.voting_power;
        let sender_voting_power = get_delegated_votes(delegations, sender, nft_store, ctx);
        if(nft_value == amount){
            let nft = dict::remove(nft_store, sender);
            let di = table::remove(delegations, sender);

            if(option::is_some(&di.delegate_to)){
                let delegatee = *option::borrow(&di.delegate_to);
                let delegatee_di = table::borrow_mut(delegations, delegatee);
                let (_, idx) = vector::index_of(&delegatee_di.delegated_by, &sender);
                vector::swap_remove(&mut delegatee_di.delegated_by, idx);
                let delegatee_voting_power = dict::borrow_mut(voting_power, delegatee);
                *delegatee_voting_power = *delegatee_voting_power - sender_voting_power;
            };
            dict::remove(voting_power, sender);

            // For each delegator, extract delegate_to to hold none and update their voting power
            while(!vector::is_empty(&di.delegated_by)){
                let current_delegator = vector::pop_back(&mut di.delegated_by);
                let current_di = table::borrow_mut(delegations, current_delegator);
                let _ = option::extract(&mut current_di.delegate_to);
                let delegator_voting_power = get_delegated_votes(delegations, current_delegator, nft_store, ctx);
                dict::add(voting_power, current_delegator, delegator_voting_power);
            };

            transfer::transfer(nft, sender);
        } else {
            // Check delegations
            let nft = dict::borrow_mut(nft_store, sender);
            let nft_balance = nft::balance_mut(nft);
            let removed_nft = nft::take(project, nft_balance, amount, ctx);

            let di = table::borrow(delegations, sender);
            if(option::is_none(&di.delegate_to)){
                *dict::borrow_mut(voting_power, sender) = sender_voting_power - amount;
            } else {
                let delegatee = di.delegate_to;
                while(option::is_some(&delegatee)){
                    delegatee = table::borrow(delegations, *option::borrow(&delegatee)).delegate_to;
                };
                let root = option::destroy_some(delegatee);
                let root_voting_power = dict::borrow_mut(voting_power, root);
                *root_voting_power = *root_voting_power - amount;
            };

            transfer::transfer(removed_nft, sender);
        }
    }

    public fun vote_proposal(governance: &mut Governance, proposal_id: ID, vote_choice: u8, ctx: &mut TxContext) {
        assert!(governance.ongoing, EInvalidAction);    // Must be an ongoing governance and not refunded

        let proposal = dict::borrow_mut(&mut governance.proposal_data, proposal_id);
        assert!(proposal.status == SActive, EInvalidAction);    // Proposal status must be active

        let sender = tx_context::sender(ctx);
        let current_vote_choice: u8 = get_address_vote_choice(proposal, &sender);
        assert!(current_vote_choice != vote_choice, EDuplicatedVotes);  // Must not cast vote choice that has already been casted

        // TODO change error code
        assert!(dict::contains(&governance.nft_store, sender), 0); // Must own nft
        assert!(!table::contains(&governance.delegations, sender), 0); // Must not delegate to anyone

        let voting_power = dict::borrow(&proposal.snapshot, sender);

        // Updating previous votes
        if (current_vote_choice == VNoVote) {
            vec_set::remove(&mut proposal.no_vote.holders, &sender);
            proposal.no_vote.count = proposal.no_vote.count - *voting_power;
        } else if (current_vote_choice == VFor) {
            vec_set::remove(&mut proposal.for.holders, &sender);
            proposal.for.count = proposal.for.count - *voting_power;
        } else if (current_vote_choice == VAgainst) {
            vec_set::remove(&mut proposal.against.holders, &sender);
            proposal.against.count = proposal.against.count - *voting_power;
        } else if (current_vote_choice == VAbstain) {
            vec_set::remove(&mut proposal.abstain.holders, &sender);
            proposal.abstain.count = proposal.abstain.count - *voting_power;
        } else {
            abort EUnexpectedError
        };
        // Updating current votes
        if (vote_choice == VFor) {
            vec_set::insert(&mut proposal.for.holders, sender);
            proposal.for.count = proposal.for.count + *voting_power;
        } else if (vote_choice == VAgainst) {
            vec_set::insert(&mut proposal.against.holders, sender);
            proposal.against.count = proposal.against.count + *voting_power;
        } else if (vote_choice == VAbstain) {
            vec_set::insert(&mut proposal.abstain.holders, sender);
            proposal.abstain.count = proposal.abstain.count + *voting_power;
        } else {
            abort ENonExistingAction
        }
    }

    public fun end_proposal(governance: &mut Governance, proposal: &mut Proposal, project: &mut Project, ctx: &mut TxContext) {
        assert!(proposal.status == SActive, EInvalidAction);
        // need to add check how long does a proposal duration last, check now >= duedate
        // quorum check
        let total_votes_size = (proposal.for.count + proposal.against.count + proposal.abstain.count + proposal.no_vote.count) * SCALE_FACTOR;
        let total_votes_casted = (proposal.for.count + proposal.against.count + proposal.abstain.count) * SCALE_FACTOR;
        let quorum = total_votes_size * QUORUM_THRESHOLD / 100;
        if (total_votes_casted < quorum) {
            proposal.for.count = proposal.for.count + proposal.no_vote.count;
            proposal.no_vote.count = 0;
        };
        if (proposal.for.count > proposal.against.count) {
            proposal.status = SSuccess;
            if (proposal.type == PAdjustment) {
                nft::withdraw_funds(project, ctx);
                nft::adjust_tap_rate(project, *option::borrow(&proposal.proposed_tap_rate));
            } else if (proposal.type == PRefund){
                governance.ongoing = false;
                nft::set_refund_info(project);
                abort_active_proposals(governance);
            }
        } else {
            proposal.status = SFailure;
        };
    }

    public fun cancel_proposal(proposal: &mut Proposal, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        assert!(proposal.proposer == sender, 0); // TODO: update error code
        assert!(proposal.status == SActive, 0); // TODO: update error code
        proposal.status = SAborted;
    }

    public fun claim_refund(governance: &mut Governance, nfts: vector<Nft>, project: &mut Project, ctx: &mut TxContext) {
        assert!(nft::is_refund_mode(project), EInvalidAction);

        let sender = tx_context::sender(ctx);
        let accumulated_value = 0;
        let nft_store = &mut governance.nft_store;

        if(dict::contains(nft_store, sender)){
            let nft = dict::remove(nft_store, sender);
            accumulated_value = accumulated_value + nft::burn(project, nft);
        };

        while(!vector::is_empty(&nfts)){
            let nft = vector::pop_back(&mut nfts);
            accumulated_value = accumulated_value + nft::burn(project, nft);
        };

        nft::refund(project, accumulated_value, sender, ctx);
        vector::destroy_empty(nfts);
    }

    /// Helper Functions
    fun abort_active_proposals(governance: &mut Governance) {
        let addresses = dict::get_keys(&governance.proposal_data);
        while (!vector::is_empty(&addresses)) {
            let address = vector::pop_back(&mut addresses);
            let proposal: &mut Proposal = dict::borrow_mut(&mut governance.proposal_data, address);
            if (proposal.status == SActive) {
                proposal.status = SAborted;
            }
        }
    }

    /// Getters
    public fun get_address_vote_choice(proposal: &Proposal, voter: &address): u8 {
        if (vec_set::contains(&proposal.no_vote.holders, voter)) {
            return VNoVote
        } else if (vec_set::contains(&proposal.for.holders, voter)) {
            return VFor
        } else if (vec_set::contains(&proposal.against.holders, voter)) {
            return VAgainst
        } else if (vec_set::contains(&proposal.abstain.holders, voter)) {
            return VAbstain
        } else {
            abort EUnauthorizedUser
        }
    }

    #[test_only]
    public fun get_vote_count(proposal: &Proposal, vote_choice: u8): u64{
        if (vote_choice == VFor) {
            return proposal.for.count
        } else if (vote_choice == VAgainst) {
            return proposal.against.count
        } else if (vote_choice == VAbstain) {
            return proposal.abstain.count
        } else if (vote_choice == VNoVote) {
            return proposal.no_vote.count
        } else {
            abort EUnexpectedError
        }
    }

    #[test_only]
    public fun get_vote_holder_size(proposal: &Proposal, vote_choice: u8): u64 {
        if (vote_choice == VFor) {
            return vec_set::size(&proposal.for.holders)
        } else if (vote_choice == VAgainst) {
            return vec_set::size(&proposal.against.holders)
        } else if (vote_choice == VAbstain) {
            return vec_set::size(&proposal.abstain.holders)
        } else if (vote_choice == VNoVote) {
            return vec_set::size(&proposal.no_vote.holders)
        } else {
            abort EUnexpectedError
        }
    }

    #[test_only]
    public fun get_proposal_data(governance: &mut Governance, proposal_id: ID): &mut Proposal {
        // let key_list: vector<ID> = dict::get_keys(&governance.proposal_data);
        // let key = vector::pop_back(&mut key_list);
        // let proposal_obj = dict::borrow_mut(&mut governance.proposal_data, key);
        // proposal_obj
        dict::borrow_mut(&mut governance.proposal_data, proposal_id)
    }



    #[test_only]
    public fun get_contributor_balance(governance: &Governance, contributor: address): u64{
        let nft = dict::borrow(&governance.nft_store, contributor);
        nft::nft_value(nft)
    }

    #[test_only]
    public fun get_nftstore_user_balance(governance: &mut Governance, ctx:&mut TxContext): u64 {
        let nft = dict::borrow(&governance.nft_store, tx_context::sender(ctx));
        nft::nft_value(nft)
    }

    #[test_only]
    public fun is_user_in_nft_store(governance: &Governance, user: address): bool {
        dict::contains(&governance.nft_store, user)
    }

    #[test_only]
    public fun is_user_in_delegations(governance: &Governance, user: address): bool{
        table::contains(&governance.delegations, user)
    }

    #[test_only]
    public fun get_nft_store(governance: &Governance): &Dict<address, Nft>{
        &governance.nft_store
    }

    #[test_only]
    public fun get_voting_power(governance: &Governance, user: address): u64{
        if (dict::contains(&governance.voting_power, user)){
            *dict::borrow(&governance.voting_power, user)
        } else { 0 }
    }

    #[test_only]
    public fun is_delegating(governance: &Governance, user: address): bool {
        let delegations = &governance.delegations;
        let di = table::borrow(delegations, user);
        option::is_some(&di.delegate_to)
    }

    #[test_only]
    public fun is_delegated_to_address(governance: &Governance, delegator: address, delegatee: address): bool {
        let delegations = &governance.delegations;
        let di = table::borrow(delegations, delegator);
        let delegated_to = *option::borrow(&di.delegate_to);
        if (delegatee == delegated_to){
            true
        } else {
            false
        }
    }

    // Checks if delegatee is currently in delegator's delegate_to DI field
    #[test_only]
    public fun is_delegated_by(governance: &Governance, delegator: address, delegatee: address): bool{
        let delegations = &governance.delegations;
        let di = table::borrow(delegations, delegatee);
        // std::debug::print(di);
        vector::contains(&di.delegated_by, &delegator)
    }

    #[test_only]
    public fun get_nft_value_in_store(governance: &Governance, user: address): u64 {
        if (dict::contains(&governance.nft_store, user)) {
            nft::nft_value(dict::borrow(&governance.nft_store, user))
        } else { 0 }
    }

    #[test_only]
    public fun find_delegation_root(governance: &Governance, starting_user: address): address{
        let delegations = &governance.delegations;
        let current_di = *table::borrow(delegations, starting_user);

        while(option::is_some(&current_di.delegate_to)){
                starting_user = *option::borrow(&current_di.delegate_to);
                current_di = *table::borrow(delegations, starting_user);
        };
        starting_user
    }

    #[test_only]
    public fun get_delegation_info(governance: &Governance, user: address): DelegationInfo {
        let delegations = &governance.delegations;
        *table::borrow(delegations, user)
    }

    #[test_only]
    public fun take(project: &mut Project, nft: &mut Nft, value: u64, ctx: &mut TxContext): Nft{
        nft::take(project, nft::balance_mut(nft), value, ctx)
    }

    #[test_only]
    public fun set_refund_mode(governance: &mut Governance, project: &mut Project){
        nft::set_refund_info(project);
        governance.ongoing = false;
    }
}