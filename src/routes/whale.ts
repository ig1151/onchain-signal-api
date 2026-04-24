import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getTokenTransfersByContract, labelAddress, getEthPrice } from '../services/etherscan';
import { logger } from '../logger';
import { WhaleTransfer } from '../types';

const router = Router();

// WETH, USDC, USDT, DAI contract addresses
const MAJOR_TOKENS: Record<string, { address: string; decimals: number; name: string }> = {
  USDC: { address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', decimals: 6, name: 'USDC' },
  USDT: { address: '0xdac17f958d2ee523a2206206994597c13d831ec7', decimals: 6, name: 'USDT' },
  WETH: { address: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', decimals: 18, name: 'WETH' },
  DAI: { address: '0x6b175474e89094c44da98b954eedeac495271d0f', decimals: 18, name: 'DAI' },
};

const recentSchema = Joi.object({
  token: Joi.string().valid('USDC', 'USDT', 'WETH', 'DAI').default('USDC'),
  minUsd: Joi.number().min(1000).max(10000000).default(50000),
  chain: Joi.string().valid('ethereum', 'base').default('ethereum'),
  limit: Joi.number().min(1).max(50).default(20),
});

// GET /v1/whale/recent
router.get('/recent', validate(recentSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, minUsd, chain, limit } = req.query as {
    token: string;
    minUsd: string;
    chain: string;
    limit: string;
  };

  const tokenInfo = MAJOR_TOKENS[token];
  const minUsdNum = parseFloat(minUsd as string);
  const limitNum = parseInt(limit as string);

  try {
    const [transfers, ethPrice] = await Promise.all([
      getTokenTransfersByContract(tokenInfo.address, chain, 200),
      getEthPrice(),
    ]);

    const whales: WhaleTransfer[] = [];

    for (const tx of transfers) {
      const rawAmount = parseInt(tx.value);
      const amount = rawAmount / Math.pow(10, tokenInfo.decimals);
      
      // For USDC/USDT, amount is already USD; for WETH use ETH price
      let usdValue: number;
      if (token === 'WETH') {
        usdValue = ethPrice ? amount * ethPrice : 0;
      } else {
        usdValue = amount;
      }

      if (usdValue < minUsdNum) continue;

      const fromLabel = labelAddress(tx.from);
      const toLabel = labelAddress(tx.to);

      let direction: WhaleTransfer['direction'] = 'WALLET_TO_WALLET';
      let sentiment: WhaleTransfer['sentiment'] = 'NEUTRAL';

      if (toLabel && toLabel.toLowerCase().includes('binance') ||
          toLabel && toLabel.toLowerCase().includes('coinbase') ||
          toLabel && toLabel.toLowerCase().includes('kraken') ||
          toLabel && toLabel.toLowerCase().includes('okx') ||
          toLabel && toLabel.toLowerCase().includes('bybit')) {
        direction = 'EXCHANGE_INFLOW';
        sentiment = 'BEARISH';
      } else if (fromLabel && (fromLabel.toLowerCase().includes('binance') ||
                  fromLabel.toLowerCase().includes('coinbase') ||
                  fromLabel.toLowerCase().includes('kraken'))) {
        direction = 'EXCHANGE_OUTFLOW';
        sentiment = 'BULLISH';
      }

      whales.push({
        txHash: tx.hash,
        from: tx.from,
        to: tx.to,
        fromLabel,
        toLabel,
        valueEth: `${amount.toFixed(2)} ${token}`,
        valueUsd: Math.round(usdValue),
        direction,
        sentiment,
        timestamp: new Date(parseInt(tx.timeStamp) * 1000).toISOString(),
        chain,
      });

      if (whales.length >= limitNum) break;
    }

    const bullishCount = whales.filter((w) => w.sentiment === 'BULLISH').length;
    const bearishCount = whales.filter((w) => w.sentiment === 'BEARISH').length;
    const overallSentiment =
      bullishCount > bearishCount ? 'BULLISH' : bearishCount > bullishCount ? 'BEARISH' : 'NEUTRAL';

    logger.info({ token, chain, count: whales.length, overallSentiment }, 'whale/recent');
    res.json({
      success: true,
      data: {
        token,
        chain,
        minUsd: minUsdNum,
        overallSentiment,
        bullishCount,
        bearishCount,
        transfers: whales,
      },
    });
  } catch (err: any) {
    logger.error({ err: err.message, token, chain }, 'whale/recent error');
    res.status(500).json({ error: 'Failed to fetch whale transfers', details: err.message });
  }
});

export default router;
