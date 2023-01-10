module crowd9_sc::governance {
    use crowd9_sc::ino::{Self, Project};
    use crowd9_sc::balance::{Self as c9_balance};
    use crowd9_sc::dict::{Self, Dict};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    // use sui::sui::SUI;
    // use sui::coin::{Self};

    /// ======= Constants =======
    // Status Codes
    const EDuplicatedVotes: u64 = 001;
    const EUnauthorizedUser: u64 = 002;
    const EInvalidAction: u64 = 003;
    const ENonExistingAction: u64 = 004;
    const EUnxpectedError: u64 = 005;
    const ERepeatedDelegation: u64 = 006;
    const EInvalidDelegatee: u64 = 007;

    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const VAgainst: u8 = 0;
    const VFor: u8 = 1;
    const VAbstain: u8 = 2;
    const VNoVote: u8 = 3;

    const SActive:u8 = 0;
    const SSuccess:u8 = 1;
    const SFailure:u8 = 2;


    struct Governance has key {
        id: UID,
        project_id: ID,
        start_timestamp: u64,
        proposal_data: Dict<address, Proposal>,
        delegated_to: Table<address, address>,
    }

    struct Proposal has key, store {
        id: UID,
        type: u8,
        status: u8,
        proposed_tap_rate: u64,
        for: Vote,
        against: Vote,
        abstain: Vote,
        no_vote: Vote,
        voting_power: Dict<address, u64>
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
        voting_power: Dict<address, u64>,
        project: &Project,
        governance: &mut Governance,
        type: u8,
        proposed_tap_rate: u64,
        ctx: &mut TxContext,
    ) {
        // for address_list, we will call oracles to get the list of addresses directly,
        // so don't have to pass in address_list as a parameter to prevent spoofing.
        let proposal = Proposal {
            id: object::new(ctx),
            type,
            status: SActive,
            proposed_tap_rate,
            for: Vote { holders: vec_set::empty<address>(), count: 0 },
            against: Vote { holders: vec_set::empty<address>(), count: 0 },
            abstain: Vote { holders: vec_set::empty<address>(), count: 0 },
            no_vote: Vote { holders: address_list, count: c9_balance::supply_value(ino::get_supply(project)) },
            voting_power,
        };
        dict::add(&mut governance.proposal_data,object::uid_to_address(&proposal.id), proposal);
    }

    public fun vote_proposal(proposal: &mut Proposal, vote_choice: u8, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx); //
        let current_vote_choice: u8 = address_vote_choice(proposal, &sender);
        let voting_power = dict::borrow(&proposal.voting_power, sender);
        assert!(current_vote_choice != vote_choice, EDuplicatedVotes);
        assert!(vote_choice != VNoVote, EInvalidAction);
        assert!(proposal.status == SActive, EInvalidAction);
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
            abort EUnxpectedError
        };
        // Updating current votes
        if (vote_choice == VFor) {
            vec_set::insert(&mut proposal.no_vote.holders, sender);
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

    // this one need check refund how its done
    public fun end_proposal(proposal: &mut Proposal, project: &mut Project) {
        assert!(proposal.type == SActive, EInvalidAction);
        // let total_casted_votes = tally_votes(proposal);
        if (proposal.for.count > proposal.against.count) {
            proposal.status = SSuccess;
            if (proposal.type == PAdjustment) {
                ino::adjust_tap_rate(project, proposal.proposed_tap_rate);
            }
            // } else if (proposal.type == PRefund){
            //
            // }
        } else {
            proposal.status = SFailure;
        };
    }

    public fun delegate(governance: &mut Governance, delegatee: address, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(table::borrow(&governance.delegated_to, sender) != &delegatee, ERepeatedDelegation);
        if (sender != delegatee) {
            assert!(table::borrow(&governance.delegated_to, delegatee) == &delegatee, EInvalidDelegatee);
        };
        *table::borrow_mut(&mut governance.delegated_to, sender) = delegatee;
    }

    /// Helper Functions
    fun tally_votes(proposal: &mut Proposal): u64 {
        let for_holders = vec_set::into_keys(proposal.for.holders);
        let against_holders = vec_set::into_keys(proposal.against.holders);
        let abstain_holders = vec_set::into_keys(proposal.abstain.holders);

        while(!vector::is_empty(&for_holders)){
            let address = vector::pop_back(&mut for_holders);
            let voting_power = dict::borrow(&proposal.voting_power, address);
            proposal.for.count = proposal.for.count + *voting_power;
        };
        while(!vector::is_empty(&against_holders)){
            let address = vector::pop_back(&mut against_holders);
            let voting_power = dict::borrow(&proposal.voting_power, address);
            proposal.against.count = proposal.against.count + *voting_power;
        };
        while(!vector::is_empty(&abstain_holders)){
            let address = vector::pop_back(&mut abstain_holders);
            let voting_power = dict::borrow(&proposal.voting_power, address);
            proposal.abstain.count = proposal.abstain.count + *voting_power;
        };
        let total_votes_casted: u64 = proposal.for.count + proposal.against.count + proposal.abstain.count;
        total_votes_casted
    }

    /// Getters
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