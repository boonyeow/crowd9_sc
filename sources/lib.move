module crowd9_sc::lib {
    const EZeroDivision: u64 = 0;

    public fun mul_div_u64(a: u64, b: u64, c: u64): u64 {
        assert!(c != 0, EZeroDivision);
        ((a as u128) * (b as u128) / (c as u128) as u64)
    }
}