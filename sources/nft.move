module crowd9_sc::nft {
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    // use crowd9_sc::ino::{Self, Project};
    use sui::balance::{Self, Balance};
    use sui::url::{Self, Url};
    use sui::vec_set::{Self, VecSet};
    use sui::sui::SUI;
    use sui::transfer::{Self};
    use sui::coin::{Self};
    use crowd9_sc::balance::{Self as c9_balance, NftSupply, NftBalance};
    friend crowd9_sc::ino;
    friend crowd9_sc::governance;
    friend crowd9_sc::ob;

    struct ProjectMetadata has store{
        name: vector<u8>,
        description: Url,
        creator: address,
        supply: NftSupply,
    }

    struct Project has key, store{
        id: UID,
        nft_ids: VecSet<ID>,
        last_withdrawn_timestamp: u64,
        tap_rate: u64,
        balance: Balance<SUI>,
        metadata: ProjectMetadata,
        owner_cap_id: ID,
        refund_info: Option<RefundInfo>,
    }

    struct RefundInfo has store{
        total_supply: u64,
        amount_to_refund: u64
    }

    struct Nft has key, store{
        id: UID,
        project_id: ID,
        balance: NftBalance
    }

    /// Create metadata for project
    public(friend) fun create_metadata(name: vector<u8>, description: vector<u8>, creator: address) : ProjectMetadata{
        ProjectMetadata {
            name,
            description: url::new_unsafe_from_bytes(description),
            creator,
            supply: c9_balance::create_supply()
        }
    }

    /// Getters for ProjectMetadata
    public fun project_creator(self: &ProjectMetadata): address{
        self.creator
    }

    /// Create project
    public(friend) fun create_project(id: UID, nft_ids: VecSet<ID>, tap_rate: u64, balance: Balance<SUI>, metadata: ProjectMetadata, owner_cap_id: ID): Project {
        let last_withdrawn_timestamp = 0; // TODO - Update timestamp once released
        Project {
            id, nft_ids, last_withdrawn_timestamp, tap_rate, balance, metadata, owner_cap_id, refund_info: option::none()
        }
    }

    /// Destroy an nft with value zero
    public(friend) fun destroy_zero(project: &mut Project, n: Nft){
        let Nft { id, project_id:_, balance} = n;
        vec_set::remove(&mut project.nft_ids, object::uid_as_inner(&id));
        object::delete(id);
        c9_balance::destroy_zero(balance);
    }

    /// Setters for project
    public(friend) fun adjust_tap_rate(project: &mut Project, adjusted_tap_rate: u64) {
        project.tap_rate = adjusted_tap_rate;
    }

    public(friend) fun mint(id: UID, project_id: ID, balance: NftBalance): Nft{
        Nft{ id, project_id, balance }
    }

    /// Getters
    public fun project_supply(project: &Project): &NftSupply{
        &project.metadata.supply
    }

    public(friend) fun project_supply_mut(metadata: &mut ProjectMetadata): &mut NftSupply{
        &mut metadata.supply
    }

    public fun project_balance(project: &Project): &Balance<SUI>{
        &project.balance
    }


    // === Balance <-> Nft accessors and type morphing ===

    /// Getter for balance's value
    public fun nft_value(self: &Nft): u64 {
        c9_balance::value(&self.balance)
    }

    /// Get immutable reference to the balance of an nft.
    public fun nft_balance(nft: &Nft): &NftBalance{
        &nft.balance
    }

    /// Get mutable reference to the balance of an nft.
    public(friend) fun balance_mut(nft: &mut Nft): &mut NftBalance{
        &mut nft.balance
    }

    /// Take an `Nft` worth of `value` from `Balance`
    /// Aborts if `value > balance.value`
    public(friend) fun take(project: &mut Project, balance: &mut NftBalance, value: u64, ctx: &mut TxContext): Nft {
        // TODO - check whether its working
        let project_id = object::id(project);
        let nft_ids = &mut project.nft_ids;
        let id = object::new(ctx);
        vec_set::insert(nft_ids, object::uid_to_inner(&id));
        Nft{ id, project_id, balance: c9_balance::split(balance, value)}
    }

    /// Consumes Nft `n` and add its value to `self`
    /// Aborts if `n.value + self.value > U64_MAX`
    public(friend) fun join(self: &mut Nft, n: Nft, project: &mut Project){
        let Nft { id, project_id:_, balance } = n;
        let nft_ids = &mut project.nft_ids;
        vec_set::remove(nft_ids, object::uid_as_inner(&id));
        object::delete(id);
        c9_balance::join(&mut self.balance, balance);
    }

    // TODO spec -> below is a draft
    // spec join {
    //     let before_val = self.balance.value;
    //     let post after_val = self.balance.value;
    //     ensures after_val == before_val + c.balance.value;
    //
    //     aborts_if before_val + c.balance.value > MAX_U64;
    // }

    public(friend) fun burn(project: &mut Project, nft: Nft): u64{
        let Nft {id, project_id:_, balance } = nft;
        let nft_supply = &mut project.metadata.supply;
        object::delete(id);
        c9_balance::decrease_supply(nft_supply, balance)
    }

    //      spec schema Burn<T> {
    //         cap: TreasuryCap<T>;
    //         c: Coin<T>;

    // let before_supply = cap.total_supply.value;
    // let post after_supply = cap.total_supply.value;
    //         ensures after_supply == before_supply - c.balance.value;

    //         aborts_if before_supply < c.balance.value;
    //     }

    //     spec burn {
    //         include Burn<T>;
    //     }


    public(friend) fun set_refund_info(project: &mut Project){
        let ri = RefundInfo {
            total_supply: c9_balance::supply_value(&project.metadata.supply),
            amount_to_refund: balance::value(&project.balance)
        };
        option::fill(&mut project.refund_info, ri);
    }

    public(friend) fun refund(project: &mut Project, accumulated_value: u64, sender: address, ctx: &mut TxContext){
        let ri = option::borrow(&project.refund_info);
        let refund_amount = ri.amount_to_refund * (accumulated_value / ri.total_supply);
        transfer::transfer(coin::take(&mut project.balance, refund_amount, ctx), sender);
    }

    public(friend) fun withdraw_funds(project: &mut Project, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        assert!(!is_refund_mode(project), 0); // TODO: change error code
        assert!(project.metadata.creator == sender, 1); //TODO: change error code
        let max_withdrawable = (tx_context::epoch(ctx) - project.last_withdrawn_timestamp) * project.tap_rate;
        transfer::transfer(coin::take(&mut project.balance, max_withdrawable, ctx), sender);
    }

    public(friend) fun is_refund_mode(project: &Project): bool{
        option::is_some(&project.refund_info)
    }

    // TODO WIP
    fun from_balance(project_id: ID, balance: NftBalance, ctx: &mut TxContext): Nft{
        Nft { id: object::new(ctx), project_id, balance }
    }


}