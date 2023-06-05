import { AptosClient, TxnBuilderTypes,HexString} from "aptos";

export class BorrowLendSDK {
  client: AptosClient;
  pid: string

  constructor(nodeUrl: string,) {
    this.client = new AptosClient(nodeUrl);
    // Initialize the module owner account here
    this.pid = "0x147e4d3a5b10eaed2a93536e284c23096dfcea9ac61f0a8420e5d01fbd8f0ea8"

  }
  /**
   * Creates a Pool by Module Creator
   *
   * @param collection Collection name
   * @param creatorAddress Collection Creator Address
   * @param dpr daily interest rate
   * @param days days before the lend expires
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>createPool

  public async createPool(collection: string, creatorAddress: String,dpr:BigInt, days:BigInt,): Promise<TxnBuilderTypes.RawTransaction> {
    // <:!:createPool
    const createPoolPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::initiate_create_pool",
      type_arguments: [],
      arguments: [creatorAddress, collection, dpr, days],
    };

    return await this.client.generateTransaction(HexString.ensure(this.pid), createPoolPayload);

  }
  /**
   * Updates a Pool by Module Creator
   *
   * @param collection Collection name
   * @param dpr daily interest rate
   * @param days days before the lend expires
   * @param state to switch of the pool
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>updatePool

  public async updatePool(collection: string, dpr:BigInt, days:BigInt,state:Boolean): Promise<TxnBuilderTypes.RawTransaction>  {
    // <:!:createPool
    const updatePoolPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::update_pool",
      type_arguments: [],
      arguments: [collection, dpr,days,state],
    };

    return await this.client.generateTransaction(HexString.ensure(this.pid), updatePoolPayload);

  }
  /**
   * Lender Offers To a Collection
   *
   * @param collection_name Collection name
   * @param offer_per_nft offer per nft
   * @param number_of_offers total number of offers
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>lenderOffer

  public async lenderOffer(lender:string,collection: string, offer_per_nft:BigInt,number_of_offers:BigInt): Promise<TxnBuilderTypes.RawTransaction> {
    // :!:>lenderOffer
    const lenderOfferPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::lender_offer",
      type_arguments: [],
      arguments: [collection,offer_per_nft,number_of_offers],
    };
    return await this.client.generateTransaction(HexString.ensure(lender), lenderOfferPayload);

  }
  /**
   * Lender Cancel Offers
   *
   * @param collection_name Collection name
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>lenderOfferCancel

  public async lenderOfferCancel(lender:string,collection: string): Promise<TxnBuilderTypes.RawTransaction> {
    // :!:>lenderOfferCancel
    const lenderOfferCancelPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::lender_offer",
      type_arguments: [],
      arguments: [collection,],
    };
    return await this.client.generateTransaction(HexString.ensure(lender), lenderOfferCancelPayload);

  }
  /**
   * Borrower Selects Offers
   *
   * @param borrower borrows loan
   * @param collection_name Collection name
   * @param tokenName token name
   * @param version property version
   * @param lenderAddress lender address to select
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>borrowerSelectOffer

  public async borrowerSelectOffer(borrower:string, collection: string, tokenName: string, version: bigint, lenderAddress: string): Promise<TxnBuilderTypes.RawTransaction> {
    // :!:>borrowerSelectOffer
    const borrowerSelectPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::borrow_select",
      type_arguments: [],
      arguments: [collection, tokenName, version, HexString.ensure(lenderAddress)],
    };

    return await this.client.generateTransaction(HexString.ensure(borrower), borrowerSelectPayload);

  }
  /**
   * Borrower Pays Loan
   *
   * @param borrower string
   * @param collection_name Collection name
   * @param tokenName token name
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>borrowerPayLoan

  public async borrowerPayLoan(borrower:string,collection: string, tokenName: string): Promise<TxnBuilderTypes.RawTransaction> {
    const borrowerPayLoanPayload = {
      type: "entry_function_payload",
      function: "borrowlend::borrower_pay_loan",
      type_arguments: [],
      arguments: [collection, tokenName],
    };

    return await this.client.generateTransaction(HexString.ensure(borrower), borrowerPayLoanPayload);
  }
  /**
   * Lender Claim NFT
   *
   * @param lenderAddress lender address to select
   * @param collection_name Collection name
   * @param tokenName token name
   * @returns Promise<TxnBuilderTypes.RawTransaction>
   */
  // :!:>lenderClaimNFT

  public async lenderClaimNFT(lenderAddress: string, collection: string, tokenName: string,): Promise<TxnBuilderTypes.RawTransaction> {
    // :!:>lenderClaimNFT
    const lenderClaimNFTPayload = {
      type: "entry_function_payload",
      function: this.pid+"borrowlend::borrow_select",
      type_arguments: [],
      arguments: [collection, tokenName,],
    };

    return await this.client.generateTransaction(HexString.ensure(lenderAddress), lenderClaimNFTPayload);
  }

}
