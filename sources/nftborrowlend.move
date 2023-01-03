//! Contract to borrow or lend against NFTs
//! Created by Mokshya Protocol
module borrowlend::borrowlend
{
    use std::signer;
    use std::string::{String};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_token::token::{Self,check_collection_exists,balance_of,direct_transfer};
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::bcs::to_bytes;
    struct CollectionPool has key {
        //name of the collection which is whitelisted for nft borrow and lend 
        //the collection should be whitelisted by the module manager
        collection:String,
        //original creator
        creator:address,
        // similar like APY, daily Aptos to be PAID by the owner 
        dpr:u64,
        //maximum of number of days after which the NFT is defaulted
        days:u64,
        //this can be turned false to stop borrowing and lending from a  particular collection
        state:bool,
        //the current total amount of money offered to the collection 
        amount:u64,
        //treasury_cap
        treasury_cap:account::SignerCapability,
    }
    struct Lender has drop,key {
        //borrower
        borrower:address,
        //collection_name
        collection: String,
        //offerred amount
        offer_amount: u64,
        //time if the offer is accepted
        start_time:u64,
        //if the offer is accepted and fund is taken
        offered_made: bool,
        // similar like APY, daily Aptos to be PAID by the owner 
        dpr:u64,
        //days for default
        days:u64,
    }
    struct Borrower has drop,key {
        lender:address,
        //collection_name
        collection: String,
        //token name
        token_name:String,
        //property_version
        property_version: u64,
        //offerred amount
        receiver_amount: u64,
        //time if the offer is accepted
        start_time:u64,
        // similar like APY, daily Aptos to be PAID by the owner 
        dpr:u64,
        //days for default
        days:u64,
    }
    struct ResourceInfo has key {
        resource_map: SimpleMap< String,address>,
    }
    // ERRORS 
    const ENO_NO_COLLECTION:u64=0;
    const ENO_NOT_INITIATED:u64=1;
    const ENO_NO_STAKING:u64=2;
    const ENO_NO_TOKEN_IN_TOKEN_STORE:u64=3;
    const ENO_STOPPED:u64=4;
    const ENO_ALREADY_INITIATED:u64=5;
    const ENO_ADDRESS_MISMATCH:u64=6;
    const ENO_INSUFFICIENT_FUND:u64=7;
    const ENO_NOT_MODULE_CREATOR:u64=8;
    const ENO_COLLECTION_MISMATCH:u64=9;
    const ENO_LOAN_TAKEN:u64=10;
    const ENO_LOAN_NOT_TAKEN:u64=11;
    const ENO_DAYS_CROSSED:u64=12;

