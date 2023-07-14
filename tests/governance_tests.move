#[test_only]
module crowd9_sc::governance_tests {
    use std::debug;
    use sui::sui::SUI;
    use std::vector;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self};
    use sui::transfer::{Self};
    use crowd9_sc::lib::{Self};

    #[test]
    fun test_append() {
        let vector1 = vector[@123, @456, @789];
        let vector2 = vector[@111, @222, @333];

        vector::append(&mut vector1, vector2);
        // debug::print(&vector1);
        // debug::print(&vector2);

        let scenario_val = ts::begin(@0xABC);
        let scenario = &mut scenario_val;
        let ctx = ts::ctx(scenario);
        let v3 = vector[object::new(ctx), object::new(ctx), object::new(ctx)];
        let v4 = vector[object::new(ctx), object::new(ctx), object::new(ctx)];
        vector::append(&mut v3, v4);
        // debug::print(&v3);

        while (!vector::is_empty(&v3)) {
            let id = vector::pop_back(&mut v3);
            object::delete(id);
            // debug::print(&1);
        };
        vector::destroy_empty(v3);
        ts::end(scenario_val);
    }


    struct Vault has key, store {
        id: UID,
        balance: Balance<SUI>,
        tap_rate: u64,
        last_withdrawn_timestamp: u64,
        refund_amount: u64,
        total_supply_value: u64,
        frozen_balance: Balance<ABC>,
    }

    struct ABC has drop {}

    #[test]
    fun division_test() {
        let sender = @0xB;
        let scenario = ts::begin(sender);
        let scenario_val = &mut scenario;

        ts::next_tx(scenario_val, sender);
        // 1000000000 mist = 1 sui
        let scale_factor = 1000000000;
        let vault = Vault {
            id: object::new(ts::ctx(scenario_val)),
            balance: balance::create_for_testing<SUI>(103 * scale_factor),
            tap_rate: 10000000,
            last_withdrawn_timestamp: 0,
            refund_amount: 103 * scale_factor, // amount left in sui
            total_supply_value: 1000 * scale_factor,
            frozen_balance: balance::zero<ABC>()
        };

        ts::next_tx(scenario_val, sender);
        let coins = coin::mint_for_testing<ABC>(1000000000, ts::ctx(scenario_val));
        let coin_value = coin::value(&coins);
        let _share1 = coin_value / vault.total_supply_value * balance::value(&vault.balance);
        let _share2 = (((coin_value as u256) * (balance::value(
            &vault.balance
        ) as u256) / (vault.total_supply_value as u256)) as u64);

        let _share3 = lib::mul_div_u64(coin_value, balance::value(&vault.balance), vault.total_supply_value);
        // debug::print(&share3);
        // debug::print(&share1);
        // debug::print(&share2);

        // coin_value / total_supply * refund_amount
        // coin_value * refund_amount / total_supply
        // proportion = coin_value / total_supply
        // debug::print(&lib::mul_div_u64(1, 600, 10000)); // share = coin_value / total_supply * balance
        // debug::print(&lib::mul_div_u64(10, 600, 10000));
        // debug::print(&lib::mul_div_u64(50, 600, 10000));
        // debug::print(&lib::mul_div_u64(100, 600, 10000));
        // debug::print(&lib::mul_div_u64(1000, 600, 10000));

        coin::burn_for_testing(coins);
        transfer::public_freeze_object(vault);
        ts::end(scenario);
    }

    #[test]
    fun vector_test() {
        let vec_test = vector[0, 1, 2, 3, 4];
        debug::print(&vec_test);

        let last_item = *vector::borrow(&vec_test, vector::length(&vec_test) - 1);
        debug::print(&last_item);

        while (last_item != 0) {
            let _ = vector::pop_back(&mut vec_test);
            last_item = *vector::borrow(&vec_test, vector::length(&vec_test) - 1);
            debug::print(&last_item)
        };
        debug::print(&vec_test)
    }
}