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

    if (args.length < 9) {
      console.error(
        `
        Usage: ts-node src/getInputAmount.ts <chainId> <currency1Address> <currency1Decimals> <tick> <liquidity> <sqrtRatioX96> <fee> <tickSpacing> <outputCurrencyAddress> <outputRawAmount>

        X ETH -> 1_000_000 Token
        bun ts-node src/getInputAmount.ts 11155111 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" 18 161189 "3162275221685340688940" "250541255178517414234103244537599" 3000 60 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" "1000000000000000000000000"

        X Token -> 1 ETH
        bun ts-node src/getInputAmount.ts 11155111 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" 18 161189 "3162275221685340688940" "250541255178517414234103244537599" 3000 60 "0x0000000000000000000000000000000000000000" "1000000000000000000"
        `
      );
      process.exit(1);
    }

    // Parse CLI arguments
    const chainId = parseInt(args[0], 10);
    const currency1Address = args[1];
    const currency1Decimals = parseInt(args[2], 10);
    const tick = parseInt(args[3], 10);
    const liquidity = JSBI.BigInt(args[4]);
    const sqrtRatioX96 = JSBI.BigInt(args[5]);
    const fee = parseInt(args[6], 10);
    const tickSpacing = parseInt(args[7], 10);
    const outputCurrencyAddress = args[8];
    const outputRawAmount = JSBI.BigInt(args[9]);

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

    const outputCurrency =
      outputCurrencyAddress == ADDRESS_ZERO ? currencyNative : currency1;

    console.log("outputCurrency: ", outputCurrency);

    const outputAmount = CurrencyAmount.fromRawAmount(
      outputCurrency,
      outputRawAmount
    );

    const [inputAmount] = await pool.getInputAmount(outputAmount);

    // console.log("Input Amount", inputAmount.quotient.toString());
    // console.log("Input Amount", inputAmount.toExact());

    process.stdout.write(
      ethers.utils.defaultAbiCoder.encode(
        ["uint256"],
        [ethers.BigNumber.from(inputAmount.quotient.toString())]
      )
    );
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
})();
