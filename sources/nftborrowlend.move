//! Contract to borrow or lend against NFTs
//! Created by Mokshya Protocol
module borrowlend::borrowlend
{
    use std::signer;
    use std::string::{String,append};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_token::token::{Self,check_collection_exists,balance_of,direct_transfer};
    use std::bcs::to_bytes;
    use aptos_std::table::{Self, Table};

    struct CollectionPool has key 
    {
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
        //treasury_cap
        treasury_cap:account::SignerCapability,
        //active offers: lender and amount
        offer: Table<address,Amount>,
        // active loans token name
        loans: Table<String,Loan>,
    }
    struct Lender has key
    {
        //active offers, collection name and amount
        offers:Table<String,Amount>,
        // active loans: collection+tokenname,Loan
        lends:Table<String,Loan>,
    }
    struct Borrower has key
    {
        // active borrows:  collection+tokenname, Loan
        borrows:Table<String,Loan>,
    }
    struct PoolMap has key
    {
        //initiated while creating the module contains the 
        //for each collection pool
        //collection name and pool address
        pools: Table<String, address>, 
    }
    struct Loan has copy,drop,store
    {
        borrower:address,
        lender:address,
        collection_name:String,
        token_name:String,
        property_version:u64,
        start_time:u64,
        dpr:u64,
        amount:u64,
        days:u64,
    }
    struct Amount has drop,store
    {
        offer_per_nft:u64, //amount offered per NFT
        number_of_offers:u64, // say Liquidity for 2 NFTs
        total_amount:u64, // offer_per_nft * number_of_offers, REDUNDANT  
    }
    // ERRORS 
    const ENO_NO_COLLECTION:u64=0;
    const ENO_NOT_INITIATED:u64=1;
    const ENO_NO_POOL:u64=2;
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
    const ENO_NOT_MODULE_DEPLOYER:u64=13;
    const ENO_NO_OFFERS:u64= 14;
    const ENO_NO_OFFER_MISMATCH:u64= 15;
    const ENO_LOAN_INFO_MISMATCH:u64= 16;
    const ENO_TIME_NOT_OVER:u64=17;
    //Functions   
    fun init_module(module_owner:&signer) 
    {
        let module_owner_address = signer::address_of(module_owner);
        assert!(module_owner_address==@borrowlend,ENO_NOT_MODULE_DEPLOYER);
        if (!exists<PoolMap>(module_owner_address))
        {
        move_to(module_owner,
                PoolMap{
                    pools:table::new<String,address>(),
                });
        };
        
    }  
    public entry fun initiate_create_pool(
        owner: &signer,
        creator_addr:address,
        collection_name:String, //the name of the collection owned by Creator 
        dpr:u64,//rate of payment,
        days:u64, //maximum loan days
    ) acquires PoolMap{
        let owner_addr = signer::address_of(owner);
        assert!(owner_addr==@borrowlend,ENO_NOT_MODULE_CREATOR);
        //verify the creator has the collection
        assert!(check_collection_exists(creator_addr,collection_name), ENO_NO_COLLECTION);
        let (collection_pool, collection_pool_cap) = account::create_resource_account(owner, to_bytes(&collection_name)); //resource account to store funds and data
        let  collection_pool_signer_from_cap = account::create_signer_with_capability(&collection_pool_cap);
        let collection_pool_address = signer::address_of(&collection_pool);
        // save pool address
        let pool_map = &mut borrow_global_mut<PoolMap>(@borrowlend).pools;
        table::add(pool_map, collection_name, collection_pool_address);
        assert!(!exists<CollectionPool>(collection_pool_address),ENO_ALREADY_INITIATED);
        move_to<CollectionPool>(&collection_pool_signer_from_cap, CollectionPool{
        collection: collection_name,
        creator:creator_addr,
        dpr:dpr,
        days:days,
        state:true,
        treasury_cap:collection_pool_cap,
        offer:table::new<address,Amount>(),
        loans: table::new<String,Loan>(),
        });
    }
    public entry fun update_pool(
        owner: &signer,
        collection_name:String, //the name of the collection owned by Creator 
        dpr:u64,//rate of payment,
        days:u64, //maximum loan days
        state:bool,
    )acquires CollectionPool,PoolMap 
    {
        let owner_addr = signer::address_of(owner);
        assert!(owner_addr==@borrowlend,ENO_NOT_MODULE_CREATOR);
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        pool_data.dpr=dpr;
        pool_data.days=days;
        pool_data.state=state;
    }
    public entry fun lender_offer(
        lender:&signer, 
        collection_name: String,
        offer_per_nft:u64,
        number_of_offers:u64,
    )acquires CollectionPool,PoolMap,Lender 
    {   
        let lender_addr = signer::address_of(lender);
        //verifying the pool
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data =borrow_global_mut<CollectionPool>(collection_pool_address);
        assert!(pool_data.state,ENO_STOPPED);
        if (!exists<Lender>(lender_addr))
        {
        move_to(lender,
                Lender{
                    offers:table::new(),
                    lends:table::new(),
                });
        };
        let user_info=borrow_global_mut<Lender>(lender_addr); 
        //TODO: verify the user hasn't active loan from the same collection
        // As it can be simply by-passed so there is no point in verifying this

        //if offer already exists we update the offer rather than creating
        //multiple offers with different price points
        let total_amount = offer_per_nft*number_of_offers;
        table::upsert(&mut user_info.offers,collection_name,Amount{offer_per_nft,number_of_offers,total_amount});
        //Adding the offer in the pool as well
        table::upsert(&mut pool_data.offer,lender_addr,Amount{offer_per_nft,number_of_offers,total_amount});
        //sending the fund to the pool
         let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        if (!coin::is_account_registered<0x1::aptos_coin::AptosCoin>(collection_pool_address))
        {managed_coin::register<0x1::aptos_coin::AptosCoin>(&pool_signer_from_cap); 
        };
        coin::transfer<0x1::aptos_coin::AptosCoin>(lender, collection_pool_address, total_amount);
    }
    public entry fun lender_offer_cancel(
        lender:&signer, 
        collection_name: String,
    )acquires CollectionPool,PoolMap,Lender 
    {       
        let lender_addr = signer::address_of(lender);
        //verifying the pool
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exists
        let pool_data = borrow_global_mut<CollectionPool>(collection_pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        //lender info and verification
        assert!(exists<Lender>(lender_addr),ENO_NO_OFFERS);
        let offers = &mut borrow_global_mut<Lender>(lender_addr).offers;
        assert!(table::contains(offers, collection_name),ENO_NO_OFFERS);
        assert!(table::contains(&mut pool_data.offer, lender_addr),ENO_NO_OFFERS);
        let pool_offer=table::borrow(&mut pool_data.offer,lender_addr);
        let lender_offer = table::borrow(offers,collection_name);
        assert!(pool_offer==lender_offer,ENO_NO_OFFER_MISMATCH);
        let offer_amount = lender_offer.total_amount;
        // removing the offer 
        table::remove(offers,collection_name);
        table::remove(&mut pool_data.offer,lender_addr);
        //returning the amount from the pool to the lender
        coin::transfer<0x1::aptos_coin::AptosCoin>(&pool_signer_from_cap,lender_addr , offer_amount);
    }
    public entry fun borrow_select(
        borrower:&signer, 
        collection_name: String,
        token_name: String,
        property_version: u64,
        lender:address,
    )acquires CollectionPool,PoolMap,Lender,Borrower 
    {       
        let borrower_addr = signer::address_of(borrower);
        //verifying collection pool is verified or not
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data =borrow_global_mut<CollectionPool>(collection_pool_address);
        assert!(pool_data.state,ENO_STOPPED);
        if (!exists<Borrower>(borrower_addr))
        {
            move_to(borrower,
                Borrower{
                    borrows:table::new(),
                });
        };
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        assert!(pool_data.state,ENO_STOPPED);
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        //lender checks
        assert!(exists<Lender>(lender),ENO_NO_OFFERS);// the offer doesn't exist
        let lender_info = borrow_global_mut<Lender>(lender);
        assert!(table::contains(& lender_info.offers, collection_name),ENO_NO_OFFERS);
        let offer = table::borrow_mut(&mut lender_info.offers, collection_name);
        // verifying offer from pool as well
        assert!(table::contains(&mut pool_data.offer, lender),ENO_NO_OFFERS);
        let pool_offer=table::borrow_mut(&mut pool_data.offer,lender);
        assert!(pool_offer==offer,ENO_NO_OFFER_MISMATCH);
        let loan_amount = offer.offer_per_nft;
        // if there is just one offer we 
        if (offer.number_of_offers == 1)
        {
            let _null = table::remove(&mut lender_info.offers, collection_name);
            let _rem  = table::remove(&mut pool_data.offer, lender);
        } 
        else
        {
            pool_offer.number_of_offers=pool_offer.number_of_offers-1;
            pool_offer.total_amount=pool_offer.total_amount-pool_offer.offer_per_nft;
            offer.number_of_offers=offer.number_of_offers-1;
            offer.total_amount=offer.total_amount-offer.offer_per_nft;
        };
        //the Loan
        let loan = Loan{
            borrower:borrower_addr,
            lender:lender,
            collection_name:collection_name,
            token_name:token_name,
            property_version:property_version,
            start_time:now,
            dpr:pool_data.dpr,
            amount:loan_amount,
            days:pool_data.days
        };
        //adding the loan in active lends of the lender
        let coll_name = collection_name;
        append(&mut coll_name,token_name); //collateral name
        //adding in lender address
        table::upsert(&mut lender_info.lends,coll_name,loan);
        //adding in pool
        table::upsert(&mut pool_data.loans,token_name,loan);
        //borrower
        let borrower_info =borrow_global_mut<Borrower>(borrower_addr);
        let token_id = token::create_token_id_raw(pool_data.creator,collection_name,token_name,property_version);
        //verifying the token owner has the token
        assert!(balance_of(borrower_addr,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        //adding in lender address
        table::upsert(&mut borrower_info.borrows,coll_name,loan);
        direct_transfer(borrower,&pool_signer_from_cap,token_id,1);
        coin::transfer<0x1::aptos_coin::AptosCoin>(&pool_signer_from_cap,borrower_addr,loan_amount);
    }
    public entry fun borrower_pay_loan(
        borrower:&signer, 
        collection_name: String,
        token_name: String,
    )acquires CollectionPool,PoolMap,Lender,Borrower 
    {
        let borrower_addr = signer::address_of(borrower);
        //verifying collection pool is verified or not
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data =borrow_global_mut<CollectionPool>(collection_pool_address);
        assert!(table::contains(& pool_data.loans, token_name),ENO_LOAN_NOT_TAKEN);
        let loan_in_pool = table::remove(&mut pool_data.loans,token_name);
        // the collateral name 
        let coll_name = collection_name;
        append(&mut coll_name,token_name); //collateral name
        // deriving the loan information from the borrower side
        assert!(exists<Borrower>(borrower_addr),ENO_LOAN_NOT_TAKEN);// the loan doesn't exist here
        let borrower_info =borrow_global_mut<Borrower>(borrower_addr);
        assert!(table::contains(& borrower_info.borrows, coll_name),ENO_LOAN_NOT_TAKEN);
        let borrower_loan = table::remove(&mut borrower_info.borrows,coll_name);
        // verifying the information from borrower and in pool are same
        assert!(borrower_loan==loan_in_pool,ENO_LOAN_INFO_MISMATCH);
        // again verifying information from the lender account 
        let lender_addr = borrower_loan.lender;
        assert!(exists<Lender>(lender_addr),ENO_LOAN_NOT_TAKEN);// the loan doesn't exist here
        let lender_info =borrow_global_mut<Lender>(lender_addr);
        assert!(table::contains(& lender_info.lends, coll_name),ENO_LOAN_NOT_TAKEN);
        let lender_loan = table::remove(&mut lender_info.lends,coll_name);
        assert!(lender_loan==borrower_loan,ENO_LOAN_INFO_MISMATCH);
        //calculations for the amount to be paid 
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        let days_in_sec= (now-borrower_loan.start_time); //number of days
        assert!(days_in_sec<=borrower_loan.days*86400,ENO_DAYS_CROSSED);
        let interest_amt = (days_in_sec*borrower_loan.dpr)/ 86400;
        let total_amt=interest_amt+borrower_loan.amount;
        //release NFT
        let token_id = token::create_token_id_raw(pool_data.creator, pool_data.collection, borrower_loan.token_name, borrower_loan.property_version);
        //signer 
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        //verifying the pool has the token
        assert!(balance_of(collection_pool_address,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap,borrower,token_id,1);
        //release fun to the lender
        coin::transfer<0x1::aptos_coin::AptosCoin>(borrower,borrower_loan.lender,total_amt);
    }
    // //if the loan is not paid 
    // //the lender can claim nft
    public entry fun lender_claim_nft(
        lender:&signer, 
        collection_name:String,
        token_name:String
    )acquires CollectionPool,PoolMap,Lender,Borrower 
    {
        let lender_addr = signer::address_of(lender);
        //verifying collection pool is verified or not
        let collection_pool_address=get_pool_address(collection_name);
        assert!(exists<CollectionPool>(collection_pool_address),ENO_NOT_INITIATED);// the pool doesn't exist
        let pool_data =borrow_global_mut<CollectionPool>(collection_pool_address);
        assert!(table::contains(& pool_data.loans, token_name),ENO_LOAN_NOT_TAKEN);
        let loan_in_pool = table::remove(&mut pool_data.loans,token_name);
        // the collateral name 
        let coll_name = collection_name;
        append(&mut coll_name,token_name); //collateral name
        // deriving the loan information from the borrower side
        assert!(exists<Lender>(lender_addr),ENO_LOAN_NOT_TAKEN);// the loan doesn't exist here
        let lender_info =borrow_global_mut<Lender>(lender_addr);
        assert!(table::contains(& lender_info.lends, coll_name),ENO_LOAN_NOT_TAKEN);
        let lender_loan = table::remove(&mut lender_info.lends,coll_name);
        // verifying the information from borrower and in pool are same
        assert!(lender_loan==loan_in_pool,ENO_LOAN_INFO_MISMATCH);
        // again verifying information from the lender account 
        let borrower_addr = lender_loan.borrower;
        assert!(exists<Borrower>(borrower_addr),ENO_LOAN_NOT_TAKEN);// the loan doesn't exist here
        let borrower_info =borrow_global_mut<Borrower>(borrower_addr);
        assert!(table::contains(& borrower_info.borrows, coll_name),ENO_LOAN_NOT_TAKEN);
        let borrower_loan = table::remove(&mut lender_info.lends,coll_name);
        assert!(lender_loan==borrower_loan,ENO_LOAN_INFO_MISMATCH);
        // verifying that the time is over or not
        //current time
        let now = aptos_framework::timestamp::now_seconds();
        let days_in_sec= (now-lender_loan.start_time); //number of days
        assert!(days_in_sec>=lender_loan.days*86400,ENO_TIME_NOT_OVER);
        //release NFT
        let token_id = token::create_token_id_raw(pool_data.creator, pool_data.collection, lender_loan.token_name, lender_loan.property_version);
        //signer
        let pool_signer_from_cap = account::create_signer_with_capability(&pool_data.treasury_cap);
        //verifying the pool has the token
        assert!(balance_of(collection_pool_address,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        direct_transfer(&pool_signer_from_cap,lender,token_id,1);        
    }
    fun get_pool_address(collection_name:String): address acquires PoolMap
    {
        let pool_map = &borrow_global<PoolMap>(@borrowlend).pools;
        assert!(
            table::contains(pool_map, collection_name),ENO_NO_POOL
        );
        let collection_pool_address=*table::borrow(pool_map,collection_name);
        collection_pool_address
    }
}