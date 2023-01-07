#[test_only]
module crowd9_sc::dict_tests {
    use crowd9_sc::dict::{Self, add, contains, borrow, borrow_mut, remove};
    use sui::test_scenario as ts;

    #[test]
    fun simple_all_functions(){
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new(ts::ctx(&mut scenario));
        // add fields
        add(&mut dict, b"hello", 0);
        add(&mut dict, b"goodbye", 1);
        // check they exist
        assert!(contains(&dict, b"hello"), 0);
        assert!(contains(&dict, b"goodbye"), 0);
        // check the values
        assert!(*borrow(&dict, b"hello") == 0, 0);
        assert!(*borrow(&dict, b"goodbye") == 1, 0);
        // mutate them
        *borrow_mut(&mut dict, b"hello") = *borrow(&dict, b"hello") * 2;
        *borrow_mut(&mut dict, b"goodbye") = *borrow(&dict, b"goodbye") * 2;
        // check the new value
        assert!(*borrow(&dict, b"hello") == 0, 0);
        assert!(*borrow(&dict, b"goodbye") == 2, 0);
        // remove the value and check it
        assert!(remove(&mut dict, b"hello") == 0, 0);
        assert!(remove(&mut dict, b"goodbye") == 2, 0);
        // verify that they are not there
        assert!(!contains(&dict, b"hello"), 0);
        assert!(!contains(&dict, b"goodbye"), 0);

        dict::destroy_empty(dict);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldAlreadyExists)]
    fun add_duplicate() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new(ts::ctx(&mut scenario));
        add(&mut dict, b"hello", 0);
        add(&mut dict, b"hello", 1);
        abort 42
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun borrow_missing() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        borrow(&dict, 0);
        abort 42
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun borrow_mut_missing() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        borrow_mut(&mut dict, 0);
        abort 42
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun remove_missing() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        remove(&mut dict, 0);
        abort 42
    }

    #[test]
    #[expected_failure(abort_code = crowd9_sc::dict::EDictNotEmpty)]
    fun destroy_non_empty() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        add(&mut dict, 0, 0);
        dict::destroy_empty(dict);
        ts::end(scenario);
    }

    #[test]
    fun sanity_check_contains() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        assert!(!contains(&mut dict, 0), 0);
        add(&mut dict, 0, 0);
        assert!(contains<u64, u64>(&mut dict, 0), 0);
        assert!(!contains<u64, u64>(&mut dict, 1), 0);
        ts::end(scenario);
        dict::drop(dict);
    }

    #[test]
    fun sanity_check_drop() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        add(&mut dict, 0, 0);
        assert!(dict::length(&dict) == 1, 0);
        ts::end(scenario);
        dict::drop(dict);
    }

    #[test]
    fun sanity_check_size() {
        let sender = @0x0;
        let scenario = ts::begin(sender);
        let dict = dict::new<u64, u64>(ts::ctx(&mut scenario));
        assert!(dict::is_empty(&dict), 0);
        assert!(dict::length(&dict) == 0, 0);
        add(&mut dict, 0, 0);
        assert!(!dict::is_empty(&dict), 0);
        assert!(dict::length(&dict) == 1, 0);
        add(&mut dict, 1, 0);
        assert!(!dict::is_empty(&dict), 0);
        assert!(dict::length(&dict) == 2, 0);
        ts::end(scenario);
        dict::drop(dict);
    }
}
