#!/usr/bin/env ts-node

import { ADDRESS_ZERO } from "@uniswap/v3-sdk";
import JSBI from "jsbi";
import { getPool } from "./utils/shared";
import { CurrencyAmount } from "@uniswap/sdk-core";
import { ethers } from "ethers";

(async () => {
  try {
    // Extract CLI arguments
    const args = process.argv.slice(2);

    if (args.length < 1) {
      console.error(
        `
        Usage: ts-node src/getOutputAmount.ts <chainId>,<currency1Address>,<currency1Decimals>,<tick>,<liquidity>,<sqrtRatioX96>,<fee>,<tickSpacing>,<inputCurrencyAddress>,<inputRawAmount>

        1 ETH -> X Token
        bun ts-node src/getOutputAmount.ts 11155111,"0x7db8A8D1E9483115b9e8028d610e3C365c649f6a",18,161189,"3162275221685340688940","250541255178517414234103244537599",3000,60,"0x0000000000000000000000000000000000000000","1000000000000000000"

        1_000_000 Token -> X ETH
        bun ts-node src/getOutputAmount.ts 11155111,"0x7db8A8D1E9483115b9e8028d610e3C365c649f6a",18,161189,"3162275221685340688940","250541255178517414234103244537599",3000,60,"0x7db8A8D1E9483115b9e8028d610e3C365c649f6a","1000000000000000000000000"
        `
      );
      process.exit(1);
    }

    // Split the single comma-separated argument string into an array
    const params = args[0].split(",");

    if (params.length !== 10) {
      console.error("Error: Incorrect number of arguments provided.");
      process.exit(1);
    }

    // Parse CLI arguments
    const chainId = parseInt(params[0], 10);
    const currency1Address = params[1];
    const currency1Decimals = parseInt(params[2], 10);
    const tick = parseInt(params[3], 10);
    const liquidity = JSBI.BigInt(params[4]);
    const sqrtRatioX96 = JSBI.BigInt(params[5]);
    const fee = parseInt(params[6], 10);
    const tickSpacing = parseInt(params[7], 10);
    const inputCurrencyAddress = params[8];
    const inputRawAmount = JSBI.BigInt(params[9]);

    const { pool, currencyNative, currency1 } = getPool({
      chainId,
      currency1Address,
      currency1Decimals,
      tick,
      liquidity,
      sqrtRatioX96,
      fee,
      tickSpacing,
    });

    const inputCurrency =
      inputCurrencyAddress == ADDRESS_ZERO ? currencyNative : currency1;

    const inputAmount = CurrencyAmount.fromRawAmount(
      inputCurrency,
      inputRawAmount
    );

    const [outputAmount] = await pool.getOutputAmount(inputAmount);

    // console.log("Output Amount", outputAmount.quotient.toString());
    // console.log("Output Amount", outputAmount.toExact());

    process.stdout.write(
      ethers.utils.defaultAbiCoder.encode(
        ["uint256"],
        [ethers.BigNumber.from(outputAmount.quotient.toString())]
      )
    );
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
})();
