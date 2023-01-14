module crowd9_sc::nft {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    // use crowd9_sc::ino::{Self, Project};
    use sui::balance::{/*Self,*/ Balance};
    use sui::url::{Self, Url};
    use sui::vec_set::{Self, VecSet};
    use sui::sui::SUI;
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
        owner_cap_id: ID
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
            id, nft_ids, last_withdrawn_timestamp, tap_rate, balance, metadata, owner_cap_id
        }
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


    // TODO WIP
    fun from_balance(project_id: ID, balance: NftBalance, ctx: &mut TxContext): Nft{
        Nft { id: object::new(ctx), project_id, balance }
    }
}