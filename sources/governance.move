module crowd9_sc::governance {
    use crowd9_sc::ino::{Self, Project};
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
        proposal_ids: VecSet<address>,
        proposal_data: Table<address, Proposal>
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
        _project: &mut Project,
        _start_timestamp: u64,
        ctx: &mut TxContext
    ) {
        let governance = Governance {
            id: object::new(ctx),
            project_id: object::id(_project),
            start_timestamp: _start_timestamp,
            proposal_ids: vec_set::empty<address>(),
            proposal_data: table::new(ctx),
        };
        // ino::set_stopwatch(collection, ctx);
        transfer::share_object(governance);
    }

    public fun create_proposal(
        _address_list: VecSet<address>,
        _project: &Project,
        _governance: &mut Governance,
        _type: u8,
        _proposed_tap_rate: u8,
        ctx: &mut TxContext,
    ) {
        // for address_list, we will call oracles to get the list of addresses directly,
        // so don't have to pass in address_list as a parameter to prevent spoofing.
        let proposal = Proposal {
            id: object::new(ctx),
            type: _type,
            proposed_tap_rate: _proposed_tap_rate,
            for: Vote { holders: vec_set::empty<address>(), count: 0 },
            against: Vote { holders: vec_set::empty<address>(), count: 0 },
            abstain: Vote { holders: vec_set::empty<address>(), count: 0 },
            no_vote: Vote { holders: _address_list, count: ino::get_campaign_total_NFT_supply(_project) },
        };

        // To comment out upon deployment
        // assert!(vec_set::size(&proposal.no_vote.holders) == vec_set::size(&_address_list), 1);
        // assert!(proposal.no_vote.count == ino::get_collection_currentSupply(_collection), 1);

        vec_set::insert(&mut _governance.proposal_ids, object::uid_to_address(&proposal.id));
        table::add(&mut _governance.proposal_data, object::uid_to_address(&proposal.id), proposal);

    }

    /// hardcoded vote count update until oracle is up
    public fun vote_proposal(_proposal: &mut Proposal, _vote_choice: u8, ctx: &mut TxContext) {
        let current_vote_choice: u8 = address_vote_choice(_proposal, &tx_context::sender(ctx));
        assert!(current_vote_choice != _vote_choice, EDuplicatedVotes);
        assert!(_vote_choice != VNoVote, EUnauthorizedAction);
        // Updating previous votes
        if (current_vote_choice == VNoVote) {
            vec_set::remove(&mut _proposal.no_vote.holders, &tx_context::sender(ctx));
            _proposal.no_vote.count = _proposal.no_vote.count - 1;
        } else if (current_vote_choice == VFor) {
            vec_set::remove(&mut _proposal.for.holders, &tx_context::sender(ctx));
            _proposal.for.count = _proposal.for.count - 1;
        } else if (current_vote_choice == VAgainst) {
            vec_set::remove(&mut _proposal.against.holders, &tx_context::sender(ctx));
            _proposal.against.count = _proposal.against.count - 1;
        } else if (current_vote_choice == VAbstain) {
            vec_set::remove(&mut _proposal.abstain.holders, &tx_context::sender(ctx));
            _proposal.abstain.count = _proposal.abstain.count - 1;
        } else {
            abort EUnxpectedError
        };
        // Updating current votes
        if (_vote_choice == VFor) {
            vec_set::insert(&mut _proposal.no_vote.holders, tx_context::sender(ctx));
            _proposal.for.count = _proposal.for.count + 1;
        } else if (_vote_choice == VAgainst) {
            vec_set::insert(&mut _proposal.against.holders, tx_context::sender(ctx));
            _proposal.against.count = _proposal.against.count + 1;
        } else if (_vote_choice == VAbstain) {
            vec_set::insert(&mut _proposal.abstain.holders, tx_context::sender(ctx));
            _proposal.abstain.count = _proposal.abstain.count + 1;
        } else {
            abort ENonExistingAction
        }
    }

    /// Getters
    public fun get_governance_proposals_length(_governance_obj: &Governance): u64 {
        vec_set::size(&_governance_obj.proposal_ids)
    }

    public fun address_vote_choice(_proposal: &Proposal, _voter: &address): u8 {
        if (vec_set::contains(&_proposal.no_vote.holders, _voter)) {
            return VNoVote
        } else if (vec_set::contains(&_proposal.for.holders, _voter)) {
            return VFor
        } else if (vec_set::contains(&_proposal.against.holders, _voter)) {
            return VAgainst
        } else if (vec_set::contains(&_proposal.abstain.holders, _voter)) {
            return VAbstain
        } else {
            abort EUnauthorizedUser
        }
    }
}