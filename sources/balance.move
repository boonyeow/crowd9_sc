module crowd9_sc::balance {
    friend crowd9_sc::ino;
    friend crowd9_sc::nft;

    /// For when splitting Balance with 0 value
    const EZeroNotAllowed: u64 = 0;

    /// For when an overflow is happening on Supply operations.
    const EOverflow: u64 = 1;

    /// For when trying to withdraw more than there is.
    const ENotEnough: u64 = 2;

    /// For when trying to destroy a non-zero balance.
    const ENonZero: u64 = 3;

    struct NftSupply has store{
        value: u64
    }

    struct NftBalance has store{
        value: u64
    }

    public fun value(self: &NftBalance): u64 {
        self.value
    }

    public fun supply_value(supply: &NftSupply): u64 {
        supply.value
    }

    public(friend) fun create_supply(): NftSupply{
        NftSupply { value: 0 }
    }

    public(friend) fun increase_supply(self: &mut NftSupply, value: u64): NftBalance{
        assert!(value < (18446744073709551615u64 - self.value), EOverflow);
        self.value = self.value + value;
        NftBalance { value }
    }

    public(friend) fun decrease_supply(self: &mut NftSupply, balance: NftBalance): u64{
        let NftBalance { value } = balance;
        assert!(self.value >= value, EOverflow);
        self.value = self.value - value;
        value
    }

    // TODO Upon joining, to remove from nft_ids
    public(friend) fun join(self: &mut NftBalance, balance: NftBalance): u64{
        let NftBalance { value } = balance;
        self.value = self.value + value;
        self.value
    }

    spec join{
        ensures self.value == old(self.value) + balance.value;
        ensures result != self.value;
    }

    /// TODO Upon splitting, to add to nft_ids
    public(friend) fun split(self: &mut NftBalance, value: u64): NftBalance{
        assert!(self.value >= value, ENotEnough);
        assert!(value > 0, EZeroNotAllowed);
        self.value = self.value - value;
        NftBalance { value }
    }

    spec split{
        aborts_if self.value < value with ENotEnough;
        ensures self.value == old(self.value) - value;
        ensures result.value == value;
    }

    /// Destroy a zero `Balance`.
    public(friend) fun destroy_zero(balance: NftBalance){
        assert!(balance.value == 0, ENonZero);
        let NftBalance { value: _} = balance;
    }
}