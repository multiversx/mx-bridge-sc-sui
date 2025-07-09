module bridge_safe::utils;

use std::ascii;
use std::type_name;

/// Returns the type name as bytes for use as storage keys
public fun type_name_bytes<T>(): vector<u8> {
    let type_name = type_name::get<T>();
    let type_name_string = type_name::into_string(type_name);
    ascii::into_bytes(type_name_string)
}