    //Functions    
    public entry fun initiate_create_pool(
        owner: &signer,
        creator_addr:address,
        collection_name:String, //the name of the collection owned by Creator 
        dpr:u64,//rate of payment,
        days:u64, //maximum loan days
    ) acquires ResourceInfo{
        let owner_addr = signer::address_of(owner);
        assert!(owner_addr==@borrowlend,ENO_NOT_MODULE_CREATOR);
        //verify the creator has the collection
        assert!(check_collection_exists(creator_addr,collection_name), ENO_NO_COLLECTION);

        let (collection_pool, collection_pool_cap) = account::create_resource_account(owner, to_bytes(&collection_name)); //resource account to store funds and data
        let  collection_pool_signer_from_cap = account::create_signer_with_capability(&collection_pool_cap);
        let collection_pool_address = signer::address_of(&collection_pool);
        assert!(!exists<CollectionPool>(collection_pool_address),ENO_ALREADY_INITIATED);
        create_add_resource_info(owner,collection_name,collection_pool_address);
        move_to<CollectionPool>(&collection_pool_signer_from_cap, CollectionPool{
        collection: collection_name,
        creator:creator_addr,
        dpr:dpr,
        days:days,
        state:true,
        amount:0, 
        treasury_cap:collection_pool_cap,
        });
    }
    public entry fun update_pool(
        owner: &signer,
        collection_name:String, //the name of the collection owned by Creator 
        dpr:u64,//rate of payment,
        days:u64, //maximum loan days
        state:bool,
    )acquires CollectionPool,ResourceInfo 
    {
        let owner_addr = signer::address_of(owner);
        //get pool address
        let collection_pool_address = get_resource_address(owner_addr,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        pool_data.dpr=dpr;
        pool_data.days=days;
        pool_data.state=state;
    }
    public entry fun lender_offer(
        lender:&signer, 
        collection_name: String,
        offer_amount:u64
    )acquires CollectionPool,ResourceInfo 
    {       
        let lender_addr = signer::address_of(lender);
        //verifying the pool
        let collection_pool_address = get_resource_address(@borrowlend,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exists
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        assert!(pool_data.state,ENO_STOPPED);
        pool_data.amount=pool_data.amount+offer_amount;
        coin::transfer<0x1::aptos_coin::AptosCoin>(lender, collection_pool_address, offer_amount);
        move_to<Lender>(lender , Lender{
        borrower:@borrowlend,
        //collection_name
        collection: collection_name,
        //offerred amount
        offer_amount: offer_amount,
        //time if the offer is accepted
        start_time:0,
        //if the offer is accepted and fund is taken
        offered_made: false,
        // similar like APY, daily Aptos to be PAID by the owner 
        dpr:0,
        //days
        days:0,
        });
    }
    public entry fun lender_offer_cancel(
        lender:&signer, 
        collection_name: String,
    )acquires CollectionPool,ResourceInfo,Lender 
    {       
        let lender_addr = signer::address_of(lender);
        //verifying pool presence
        let collection_pool_address = get_resource_address(@borrowlend,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exists
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        assert!(pool_data.state,ENO_STOPPED);
        //lender data
        let lender_data = borrow_global<Lender>(lender_addr);
        assert!(lender_data.collection==collection_name,ENO_COLLECTION_MISMATCH);
        assert!(lender_data.offered_made==false,ENO_LOAN_TAKEN);
        pool_data.amount=pool_data.amount-lender_data.offer_amount;
        coin::transfer<0x1::aptos_coin::AptosCoin>(&pool_signer_from_cap,lender_addr , lender_data.offer_amount);
        let dropdata = move_from<Lender>(lender_addr);
        let Lender{
        borrower:_,
        collection: _,
        offer_amount:_,
        start_time:_,
        offered_made:_,
        dpr:_,
        days:_}=dropdata;
    }
    public entry fun borrow_select(
        borrower:&signer, 
        collection_name: String,
        token_name: String,
        property_version: u64,
        lender:address,
    )acquires CollectionPool,ResourceInfo,Lender 
    {       
        let borrower_addr = signer::address_of(borrower);
        //verifying collection pool is verified or not
        let collection_pool_address = get_resource_address(@borrowlend,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);
        let pool_data = borrow_global<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        assert!(pool_data.state,ENO_STOPPED);
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        //lender data
        assert!(exists<Lender>(lender),ENO_NOT_INITIATED);
        let lender_data = borrow_global_mut<Lender>(lender);
        assert!(lender_data.collection==collection_name,ENO_COLLECTION_MISMATCH);
        assert!(lender_data.offered_made==false,ENO_LOAN_TAKEN);
        lender_data.borrower=borrower_addr;
        lender_data.start_time=now;
        lender_data.offered_made=true;
        lender_data.dpr=pool_data.dpr;
        lender_data.days=pool_data.days;
        //borrower
        let token_id = token::create_token_id_raw(pool_data.creator, collection_name, token_name, property_version);
        //verifying the token owner has the token
        assert!(balance_of(borrower_addr,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(borrower,&pool_signer_from_cap,token_id,1);
        move_to<Borrower>(borrower , Borrower{
        lender:lender,
        //collection_name
        collection: collection_name,
        //token_name
        token_name:token_name,
        // property version
        property_version:property_version,
        //offerred amount
        receiver_amount: lender_data.offer_amount,
        //time if the offer is accepted
        start_time:now,
        // similar like APY, daily Aptos to be PAID by the owner 
        dpr:pool_data.dpr,
        //days
        days:pool_data.days,
        });
        coin::transfer<0x1::aptos_coin::AptosCoin>(&pool_signer_from_cap,borrower_addr,lender_data.offer_amount);
    }
    public entry fun borrower_pay_loan(
        borrower:&signer, 
    )acquires CollectionPool,ResourceInfo,Lender,Borrower 
    {
        let borrower_addr = signer::address_of(borrower);
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        assert!(exists<Borrower>(borrower_addr),ENO_LOAN_NOT_TAKEN);
        let borrow_data = borrow_global<Borrower>(borrower_addr);
        //verifying collection pool is verified or not
        let collection_pool_address = get_resource_address(@borrowlend,borrow_data.collection);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        assert!(pool_data.state,ENO_STOPPED);
        //lenderside
        assert!(exists<Lender>(borrow_data.lender),ENO_NOT_INITIATED);
        let lender_data = borrow_global<Lender>(borrow_data.lender);
        assert!(lender_data.offered_made==true,ENO_LOAN_NOT_TAKEN);
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        let days= (now-borrow_data.start_time)/86400; //number of days
        assert!(days<=borrow_data.days,ENO_DAYS_CROSSED);
        let interest_amt = days* borrow_data.dpr*borrow_data.receiver_amount; // interest per day per apt
        let total_amt=interest_amt+borrow_data.receiver_amount;
        //release NFT
        let token_id = token::create_token_id_raw(pool_data.creator, pool_data.collection, borrow_data.token_name, borrow_data.property_version);
        //verifying the pool has the token
        assert!(balance_of(collection_pool_address,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap,borrower,token_id,1);
        //release fun to the lender
        coin::transfer<0x1::aptos_coin::AptosCoin>(borrower,borrow_data.lender,total_amt);
        pool_data.amount=pool_data.amount-borrow_data.receiver_amount;
        //delete accounts from borrower and lender
        let dropdata = move_from<Lender>(borrow_data.lender);
        let Lender{
        borrower:_,
        collection: _,
        offer_amount:_,
        start_time:_,
        offered_made:_,
        dpr:_,
        days:_}=dropdata;
        let borrow_drop_data = move_from<Borrower>(borrower_addr);
        let Borrower{
        lender:_,
        collection: _,
        token_name:_,
        property_version:_,
        receiver_amount:_,
        start_time:_,
        dpr:_,
        days:_}=borrow_drop_data;
    }
    //if the loan is not paid 
    //the lender can claim nft
    public entry fun lender_claim_nft(
        lender:&signer, 
        collection_name:String
    )acquires CollectionPool,ResourceInfo,Lender,Borrower 
    {
        let lender_addr = signer::address_of(lender);
        //verifying collection pool is verified or not
        let collection_pool_address = get_resource_address(@borrowlend,collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        assert!(pool_data.state,ENO_STOPPED);
        //lender
        assert!(exists<Lender>(lender_addr),ENO_NOT_INITIATED);
        let lender_data = borrow_global_mut<Lender>(lender_addr);
        assert!(lender_data.offered_made==true,ENO_LOAN_NOT_TAKEN);
        let now = aptos_framework::timestamp::now_seconds();
        let days= (now - lender_data.start_time)/86400; //number of days
        assert!(days>=lender_data.days,ENO_DAYS_CROSSED);
        //borrower data
        assert!(exists<Borrower>(lender_data.borrower),ENO_LOAN_NOT_TAKEN);
        let borrow_data = borrow_global<Borrower>(lender_data.borrower);
        pool_data.amount=pool_data.amount-borrow_data.receiver_amount;
        //release NFT
        let token_id = token::create_token_id_raw(pool_data.creator, pool_data.collection, borrow_data.token_name, borrow_data.property_version);
        //verifying the pool has the token
        assert!(balance_of(collection_pool_address,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap,lender,token_id,1);        
        //delete accounts from borrower and lender
        let dropdata = move_from<Lender>(lender_addr);
        let Lender{
        borrower:_,
        collection: _,
        offer_amount:_,
        start_time:_,
        offered_made:_,
        dpr:_,
        days:_}=dropdata;
        let borrow_drop_data = move_from<Borrower>(lender_data.borrower);
        let Borrower{
        lender:_,
        collection: _,
        token_name:_,
        property_version:_,
        receiver_amount:_,
        start_time:_,
        dpr:_,
        days:_}=borrow_drop_data;
    }
    fun create_add_resource_info(account:&signer,string:String,resource:address) acquires ResourceInfo
    {
        let account_addr = signer::address_of(account);
        if (!exists<ResourceInfo>(account_addr)) {
            move_to(account, ResourceInfo { resource_map: simple_map::create() })
        };
        let maps = borrow_global_mut<ResourceInfo>(account_addr);
        simple_map::add(&mut maps.resource_map, string,resource);
    }
    fun get_resource_address(add1:address,string:String): address acquires ResourceInfo
    {
        assert!(exists<ResourceInfo>(add1), ENO_NO_STAKING);
        let maps = borrow_global<ResourceInfo>(add1);
        let staking_address = *simple_map::borrow(&maps.resource_map, &string);
        staking_address

    }
}