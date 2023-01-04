#[test_only]
module crowd9_sc::time_oracle_tests {
    use sui::test_scenario::{Self, Scenario};
    use crowd9_sc::time_oracle;
    // use sui::object;

    const ADMIN:address = @0xCAFE;
    const ALICE:address = @0xAAAA;
    const BOB:address = @0xAAAB;
    const CAROL:address = @0xAAAC;

    entry fun init_time_oracle(scenario: &mut Scenario){
        test_scenario::next_tx(scenario, ADMIN);
        time_oracle::test_init(test_scenario::ctx(scenario));
    }

    // #[test]
    // fun hello_world(){
    //     let scenario_val = test_scenario::begin(ADMIN);
    //     let scenario = &mut scenario_val;
    //     init_time_oracle(scenario);
    // }
}
