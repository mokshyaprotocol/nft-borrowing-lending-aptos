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
        if (!coin::is_account_registered<0x1::aptos_coin::AptosCoin>(borrower_addr))
        {managed_coin::register<0x1::aptos_coin::AptosCoin>(borrower); 
        };
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
        let borrower_loan = table::remove(&mut borrower_info.borrows,coll_name);
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
    #[test_only] 
    use aptos_token::token::{create_collection,create_token_script,create_token_id_raw};
    #[test_only] 
    use aptos_token::token::withdraw_token;
    #[test_only] 
    use aptos_token::token::deposit_token;
    #[test_only] 
    use std::string;
    #[test_only] 
    use std::bcs;
    // Errors start in test code from 1000
    #[test_only]
    fun deposit_fund(
        receiver:&signer,
        aptos_framework:&signer)
    {
     let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        coin::register<0x1::aptos_coin::AptosCoin>(receiver);
        coin::deposit(signer::address_of(receiver), coin::mint(1000, &mint_cap));
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
    #[test_only]
    fun create_collection_token(
        creator:&signer,
        receiver:&signer)
    {
        create_collection(
                creator,
                string::utf8(b"Mokshya Collection"),
                string::utf8(b"Collection for Test"),
                string::utf8(b"https://github.com/mokshyaprotocol"),
                2,
                vector<bool>[false, false, false],
            );
        let default_keys = vector<String>[string::utf8(b"attack"), string::utf8(b"num_of_use")]; 
        let default_vals = vector<vector<u8>>[bcs::to_bytes<u64>(&10), bcs::to_bytes<u64>(&5)];
        let default_types = vector<String>[string::utf8(b"u64"), string::utf8(b"u64")];
        let mutate_setting = vector<bool>[false, false, false, false, false];
        create_token_script(
                creator,
                string::utf8(b"Mokshya Collection"),
                string::utf8(b"Mokshya Token #1"),
                string::utf8(b"Collection for Test"),
                2,
                5,
                string::utf8(b"mokshya.io"),
                signer::address_of(creator),
                100,
                0,
                mutate_setting,
                default_keys,
                default_vals,
                default_types,
            );
            let token_id=create_token_id_raw(signer::address_of(creator), string::utf8(b"Mokshya Collection"), 
            string::utf8(b"Mokshya Token #1"), 0);
            let token = withdraw_token(creator, token_id, 1);
            deposit_token(receiver, token);
    }
    #[test_only]
    fun initialize_for_test(
        module_owner:&signer,
        creator:&signer,       
        )acquires CollectionPool,PoolMap 
    {
        init_module(module_owner);
        assert!(exists<PoolMap>(signer::address_of(module_owner)),1000);
        initiate_create_pool(
            module_owner,
            signer::address_of(creator),
            string::utf8(b"Mokshya Collection"),
            86400,
            1
        );
        assert!(exists<CollectionPool>(get_pool_address(string::utf8(b"Mokshya Collection"))),1001);
        let collection_pool_data = borrow_global<CollectionPool>(get_pool_address(string::utf8(b"Mokshya Collection")));
        assert!(collection_pool_data.collection==string::utf8(b"Mokshya Collection"),1002);
        assert!(collection_pool_data.creator==signer::address_of(creator),1003);
        assert!(collection_pool_data.days==1,1004);
        assert!(collection_pool_data.dpr==86400,1005);
        assert!(collection_pool_data.state==true,1006);            
    }
    #[test_only]
    fun test_update_pool(
        module_owner:&signer,
    )acquires CollectionPool,PoolMap 
    {
        update_pool(
            module_owner,
            string::utf8(b"Mokshya Collection"),
            86500,
            2,
            false
        );
        let collection_pool_data = borrow_global<CollectionPool>(get_pool_address(string::utf8(b"Mokshya Collection")));
        assert!(collection_pool_data.days==2,1007);
        assert!(collection_pool_data.dpr==86500,1008);
        assert!(collection_pool_data.state==false,1009);  
    }
    #[test(creator = @0xa11ce, receiver = @0xb0b, borrowlend = @borrowlend)]
    fun test_pool(
        creator: signer,
        receiver: signer,
        borrowlend: signer
    )acquires CollectionPool,PoolMap{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, borrowlend = @borrowlend)]
    fun test_pool_updates(
        creator: signer,
        receiver: signer,
        borrowlend: signer
    )acquires CollectionPool,PoolMap{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        test_update_pool(&borrowlend);
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @aptos_framework,)]
    fun test_lender_offer(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            string::utf8(b"Mokshya Collection"),
            10,
            1
        );
        assert!(exists<Lender>(lender_addr),1010);
        let offer=& borrow_global<Lender>(lender_addr).offers; 
        assert!(table::contains(offer,  string::utf8(b"Mokshya Collection")),ENO_NO_OFFERS);
        let lender_offer = table::borrow(offer,string::utf8(b"Mokshya Collection"));
        assert!(lender_offer.offer_per_nft==10,1011);
        assert!(lender_offer.number_of_offers==1,1012);
        assert!(lender_offer.total_amount==10,1013);

        let pool_offer=& borrow_global<CollectionPool>(get_pool_address(string::utf8(b"Mokshya Collection"))).offer; 
        assert!(table::contains(pool_offer, lender_addr),ENO_NO_OFFERS);
        
        let offer_in = table::borrow(pool_offer,lender_addr);
        assert!(offer_in==lender_offer,1014);

        lender_offer_cancel(
            &lender,
            string::utf8(b"Mokshya Collection"));
        
        assert!(!table::contains(& borrow_global<Lender>(lender_addr).offers,  string::utf8(b"Mokshya Collection")),1015);
        assert!(!table::contains(& borrow_global<CollectionPool>(get_pool_address(string::utf8(b"Mokshya Collection"))).offer, lender_addr),ENO_NO_OFFERS);
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @0x1,)]
    fun test_borrow_select(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender,Borrower{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        let collection_name =  string::utf8(b"Mokshya Collection");
        let token_name = string::utf8(b"Mokshya Token #1");
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        let collection_pool = get_pool_address(string::utf8(b"Mokshya Collection"));
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            collection_name,
            10,
            1
        );
        aptos_framework::timestamp::set_time_has_started_for_testing(&aptos_framework);
        aptos_framework::timestamp::update_global_time_for_test_secs(1000);
        borrow_select(
            &receiver,
            collection_name,
            token_name,
            0,
            lender_addr);
        // verifying the borrower has received the amount
        assert!(coin::balance<0x1::aptos_coin::AptosCoin>(receiver_addr)==10,1016);
        // verifying the pool has the token 
        let token_id = token::create_token_id_raw(sender_addr,collection_name,token_name,0);
        //verifying the token owner has the token
        assert!(balance_of(collection_pool,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        let coll_name = collection_name;
        append(&mut coll_name,token_name);
        // verify that the offer is been removed 
        assert!(!table::contains(& borrow_global<Lender>(lender_addr).offers,collection_name),2000);
        assert!(!table::contains(& borrow_global<CollectionPool>(get_pool_address(collection_name)).offer, lender_addr),ENO_NO_OFFERS);
        // verify has been send to the lends
        assert!(table::contains(& borrow_global<Lender>(lender_addr).lends,coll_name),2001);        
        // verify changes in borrows of borrower
        assert!(table::contains(& borrow_global<Borrower>(receiver_addr).borrows,coll_name),2002); 
        //borrow the loan and verify the loan status
        let loan = *table::borrow(& borrow_global<Borrower>(receiver_addr).borrows,coll_name);
        let loan_info = Loan{
            borrower:receiver_addr,
            lender:lender_addr,
            collection_name:collection_name,
            token_name:token_name,
            property_version:0,
            start_time:1000,
            dpr:86400,
            amount:10,
            days:1};
        assert!(loan_info==loan,2003)
        
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @0x1,)]
    fun test_borrow_pay_loan(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender,Borrower{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        let collection_name =  string::utf8(b"Mokshya Collection");
        let token_name = string::utf8(b"Mokshya Token #1");
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        // let collection_pool = get_pool_address(string::utf8(b"Mokshya Collection"));
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            collection_name,
            10,
            1
        );
        aptos_framework::timestamp::set_time_has_started_for_testing(&aptos_framework);
        aptos_framework::timestamp::update_global_time_for_test_secs(1000);
        borrow_select(
            &receiver,
            collection_name,
            token_name,
            0,
            lender_addr);
        coin::transfer<0x1::aptos_coin::AptosCoin>(&lender,receiver_addr,10);
        aptos_framework::timestamp::update_global_time_for_test_secs(1010);
        borrower_pay_loan(
            &receiver,
            collection_name,
            token_name,
        ); 
        // verifying the borrower has given back the amount
        assert!(coin::balance<0x1::aptos_coin::AptosCoin>(receiver_addr)==0,1017);
        // verifying the pool has the token 
        let token_id = token::create_token_id_raw(sender_addr,collection_name,token_name,0);
        //verifying the token owner has the token
        assert!(balance_of(receiver_addr,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        // after the borrower pays loan the lend info should be removed
        let coll_name = collection_name;
        append(&mut coll_name,token_name);
        assert!(!table::contains(& borrow_global<CollectionPool>(get_pool_address(collection_name)).loans, token_name),2003);
        assert!(!table::contains(& borrow_global<Lender>(lender_addr).lends,coll_name),2004);        
        assert!(!table::contains(& borrow_global<Borrower>(receiver_addr).borrows,coll_name),2005); 
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @0x1,)]
    #[expected_failure(abort_code = 12, location = Self)]
    fun test_borrow_pay_after_time(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender,Borrower{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        let collection_name =  string::utf8(b"Mokshya Collection");
        let token_name = string::utf8(b"Mokshya Token #1");
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            collection_name,
            10,
            1
        );
        aptos_framework::timestamp::set_time_has_started_for_testing(&aptos_framework);
        aptos_framework::timestamp::update_global_time_for_test_secs(1000);
        borrow_select(
            &receiver,
            collection_name,
            token_name,
            0,
            lender_addr);
        coin::transfer<0x1::aptos_coin::AptosCoin>(&lender,receiver_addr,10);
        aptos_framework::timestamp::update_global_time_for_test_secs(87401);
        borrower_pay_loan(
            &receiver,
            collection_name,
            token_name,
        ); 
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @0x1,)]
    fun test_lender_claim_nft(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender,Borrower{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        let collection_name =  string::utf8(b"Mokshya Collection");
        let token_name = string::utf8(b"Mokshya Token #1");
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            collection_name,
            10,
            1
        );
        aptos_framework::timestamp::set_time_has_started_for_testing(&aptos_framework);
        aptos_framework::timestamp::update_global_time_for_test_secs(1000);
        borrow_select(
            &receiver,
            collection_name,
            token_name,
            0,
            lender_addr);
        coin::transfer<0x1::aptos_coin::AptosCoin>(&lender,receiver_addr,10);
        aptos_framework::timestamp::update_global_time_for_test_secs(87401);
        lender_claim_nft(
            &lender,
            collection_name,
            token_name,
        );
        // verifying the pool has the token 
        let token_id = token::create_token_id_raw(sender_addr,collection_name,token_name,0);
        //verifying the token owner has the token
        assert!(balance_of(lender_addr,token_id)>=1,ENO_NO_TOKEN_IN_TOKEN_STORE);
        // after the lender defaults the  NFT all the info needs to be deleted 
        let coll_name = collection_name;
        append(&mut coll_name,token_name);
        assert!(!table::contains(& borrow_global<CollectionPool>(get_pool_address(collection_name)).loans, token_name),2006);
        assert!(!table::contains(& borrow_global<Lender>(lender_addr).lends,coll_name),2007);        
        assert!(!table::contains(& borrow_global<Borrower>(receiver_addr).borrows,coll_name),2008); 
    } 
    #[test(creator = @0xa11ce, receiver = @0xb0b, lender =@0xa0b, borrowlend = @borrowlend,aptos_framework = @0x1,)]
    #[expected_failure(abort_code = 17, location = Self)]
    fun test_lender_claim_before_time(
        creator: signer,
        receiver: signer,
        borrowlend: signer,
        lender:signer,
        aptos_framework:signer,
    )acquires CollectionPool,PoolMap,Lender,Borrower{
       let sender_addr = signer::address_of(&creator);
       let receiver_addr = signer::address_of(&receiver);
       let lender_addr = signer::address_of(&lender);
        aptos_framework::account::create_account_for_test(sender_addr);
        aptos_framework::account::create_account_for_test(receiver_addr);
        aptos_framework::account::create_account_for_test(lender_addr);
        let collection_name =  string::utf8(b"Mokshya Collection");
        let token_name = string::utf8(b"Mokshya Token #1");
        create_collection_token(&creator,&receiver);
        initialize_for_test(&borrowlend,&creator);
        deposit_fund(&lender,&aptos_framework);
        lender_offer(
            &lender,
            collection_name,
            10,
            1
        );
        aptos_framework::timestamp::set_time_has_started_for_testing(&aptos_framework);
        aptos_framework::timestamp::update_global_time_for_test_secs(1000);
        borrow_select(
            &receiver,
            collection_name,
            token_name,
            0,
            lender_addr);
        coin::transfer<0x1::aptos_coin::AptosCoin>(&lender,receiver_addr,10);
        aptos_framework::timestamp::update_global_time_for_test_secs(2000);
        lender_claim_nft(
            &lender,
            collection_name,
            token_name,
        );
    } 
}