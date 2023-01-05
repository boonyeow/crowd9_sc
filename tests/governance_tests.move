#[test_only]
module crowd9_sc::governance_tests {
    use crowd9_sc::ino::{Self, Campaign, OwnerCap};
    use crowd9_sc::governance::{Self, Governance};
    // use sui::transfer;
    // use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    // use sui::object::{Self};
    // use sui::tx_context::{TxContext};
    use sui::sui::SUI;
    use sui::coin::{Self};
    use sui::test_scenario::{Self, Scenario};
    use crowd9_sc::ino::Campaign;
    // use std::debug;

    /// Constants
    // Status Codes
    const PRefund: u8 = 0;
    const PAdjustment: u8 = 1;

    const ADMIN: address = @0xCAFE;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xAAAB;

    // fun init_campaign(
    //     _name: vector<u8>,
    //     _description: vector<u8>,
    //     _funding_goal: u64,
    //     _price_per_nft: u64,
    //     _duration: u64,
    //     _proposed_tape_rate: u64,
    //     _user: address,
    //     _scenario: &mut Scenario
    // ): Campaign {
    //     test_scenario::next_tx(_scenario, _user);
    //     let ctx = test_scenario::ctx(_scenario);
    //     ino::create_campaign(_name, _description, _funding_goal, _price_per_nft, _duration, _proposed_tape_rate, ctx);
    //
    //     test_scenario::next_tx(_scenario, _user);
    //     test_scenario::take_shared<Campaign>(_scenario)
    // }
    //
    // fun start_campaign(
    //     _campaign: &mut Campaign,
    //     _owner_cap: &OwnerCap,
    //     _user: address,
    //     _scenario: &mut Scenario
    // ) {
    //     test_scenario::next_tx(_scenario, _user);
    //     let ctx = test_scenario::ctx(_scenario);
    //     ino::start_campaign(_campaign, _owner_cap, ctx)
    // }
    //
    // fun mint_nft<COIN>(_campaign_obj: &mut NftCollection<COIN>, _qty: u64, _user: address, _scenario: &mut Scenario) {
    //     test_scenario::next_tx(_scenario, _user);
    //     let ctx = test_scenario::ctx(_scenario);
    //     token::temp_mint(_campaign_obj, coin::mint_for_testing<SUI>(_qty, ctx));
    // }
    //
    // fun init_governance<COIN>(
    //     _campaign_obj: &mut NftCollection<COIN>,
    //     _start_timestamp: u64,
    //     _user: address,
    //     _scenario: &mut Scenario,
    // ): Governance {
    //     test_scenario::next_tx(_scenario, _user);
    //     let ctx = test_scenario::ctx(_scenario);
    //     governance::create_governance(_campaign_obj, 0000, ctx);
    //
    //     test_scenario::next_tx(_scenario, _user);
    //     test_scenario::take_shared<Governance>(_scenario)
    // }
    //
    // fun create_proposal<COIN>(
    //     _address_list: VecSet<address>,
    //     _campaign_obj: &NftCollection<COIN>,
    //     _governance: &mut Governance,
    //     _type: u8,
    //     _proposed_rate: u8,
    //     _user: address,
    //     _scenario: &mut Scenario,
    // ){
    //     test_scenario::next_tx(_scenario, _user);
    //     let ctx = test_scenario::ctx(_scenario);
    //     governance::create_proposal(_address_list, _campaign_obj, _governance, _type, _proposed_rate, ctx);
    // }
    //
    // // #[test]
    // // public fun create_proposal_test() {
    // //     let scenario_val = test_scenario::begin(ADMIN);
    // //     let scenario = &mut scenario_val;
    // //
    // //     let campaign_obj = init_campaign(b"The One", b"Description", 1000, 10, 1, 20, ALICE, scenario);
    // //     mint_nft(&mut campaign_obj, 2, ALICE, scenario);
    // //     mint_nft(&mut campaign_obj, 5, BOB, scenario);
    // //     let governance_obj = init_governance(&mut campaign_obj, 0000, ALICE, scenario);
    // //
    // //     let address_list = vec_set::empty();
    // //     vec_set::insert(&mut address_list, ALICE);
    // //     vec_set::insert(&mut address_list, BOB);
    // //     create_proposal(address_list, &campaign_obj, &mut governance_obj, PRefund, 5, ALICE, scenario);
    // //     assert!(governance::get_governance_proposals_length(&governance_obj) == 1, 1);
    // //     create_proposal(address_list, &campaign_obj, &mut governance_obj, PAdjustment, 3, BOB, scenario);
    // //     assert!(governance::get_governance_proposals_length(&governance_obj) == 2, 1);
    // //
    // //     test_scenario::return_shared(campaign_obj);
    // //     test_scenario::return_shared(governance_obj);
    // //     test_scenario::end(scenario_val);
    // // }
}
