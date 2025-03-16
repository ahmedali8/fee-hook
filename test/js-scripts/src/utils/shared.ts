import JSBI from "jsbi";
import {
  ADDRESS_ZERO,
  nearestUsableTick,
  TickConstructorArgs,
  TickMath,
} from "@uniswap/v3-sdk";
import { Currency, Ether, Token } from "@uniswap/sdk-core";
import { Pool } from "@uniswap/v4-sdk";

export function getPool({
  chainId,
  currency1Address,
  currency1Decimals,
  tick,
  liquidity,
  sqrtRatioX96,
  fee,
  tickSpacing,
}: {
  chainId: number;
  currency1Address: string;
  currency1Decimals: number;
  fee: number;
  tickSpacing: number;
  tick: number;
  liquidity: JSBI;
  sqrtRatioX96: JSBI;
}) {
  const currencyNative = Ether.onChain(chainId);
  const currency1: Currency = new Token(
    chainId,
    currency1Address,
    currency1Decimals
  );

  const poolKey = Pool.getPoolKey(
    currencyNative,
    currency1,
    fee,
    tickSpacing,
    ADDRESS_ZERO
  );

  // Provide full-range liquidity to the pool
  const tickLower = nearestUsableTick(TickMath.MIN_TICK, poolKey.tickSpacing);
  const tickUpper = nearestUsableTick(TickMath.MAX_TICK, poolKey.tickSpacing);

  // Tick Bitmap
  const tickBitmap: TickConstructorArgs[] = [
    {
      index: tickLower,
      liquidityNet: liquidity,
      liquidityGross: liquidity,
    },
    {
      index: tickUpper,
      liquidityNet: JSBI.multiply(liquidity, JSBI.BigInt(-1)),
      liquidityGross: liquidity,
    },
  ];

  // Pool Instance
  const pool = new Pool(
    currencyNative,
    currency1,
    fee,
    tickSpacing,
    ADDRESS_ZERO,
    sqrtRatioX96,
    liquidity,
    tick,
    tickBitmap
  );

  return {
    currencyNative,
    currency1,
    poolKey,
    tickLower,
    tickUpper,
    tickBitmap,
    pool,
  };
}
