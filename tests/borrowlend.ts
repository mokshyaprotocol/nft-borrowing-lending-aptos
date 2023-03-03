//Test Code for Borrow Lending
import { HexString,AptosClient,TokenClient, AptosAccount, FaucetClient, } from "aptos";

const NODE_URL = process.env.APTOS_NODE_URL || "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = process.env.APTOS_FAUCET_URL || "https://faucet.devnet.aptoslabs.com";


export const timeDelay = async (s: number): Promise<unknown> => {
  const delay = new Promise((resolve) => setTimeout(resolve, s*1000));
  return delay;
};

const client = new AptosClient(NODE_URL);
const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
//pid
const pid="0x147e4d3a5b10eaed2a93536e284c23096dfcea9ac61f0a8420e5d01fbd8f0ea8";
//borrow lend module
// This private key is only for test purpose do not use this in mainnet
const module_owner = new AptosAccount(HexString.ensure("0x1111111111111111111111111111111111111111111111111111111111111111").toUint8Array());
//borrower
const account1 = new AptosAccount();
// lender
const account2 = new AptosAccount();
//Token Info
const collection = "Mokshya Collection"+account1.address().toString();
const tokenname = "Mokshya Token #1";
const description="Mokshya Token for test"
const uri = "https://github.com/mokshyaprotocol"
const tokenPropertyVersion = BigInt(0);

/*
NFT BORROW LENDING CONTRACT 
*/
 describe("Borrow Lend", () => {
  it ("Create Collection", async () => {
    await faucetClient.fundAccount(account1.address(), 1000000000);//Airdropping
    const create_collection_payloads = {
      type: "entry_function_payload",
      function: "0x3::token::create_collection_script",
      type_arguments: [],
      arguments: [collection,description,uri,BigInt(100),[false, false, false]],
    };
    let txnRequest = await client.generateTransaction(account1.address(), create_collection_payloads);
    let bcsTxn = AptosClient.generateBCSTransaction(account1, txnRequest);
    await client.submitSignedBCSTransaction(bcsTxn);
  });
  it ("Create Token", async () => {
    const create_token_payloads = {
      type: "entry_function_payload",
      function: "0x3::token::create_token_script",
      type_arguments: [],
      arguments: [collection,tokenname,description,BigInt(5),BigInt(10),uri,account1.address(),
        BigInt(100),BigInt(0),[ false, false, false, false, false, false ],
        [ "attack", "num_of_use"],
        [[1,2],[1,2]],
        ["Bro","Ho"]
      ],
    };
    let txnRequest = await client.generateTransaction(account1.address(), create_token_payloads);
    let bcsTxn = AptosClient.generateBCSTransaction(account1, txnRequest);
    await client.submitSignedBCSTransaction(bcsTxn);
  });
  it ("Create Pool", async () => {
    const create_initiate_create_pool = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::initiate_create_pool",
      type_arguments: [],
      arguments: [account1.address(),collection,BigInt(86400),BigInt(1)],
    };
    let txnRequest = await client.generateTransaction(module_owner.address(), create_initiate_create_pool);
    let bcsTxn = AptosClient.generateBCSTransaction(module_owner, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
  });
  it ("Update Pool", async () => {
    const create_update_pool = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::update_pool",
      type_arguments: [],
      arguments: [collection,BigInt(86400),BigInt(1),true],
    };
    let txnRequest = await client.generateTransaction(module_owner.address(), create_update_pool);
    let bcsTxn = AptosClient.generateBCSTransaction(module_owner, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));

  });
  it ("Lender Offer", async () => {
    await faucetClient.fundAccount(account2.address(), 1000000000);//Airdropping
    const lender_offer_payload = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::lender_offer",
      type_arguments: [],
      arguments: [collection,BigInt(100),BigInt(1)],
    };
    let txnRequest = await client.generateTransaction(account2.address(), lender_offer_payload);
    let bcsTxn = AptosClient.generateBCSTransaction(account2, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
  });
  it ("Borrower Select Offer", async () => {
    const borrower_select_payload = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::borrow_select",
      type_arguments: [],
      arguments: [collection,tokenname,tokenPropertyVersion,account2.address()],
    };
    let txnRequest = await client.generateTransaction(account1.address(), borrower_select_payload);
    let bcsTxn = AptosClient.generateBCSTransaction(account1, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
    await timeDelay(10);
  });
  it ("Borrower Pay Loan", async () => {
    const borrower_payloan_payload = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::borrower_pay_loan",
      type_arguments: [],
      arguments: [collection,tokenname,],
    };
    let txnRequest = await client.generateTransaction(account1.address(), borrower_payloan_payload);
    let bcsTxn = AptosClient.generateBCSTransaction(account1, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
  });
  });
/*
As the contract requires the loan period to be at least a day 
So, it is not possible to test the default situation directly here
But the codes are commented below:
    it ("Lender Offer Cancel", async () => {
    const lender_offer_cancel_payload = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::lender_offer_cancel",
      type_arguments: [],
      arguments: [collection)],
    };
    let txnRequest = await client.generateTransaction(account2.address(), lender_offer_cancel_payload);
    let bcsTxn = AptosClient.generateBCSTransaction(account2, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
  });
  it ("Lender Defaults NFT", async () => {
    const lender_default_payload = {
      type: "entry_function_payload",
      function: pid+"::borrowlend::lender_claim_nft",
      type_arguments: [],
      arguments: [collection)],
    };
    let txnRequest = await client.generateTransaction(account2.address(), lender_default_payload);
    let bcsTxn = AptosClient.generateBCSTransaction(account2, txnRequest);
    console.log(await client.submitSignedBCSTransaction(bcsTxn));
  });
*/
