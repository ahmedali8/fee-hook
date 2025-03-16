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
        Usage: ts-node src/getOutputAmount.ts <chainId> <currency1Address> <currency1Decimals> <tick> <liquidity> <sqrtRatioX96> <fee> <tickSpacing> <inputCurrencyAddress> <inputRawAmount>

        1 ETH -> X Token
        bun ts-node src/getOutputAmount.ts 11155111 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" 18 161189 "3162275221685340688940" "250541255178517414234103244537599" 3000 60 "0x0000000000000000000000000000000000000000" "1000000000000000000"

        1_000_000 Token -> X ETH
        bun ts-node src/getOutputAmount.ts 11155111 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" 18 161189 "3162275221685340688940" "250541255178517414234103244537599" 3000 60 "0x7db8A8D1E9483115b9e8028d610e3C365c649f6a" "1000000000000000000000000"
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
    const inputCurrencyAddress = args[8];
    const inputRawAmount = JSBI.BigInt(args[9]);

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
