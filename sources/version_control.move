/// Version Control - Package Version Management
/// 
/// This module manages package versioning and compatibility checks
/// for the bridge system upgrade process.

module bridge_safe::bridge_version_control;

use sui::vec_set::VecSet;

/// The current version of the package.
const VERSION: u64 = 1;

// === Errors ===
const EIncompatibleVersion: u64 = 0;

// === Methods ===

/// Gets the current package's version.
public fun current_version(): u64 {
    VERSION
}

/// [Package private] Asserts that an object's compatible version set is
/// compatible with the current package's version.
public(package) fun assert_object_version_is_compatible_with_package(
    compatible_versions: VecSet<u64>,
) {
    assert!(compatible_versions.contains(&current_version()), EIncompatibleVersion);
}
