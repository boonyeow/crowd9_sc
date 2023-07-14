module crowd9_sc::governance {
    use sui::tx_context::TxContext;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::coin::{Self, Coin};
    use sui::balance::{Balance};
    use sui::tx_context::{Self};
    use sui::linked_table::{Self, LinkedTable};
    use sui::clock::{Self, Clock};
    use crowd9_sc::lib::{Self};
    use std::option::{Self, Option};
    use std::vector::{Self};

    const VAgainst: u8 = 0;
    const VFor: u8 = 1;
    const VAbstain: u8 = 2;
    const VNoVote: u8 = 3;

    const SActive: u8 = 0;
    const SInactive: u8 = 1;
    const SSuccess: u8 = 2;
    const SFailure: u8 = 3;
    const SAborted: u8 = 4;
    const SExecuted: u8 = 5;

    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const EDuplicatedVotes: u64 = 001;
    const EUnauthorizedUser: u64 = 002;
    const EInvalidAction: u64 = 003;
    const ENonExistingAction: u64 = 004;
    const EUnxpectedError: u64 = 005;
    const ERepeatedDelegation: u64 = 006;
    const EInvalidDelegatee: u64 = 007;
    const ENoPermission: u64 = 008;
    const EInsufficientBalance: u64 = 008;
    const ECircularDelegation: u64 = 009;
    const EInvalidVoteChoice: u64 = 010;
    const EInvalidParameter: u64 = 011;

    // 3 days
    const PROPOSAL_DURATION: u64 = 259200 * 1000;
    // 0.5% of total votes to create proposal
    const PROPOSAL_CREATE_THRESHOLD: u64 = 5;
    // 5% of total votes for proposal to be considered valid
    const QUORUM_THRESHOLD: u64 = 50;
    // 66.7% for proposal to be approved
    const APPROVAL_THRESHOLD: u64 = 667;
    const THRESHOLD_DENOMINATOR: u64 = 1000;

    struct Governance<phantom X, phantom Y> has key, store {
        id: UID,
        creator: address,
        // X = raised coin type
        treasury: Balance<X>,
        // Y = governance coin type
        deposits: Balance<Y>,
        store: LinkedTable<address, u64>,
        delegations: LinkedTable<address, DelegationInfo>,
        proposal_data: Table<ID, Proposal>,
        tap_info: TapInfo,
        total_supply: u64,
        ongoing: bool,
        refund_amount: u64,
        setting: GovernanceSetting,
        execution_sequence: vector<ID>
    }

    struct TapInfo has store {
        tap_rate: u64,
        last_max_withdrawable: u64,
        last_withdrawn_timestamp: u64
    }

    struct GovernanceSetting has store {
        proposal_threshold: u64,
        quorum_threshold: u64,
        // minimum participation
        approval_threshold: u64,
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
        snapshot: LinkedTable<address, u64>,
        start_timestamp: u64,
    }

    struct Vote has store {
        holders: VecSet<address>,
        count: u64
    }

    struct DelegationInfo has copy, drop, store {
        current_voting_power: u64,
        delegate_to: Option<address>,
        delegated_by: vector<address>
    }

    public fun create_governance<X, Y>(
        creator: address,
        treasury: Balance<X>,
        deposits: Balance<Y>,
        store: LinkedTable<address, u64>,
        total_supply: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Governance<X, Y> {
        Governance {
            id: object::new(ctx),
            creator,
            treasury,
            deposits,
            store,
            delegations: linked_table::new(ctx),
            proposal_data: table::new(ctx),
            tap_info: TapInfo {
                tap_rate: 0, last_max_withdrawable: 0, last_withdrawn_timestamp: clock::timestamp_ms(
                    clock
                )
            },
            total_supply,
            ongoing: true,
            refund_amount: 0,
            setting: GovernanceSetting { proposal_threshold: total_supply * PROPOSAL_CREATE_THRESHOLD, quorum_threshold: total_supply * QUORUM_THRESHOLD, approval_threshold: APPROVAL_THRESHOLD },
            execution_sequence: vector::empty()
        }
    }

    public entry fun deposit_coin<X, Y>(governance: &mut Governance<X, Y>, coins: Coin<Y>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let store = &mut governance.store;

        if (linked_table::contains(store, sender)) {
            let existing_quantity = *linked_table::borrow(store, sender);
            *linked_table::borrow_mut(store, sender) = existing_quantity + coin::value(&coins);
        } else {
            linked_table::push_back(store, sender, coin::value(&coins));
        };

        coin::put(&mut governance.deposits, coins);
    }

    public fun withdraw_coin<X, Y>(governance: &mut Governance<X, Y>, amount: u64, ctx: &mut TxContext): Coin<Y> {
        let sender = tx_context::sender(ctx);
        let store = &mut governance.store;
        assert!(linked_table::contains(store, sender), ENoPermission);
        let existing_quantity = *linked_table::borrow(store, sender);
        assert!(existing_quantity >= amount, EInsufficientBalance);

        if (existing_quantity == amount) {
            let _ = linked_table::remove(store, sender);
        } else {
            *linked_table::borrow_mut(store, sender) = existing_quantity - amount;
        };

        coin::take(&mut governance.deposits, amount, ctx)
    }

    fun get_delegation_root(
        delegations: &LinkedTable<address, DelegationInfo>,
        sender: address
    ): address {
        let delegated_user = &linked_table::borrow(delegations, sender).delegate_to;
        let root = sender;
        while (option::is_some(delegated_user)) {
            let user = *option::borrow(delegated_user);
            assert!(user != sender, ECircularDelegation);
            delegated_user = &linked_table::borrow(delegations, user).delegate_to;
            root = user;
        };
        root
    }

    public entry fun delegate<X, Y>(
        governance: &mut Governance<X, Y>,
        delegate_to: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let store = &governance.store;
        assert!(linked_table::contains(store, delegate_to) && linked_table::contains(store, sender), ENoPermission);

        let delegations = &mut governance.delegations;
        let user_di = linked_table::borrow(delegations, sender);
        let user_voting_power = user_di.current_voting_power;
        assert!(option::is_none(&user_di.delegate_to), EInvalidAction);

        // Add voting power to root
        let root = get_delegation_root(delegations, sender);
        let root_di_mut = linked_table::borrow_mut(delegations, root);
        root_di_mut.current_voting_power = root_di_mut.current_voting_power + user_voting_power;

        // Update sender delegation info (voting power & delegate_to)
        let user_di_mut = linked_table::borrow_mut(delegations, sender);
        user_di_mut.current_voting_power = 0;
        *option::borrow_mut(&mut user_di_mut.delegate_to) = delegate_to;

        // Update delegate_to's delegated_by
        let delegate_to_di_mut = linked_table::borrow_mut(delegations, delegate_to);
        vector::push_back(&mut delegate_to_di_mut.delegated_by, sender);
    }

    public entry fun remove_delegate<X, Y>(governance: &mut Governance<X, Y>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let store = &governance.store;
        assert!(linked_table::contains(store, sender), ENoPermission);

        let delegations = &mut governance.delegations;
        let user_di = linked_table::borrow(delegations, sender);
        let user_voting_power = 0;
        assert!(option::is_some(&user_di.delegate_to), EInvalidAction);

        // Get user's current voting power
        let queue = vector::singleton(sender);
        while (!vector::is_empty(&queue)) {
            let current_address = vector::pop_back(&mut queue);
            user_voting_power = user_voting_power + *linked_table::borrow(store, current_address);
            let current_address_delegated_by = linked_table::borrow(delegations, current_address).delegated_by;
            vector::append(&mut queue, current_address_delegated_by);
        };

        // Remove voting power from the root
        let root = get_delegation_root(delegations, sender);
        let root_di_mut = linked_table::borrow_mut(delegations, root);
        root_di_mut.current_voting_power = root_di_mut.current_voting_power - user_voting_power;

        // Update sender delegation info (voting power & delegate_to)
        let user_di_mut = linked_table::borrow_mut(delegations, sender);
        user_di_mut.current_voting_power = user_voting_power;
        let delegate_to = option::extract(&mut user_di_mut.delegate_to);

        // Update delegate_to's delegated_by
        let delegate_to_di_mut = linked_table::borrow_mut(delegations, delegate_to);
        let (_, idx) = vector::index_of(&delegate_to_di_mut.delegated_by, &sender);
        vector::swap_remove<address>(&mut delegate_to_di_mut.delegated_by, idx);
    }

    public entry fun create_proposal<X, Y>(
        governance: &mut Governance<X, Y>,
        type: u8,
        proposed_tap_rate: Option<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(governance.ongoing, EInvalidAction);
        assert!(type == PAdjustment || type == PRefund, EInvalidParameter);
        if (type == PAdjustment) {
            assert!(option::is_some(&proposed_tap_rate), EInvalidParameter);
        } else {
            assert!(governance.tap_info.tap_rate == 0, EInvalidAction);
        };

        let min_votes_required = lib::mul_div_u64(
            governance.total_supply,
            PROPOSAL_CREATE_THRESHOLD,
            THRESHOLD_DENOMINATOR
        );

        let sender = tx_context::sender(ctx);
        let store = &governance.store;
        assert!(
            (linked_table::contains(store, sender) && linked_table::borrow(
                &governance.delegations,
                sender
            ).current_voting_power >= min_votes_required) || sender == governance.creator,
            ENoPermission
        );


        let snapshot = linked_table::new<address, u64>(ctx);
        let delegations = &governance.delegations;
        let current_node = linked_table::front(delegations);

        while (option::is_some(current_node)) {
            let user = *option::borrow(current_node);
            let user_di = linked_table::borrow(delegations, user);

            // Filter users w/o voting power
            if (user_di.current_voting_power > 0) {
                linked_table::push_back(&mut snapshot, user, user_di.current_voting_power);
            };
            current_node = linked_table::next(delegations, user);
        };

        // Might want to reconsider using vec_set so we can handle >1k limit
        let proposal = Proposal {
            id: object::new(ctx),
            proposer: sender,
            type,
            status: SActive,
            proposed_tap_rate,
            for: Vote { holders: vec_set::empty<address>(), count: 0 },
            against: Vote { holders: vec_set::empty<address>(), count: 0 },
            abstain: Vote { holders: vec_set::empty<address>(), count: 0 },
            snapshot,
            start_timestamp: clock::timestamp_ms(clock) // Adjust as needed
        };
        let proposal_id = object::id(&proposal);
        vector::push_back(&mut governance.execution_sequence, proposal_id);
        table::add(&mut governance.proposal_data, proposal_id, proposal);
    }

    public fun vote_proposal<X, Y>(
        governance: &mut Governance<X, Y>,
        proposal_id: ID,
        vote_choice: u8,
        ctx: &mut TxContext
    ) {
        assert!(vote_choice < 3, EInvalidVoteChoice); // handles VFor, VAgainst, VAbstain
        let proposal = table::borrow_mut(&mut governance.proposal_data, proposal_id);
        assert!(proposal.status == SActive, EInvalidAction);

        let sender = tx_context::sender(ctx);
        assert!(linked_table::contains(&proposal.snapshot, sender), ENoPermission);

        let current_vote_choice: u8 = get_address_vote_choice(proposal, &sender);
        assert!(current_vote_choice != vote_choice, EDuplicatedVotes);

        let voting_power = linked_table::borrow(&proposal.snapshot, sender);

        // Update previous vote
        if (current_vote_choice == VFor) {
            vec_set::remove(&mut proposal.for.holders, &sender);
            proposal.for.count = proposal.for.count - *voting_power;
        } else if (current_vote_choice == VAgainst) {
            vec_set::remove(&mut proposal.against.holders, &sender);
            proposal.against.count = proposal.against.count - *voting_power;
        } else if (current_vote_choice == VAbstain) {
            vec_set::remove(&mut proposal.abstain.holders, &sender);
            proposal.abstain.count = proposal.abstain.count - *voting_power;
        };

        // Update current vote
        if (vote_choice == VFor) {
            vec_set::insert(&mut proposal.for.holders, sender);
            proposal.for.count = proposal.for.count + *voting_power;
        } else if (vote_choice == VAgainst) {
            vec_set::insert(&mut proposal.against.holders, sender);
            proposal.against.count = proposal.against.count + *voting_power;
        } else if (vote_choice == VAbstain) {
            vec_set::insert(&mut proposal.abstain.holders, sender);
            proposal.abstain.count = proposal.abstain.count + *voting_power;
        }
    }

    public fun get_address_vote_choice(proposal: &Proposal, voter: &address): u8 {
        if (vec_set::contains(&proposal.for.holders, voter)) {
            return VFor
        } else if (vec_set::contains(&proposal.against.holders, voter)) {
            return VAgainst
        } else if (vec_set::contains(&proposal.abstain.holders, voter)) {
            return VAbstain
        } else {
            return VNoVote
        }
    }

    /// TODO: To check
    public fun end_proposal<X, Y>(
        governance: &mut Governance<X, Y>,
        proposal: &mut Proposal,
        clock: &Clock,
    ) {
        assert!(
            proposal.status == SActive || clock::timestamp_ms(clock) > proposal.start_timestamp + PROPOSAL_DURATION,
            EInvalidAction
        );

        let proposal_id = object::id(proposal);
        let quorum = lib::mul_div_u64(governance.total_supply, QUORUM_THRESHOLD, THRESHOLD_DENOMINATOR);
        let approval = lib::mul_div_u64(governance.total_supply, APPROVAL_THRESHOLD, THRESHOLD_DENOMINATOR);
        let total_votes = governance.total_supply;
        let total_votes_casted = proposal.for.count + proposal.against.count + proposal.abstain.count;
        let no_votes = total_votes - total_votes_casted;

        if (total_votes_casted >= quorum && no_votes + proposal.for.count > approval) {
            proposal.status = SSuccess;
        } else {
            proposal.status = SFailure;
            let (_, proposal_index) = vector::index_of(&governance.execution_sequence, &proposal_id);
            vector::remove(&mut governance.execution_sequence, proposal_index);
        }
    }

    public fun execute_proposal<X, Y>(governance: &mut Governance<X, Y>, proposal: &mut Proposal, clock: &Clock) {
        assert!(proposal.status == SSuccess, EInvalidAction);

        let proposal_id = object::id(proposal);
        if (proposal.type == PAdjustment) {
            let tap_info = &mut governance.tap_info;
            let proposed_tap_rate = *option::borrow(&proposal.proposed_tap_rate);
            let current_timestamp = clock::timestamp_ms(clock);
            tap_info.last_max_withdrawable = tap_info.last_max_withdrawable + (current_timestamp - tap_info.last_withdrawn_timestamp) * tap_info.tap_rate;
            tap_info.tap_rate = proposed_tap_rate;
            tap_info.last_withdrawn_timestamp = current_timestamp;

            if (proposed_tap_rate == 0) {
                // Proceed to invalidate all other proposals
                let proposal_to_execute = *vector::borrow(
                    &governance.execution_sequence,
                    vector::length(&governance.execution_sequence) - 1
                );

                while (proposal_to_execute != proposal_id) {
                    let _ = vector::pop_back(&mut governance.execution_sequence);
                    let proposal = table::borrow_mut(&mut governance.proposal_data, proposal_to_execute);
                    proposal.status = SAborted;
                    proposal_to_execute = *vector::borrow(
                        &governance.execution_sequence,
                        vector::length(&governance.execution_sequence) - 1
                    );
                }
            }
        } else {
            governance.ongoing = false;
        };

        proposal.status = SExecuted;
        let (_, proposal_index) = vector::index_of(&governance.execution_sequence, &proposal_id);
        vector::remove(&mut governance.execution_sequence, proposal_index);
    }

    public fun cancel_proposal<X, Y>(governance: &mut Governance<X, Y>, proposal: &mut Proposal, ctx: &mut TxContext) {
        assert!(proposal.status == SActive || proposal.status == SSuccess, EInvalidAction);
        let sender = tx_context::sender(ctx);
        assert!(proposal.proposer == sender, ENoPermission);

        let proposal_id = object::id(proposal);
        proposal.status = SAborted;
        let (_, proposal_index) = vector::index_of(&governance.execution_sequence, &proposal_id);
        vector::remove(&mut governance.execution_sequence, proposal_index);
    }

    public fun claim_refund<X, Y>(governance: &mut Governance<X, Y>, coins: Coin<Y>, ctx: &mut TxContext): Coin<X> {
        assert!(!governance.ongoing, EInvalidAction);
        let y_value_deposited = coin::value(&coins);
        coin::put(&mut governance.deposits, coins);
        let x_value_to_refund = lib::mul_div_u64(y_value_deposited, governance.refund_amount, governance.total_supply);
        coin::take(&mut governance.treasury, x_value_to_refund, ctx)
    }

    public fun withdraw_funds<X, Y>(governance: &mut Governance<X, Y>, clock: &Clock, ctx: &mut TxContext): Coin<X> {
        let sender = tx_context::sender(ctx);
        assert!(governance.ongoing && governance.creator == sender, EInvalidAction);

        let current_timestamp = clock::timestamp_ms(clock);
        let tap_info = &mut governance.tap_info;
        let max_withdrawable = tap_info.last_max_withdrawable + ((current_timestamp - tap_info.last_withdrawn_timestamp) * tap_info.tap_rate);

        // Update tap_info
        tap_info.last_max_withdrawable = 0;
        tap_info.last_withdrawn_timestamp = current_timestamp;

        coin::take(&mut governance.treasury, max_withdrawable, ctx)
    }
}