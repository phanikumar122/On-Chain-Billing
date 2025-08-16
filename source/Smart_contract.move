module pro_addr::decentralized_warranty_vault {
    use std::signer;
    use std::vector;
    use std::hash;
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use aptos_std::timestamp;

    // Error codes
    const E_INVALID_WARRANTY: u64 = 1;
    const E_UNAUTHORIZED_ACCESS: u64 = 2;
    const E_WARRANTY_EXPIRED: u64 = 3;
    const E_WARRANTY_NOT_FOUND: u64 = 4;
    const E_INVALID_TRANSFER: u64 = 5;

    // Struct for warranty information
    struct Warranty has store, drop, copy {
        product_id: String,
        product_name: String,
        seller_address: address,
        buyer_address: address,
        purchase_date: u64,
        warranty_end_date: u64,
        warranty_terms: String,
        receipt_hash: vector<u8>,
        is_active: bool,
        transfer_count: u64,
    }

    // Struct for warranty registry
    struct WarrantyRegistry has key {
        warranties: Table<vector<u8>, Warranty>,
        product_warranties: Table<String, vector<vector<u8>>>,
        user_warranties: Table<address, vector<vector<u8>>>,
    }

    // Struct for transfer history
    struct TransferHistory has store, drop, copy {
        from_address: address,
        to_address: address,
        transfer_date: u64,
        warranty_hash: vector<u8>,
    }

    // Initialize the warranty system
    public entry fun initialize(account: &signer) {
        let registry = WarrantyRegistry {
            warranties: table::new(),
            product_warranties: table::new(),
            user_warranties: table::new(),
        };
        move_to(account, registry);
    }

    // Register a new warranty
    public entry fun register_warranty(
        account: &signer,
        product_id: String,
        product_name: String,
        buyer_address: address,
        warranty_end_date: u64,
        warranty_terms: String,
        receipt_data: vector<u8>
    ) acquires WarrantyRegistry {
        let seller_address = signer::address_of(account);
        let purchase_date = timestamp::now_seconds();
        
        // Create receipt hash
        let receipt_hash = hash::sha3_256(receipt_data);
        
        // Create warranty hash
        let warranty_hash_input = vector::empty<u8>();
        vector::append(&mut warranty_hash_input, bcs::to_bytes(&product_id));
        vector::append(&mut warranty_hash_input, bcs::to_bytes(&seller_address));
        vector::append(&mut warranty_hash_input, bcs::to_bytes(&buyer_address));
        vector::append(&mut warranty_hash_input, bcs::to_bytes(&purchase_date));
        vector::append(&mut warranty_hash_input, bcs::to_bytes(&warranty_end_date));
        
        let warranty_hash = hash::sha3_256(warranty_hash_input);
        
        // Create warranty
        let warranty = Warranty {
            product_id,
            product_name,
            seller_address,
            buyer_address,
            purchase_date,
            warranty_end_date,
            warranty_terms,
            receipt_hash,
            is_active: true,
            transfer_count: 0,
        };
        
        // Store warranty
        let registry = borrow_global_mut<WarrantyRegistry>(@d_warranty);
        table::add(&mut registry.warranties, warranty_hash, warranty);
        
        // Add to product warranties
        if (!table::contains(&registry.product_warranties, product_id)) {
            table::add(&mut registry.product_warranties, product_id, vector::empty());
        };
        let product_warranties = table::borrow_mut(&mut registry.product_warranties, product_id);
        vector::push_back(product_warranties, warranty_hash);
        
        // Add to user warranties
        if (!table::contains(&registry.user_warranties, buyer_address)) {
            table::add(&mut registry.user_warranties, buyer_address, vector::empty());
        };
        let user_warranties = table::borrow_mut(&mut registry.user_warranties, buyer_address);
        vector::push_back(user_warranties, warranty_hash);
    }

    // Transfer warranty to new owner
    public entry fun transfer_warranty(
        account: &signer,
        warranty_hash: vector<u8>,
        new_owner: address
    ) acquires WarrantyRegistry {
        let current_owner = signer::address_of(account);
        
        let registry = borrow_global_mut<WarrantyRegistry>(@d_warranty);
        
        // Check warranty exists
        assert!(table::contains(&registry.warranties, warranty_hash), E_WARRANTY_NOT_FOUND);
        
        let warranty = table::borrow_mut(&mut registry.warranties, warranty_hash);
        
        // Check current owner
        assert!(warranty.buyer_address == current_owner, E_UNAUTHORIZED_ACCESS);
        
        // Check warranty is active and not expired
        let current_time = timestamp::now_seconds();
        assert!(warranty.is_active && current_time <= warranty.warranty_end_date, E_WARRANTY_EXPIRED);
        
        // Remove from old owner's list
        let old_owner_warranties = table::borrow_mut(&mut registry.user_warranties, current_owner);
        let index = 0;
        let found = false;
        while (index < vector::length(old_owner_warranties)) {
            if (*vector::borrow(old_owner_warranties, index) == warranty_hash) {
                vector::remove(old_owner_warranties, index);
                found = true;
                break;
            };
            index = index + 1;
        };
        assert!(found, E_WARRANTY_NOT_FOUND);
        
        // Add to new owner's list
        if (!table::contains(&registry.user_warranties, new_owner)) {
            table::add(&mut registry.user_warranties, new_owner, vector::empty());
        };
        let new_owner_warranties = table::borrow_mut(&mut registry.user_warranties, new_owner);
        vector::push_back(new_owner_warranties, warranty_hash);
        
        // Update warranty
        warranty.buyer_address = new_owner;
        warranty.transfer_count = warranty.transfer_count + 1;
    }

    // Verify warranty validity
    public fun verify_warranty(
        warranty_hash: vector<u8>
    ): bool acquires WarrantyRegistry {
        let registry = borrow_global<WarrantyRegistry>(@d_warranty);
        
        if (!table::contains(&registry.warranties, warranty_hash)) {
            return false;
        };
        
        let warranty = table::borrow(&registry.warranties, warranty_hash);
        let current_time = timestamp::now_seconds();
        
        warranty.is_active && current_time <= warranty.warranty_end_date
    }

    // Get warranty details
    public fun get_warranty_details(
        warranty_hash: vector<u8>
    ): Warranty acquires WarrantyRegistry {
        let registry = borrow_global<WarrantyRegistry>(@d_warranty);
        *table::borrow(&registry.warranties, warranty_hash)
    }

    // Get warranties for a user
    public fun get_user_warranties(
        user: address
    ): vector<Warranty> acquires WarrantyRegistry {
        let registry = borrow_global<WarrantyRegistry>(@d_warranty);
        
        if (!table::contains(&registry.user_warranties, user)) {
            return vector::empty();
        };
        
        let warranty_hashes = table::borrow(&registry.user_warranties, user);
        let warranties = vector::empty<Warranty>();
        
        let i = 0;
        while (i < vector::length(warranty_hashes)) {
            let hash = *vector::borrow(warranty_hashes, i);
            let warranty =<ask_followup_question>