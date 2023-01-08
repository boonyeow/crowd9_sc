module crowd9_sc::governance {
    use crowd9_sc::ino::{Self, Project};
    use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::dict::{Self, Dict};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    // use sui::sui::SUI;
    // use sui::coin::{Self};

    /// ======= Constants =======
    // Status Codes
    const EDuplicatedVotes: u64 = 001;
    const EUnauthorizedUser: u64 = 002;
    const EUnauthorizedAction: u64 = 003;
    const ENonExistingAction: u64 = 004;
    const EUnxpectedError: u64 = 005;

    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const VAgainst: u8 = 0;
    const VFor: u8 = 1;
    const VAbstain: u8 = 2;
    const VNoVote: u8 = 3;

    struct Governance has key {
        id: UID,
        project_id: ID,
        start_timestamp: u64,
        proposal_data: Dict<address, Proposal>,
        delegated_to: Table<address, address>
    }

    struct Proposal has key, store {
        id: UID,
        type: u8,
        proposed_tap_rate: u8,
        for: Vote,
        against: Vote,
        abstain: Vote,
        no_vote: Vote,
    }

    struct Vote has store {
        holders: VecSet<address>,
        count: u64,
    }

    /// ======= Core Functionalities =======
    public fun create_governance(
        project: &mut Project,
        start_timestamp: u64,
        ctx: &mut TxContext
    ) {
        let governance = Governance {
            id: object::new(ctx),
            project_id: object::id(project),
            start_timestamp,
            proposal_data: dict::new(ctx),
            delegated_to: table::new(ctx)
        };
        // ino::set_stopwatch(collection, ctx);
        transfer::share_object(governance);
    }

    public fun create_proposal(
        address_list: VecSet<address>,
        project: &Project,
        governance: &mut Governance,
        type: u8,
        proposed_tap_rate: u8,
        ctx: &mut TxContext,
    ) {
        // for address_list, we will call oracles to get the list of addresses directly,
        // so don't have to pass in address_list as a parameter to prevent spoofing.
        let proposal = Proposal {
            id: object::new(ctx),
            type,
            proposed_tap_rate,
            for: Vote { holders: vec_set::empty<address>(), count: 0 },
            against: Vote { holders: vec_set::empty<address>(), count: 0 },
            abstain: Vote { holders: vec_set::empty<address>(), count: 0 },
            no_vote: Vote { holders: address_list, count: c9_balance::supply_value(ino::get_supply(project)) },
        };

        // To comment out upon deployment
        // assert!(vec_set::size(&proposal.no_vote.holders) == vec_set::size(&_address_list), 1);
        // assert!(proposal.no_vote.count == ino::get_collection_currentSupply(_collection), 1);

        dict::add(&mut governance.proposal_data,object::uid_to_address(&proposal.id), proposal);
    }

    /// hardcoded vote count update until oracle is up
    public fun vote_proposal(proposal: &mut Proposal, vote_choice: u8, ctx: &mut TxContext) {
        let current_vote_choice: u8 = address_vote_choice(proposal, &tx_context::sender(ctx));
        assert!(current_vote_choice != vote_choice, EDuplicatedVotes);
        assert!(vote_choice != VNoVote, EUnauthorizedAction);
        // Updating previous votes
        if (current_vote_choice == VNoVote) {
            vec_set::remove(&mut proposal.no_vote.holders, &tx_context::sender(ctx));
            proposal.no_vote.count = proposal.no_vote.count - 1;
        } else if (current_vote_choice == VFor) {
            vec_set::remove(&mut proposal.for.holders, &tx_context::sender(ctx));
            proposal.for.count = proposal.for.count - 1;
        } else if (current_vote_choice == VAgainst) {
            vec_set::remove(&mut proposal.against.holders, &tx_context::sender(ctx));
            proposal.against.count = proposal.against.count - 1;
        } else if (current_vote_choice == VAbstain) {
            vec_set::remove(&mut proposal.abstain.holders, &tx_context::sender(ctx));
            proposal.abstain.count = proposal.abstain.count - 1;
        } else {
            abort EUnxpectedError
        };
        // Updating current votes
        if (vote_choice == VFor) {
            vec_set::insert(&mut proposal.no_vote.holders, tx_context::sender(ctx));
            proposal.for.count = proposal.for.count + 1;
        } else if (vote_choice == VAgainst) {
            vec_set::insert(&mut proposal.against.holders, tx_context::sender(ctx));
            proposal.against.count = proposal.against.count + 1;
        } else if (vote_choice == VAbstain) {
            vec_set::insert(&mut proposal.abstain.holders, tx_context::sender(ctx));
            proposal.abstain.count = proposal.abstain.count + 1;
        } else {
            abort ENonExistingAction
        }
    }

    public fun delegate(governance: &mut Governance, delegatee: address, ctx: &mut TxContext) {
        assert!(table::borrow(&governance.delegated_to, delegatee) == &delegatee, 0);
        assert!(table::borrow(&governance.delegated_to, tx_context::sender(ctx)) == &tx_context::sender(ctx), 0);
        table::remove(&mut governance.delegated_to, tx_context::sender(ctx));
        table::add(&mut governance.delegated_to, tx_context::sender(ctx), delegatee);
    }

    /// Getters
    public fun get_governance_proposals_length(governance: &Governance): u64 {
        dict::length(&governance.proposal_data)
    }

    public fun address_vote_choice(proposal: &Proposal, voter: &address): u8 {
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
}