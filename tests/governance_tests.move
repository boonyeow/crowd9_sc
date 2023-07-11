// #[test_only]
// module crowd9_sc::governance_tests {
//     use std::debug;
//     use std::vector;
//     use sui::object::{Self};
//     use sui::test_scenario::{Self as ts};
//
//     #[test]
//     fun test_append() {
//         let vector1 = vector[@123, @456, @789];
//         let vector2 = vector[@111, @222, @333];
//
//         vector::append(&mut vector1, vector2);
//         debug::print(&vector1);
//         debug::print(&vector2);
//
//         let scenario_val = ts::begin(@0xABC);
//         let scenario = &mut scenario_val;
//         let ctx = ts::ctx(scenario);
//         let v3 = vector[object::new(ctx), object::new(ctx), object::new(ctx)];
//         let v4 = vector[object::new(ctx), object::new(ctx), object::new(ctx)];
//         vector::append(&mut v3, v4);
//         debug::print(&v3);
//
//         while (!vector::is_empty(&v4)) {
//             let id = vector::pop_back(&mut v3);
//             object::delete(id);
//             debug::print(&1);
//         };
//         vector::destroy_empty(v3);
//         ts::end(scenario_val);
//     }
// }