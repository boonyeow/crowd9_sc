module crowd9_sc::dict{
    use sui::object::{Self, UID};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field as field;

    // Attempted to destroy a non-empty dict
    const EDictNotEmpty: u64 = 0;

    struct Dict<K: copy + drop + store, phantom V: store> has key, store {
        id: UID,
        keys: VecSet<K>,
    }

    /// Creates a new, empty dict
    public fun new <K: copy + drop + store, V:store>(ctx: &mut TxContext): Dict<K,V>{
        Dict {
            id: object::new(ctx),
            keys: vec_set::empty<K>(),
        }
    }

    /// Adds a key-value pair to the table `dict: &mut Dict<K, V>`
    /// Aborts with `sui::dynamic_field::EFieldAlreadyExists` if the dict already has an entry with
    /// that key `k: K`.
    public fun add<K: copy + drop + store, V: store>(dict: &mut Dict<K, V>, k: K, v: V) {
        field::add(&mut dict.id, k, v);
        vec_set::insert(&mut dict.keys, k);
    }

    /// Immutable borrows the value associated with the key in the dict `dict: &Dict<K, V>`.
    /// Aborts with `sui::dynamic_field::EFieldDoesNotExist` if the table does not have an entry with
    /// that key `k: K`.
    public fun borrow<K: copy + drop + store, V: store>(dict: &Dict<K, V>, k: K): &V {
        field::borrow(&dict.id, k)
    }

    /// Mutably borrows the value associated with the key in the dict `dict: &mut Dict<K, V>`.
    /// Aborts with `sui::dynamic_field::EFieldDoesNotExist` if the table does not have an entry with
    /// that key `k: K`.
    public fun borrow_mut<K: copy + drop + store, V: store>(dict: &mut Dict<K, V>, k: K): &mut V {
        field::borrow_mut(&mut dict.id, k)
    }

    /// Mutably borrows the key-value pair in the table `dict: &mut Dict<K, V>` and returns the value.
    /// Aborts with `sui::dynamic_field::EFieldDoesNotExist` if the dict does not have an entry with
    /// that key `k: K`.
    public fun remove<K: copy + drop + store, V: store>(dict: &mut Dict<K, V>, k: K): V {
        let v = field::remove(&mut dict.id, k);
        vec_set::remove(&mut dict.keys, &k);
        v
    }

    /// Returns true if there is a value associated with the key `k: K` in dict `dict: &Dict<K, V>`
    public fun contains<K: copy + drop + store, V: store>(dict: &Dict<K, V>, k: K): bool {
        field::exists_with_type<K, V>(&dict.id, k)
    }

    /// Returns the size of the table, the number of key-value pairs
    public fun length<K: copy + drop + store, V: store>(dict: &Dict<K, V>): u64 {
        vec_set::size(&dict.keys)
    }

    /// Returns true if the dict is empty (if `length` returns `0`)
    public fun is_empty<K: copy + drop + store, V: store>(dict: &Dict<K, V>): bool {
        vec_set::size(&dict.keys) == 0
    }

    /// Destroys an empty dict
    /// Aborts with `EDictNotEmpty` if the table still contains values
    public fun destroy_empty<K: copy + drop + store, V: store>(dict: Dict<K, V>) {
        let Dict { id, keys } = dict;
        assert!(vec_set::size(&keys) == 0, EDictNotEmpty);
        object::delete(id)
    }

    /// Drop a possibly non-empty dict.
    /// Usable only if the value type `V` has the `drop` ability
    public fun drop<K: copy + drop + store, V: drop + store>(dict: Dict<K, V>) {
        let Dict { id, keys: _ } = dict;
        object::delete(id)
    }

    /// Return a vector of keys in the dictionary
    public fun get_keys<K: copy + drop + store, V: store>(dict: &Dict<K, V>): vector<K>{
        vec_set::into_keys(dict.keys)
    }

    use std::vector;
    // Return a copy of dictionary only if value can be copied / dropped
    public fun duplicate<K: copy + drop + store, V: copy + drop + store>(dict: &Dict<K,V>, ctx: &mut TxContext): Dict<K, V>{
        let duplicated_dict = new(ctx);
        let keys = get_keys(dict);
        while(!vector::is_empty(&keys)){
            let key = vector::pop_back(&mut keys);
            add(&mut duplicated_dict, key, *borrow(dict, key));
        };
        duplicated_dict
    }
}