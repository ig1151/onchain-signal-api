import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getTokenTransfersByContract, labelAddress, getEthPrice } from '../services/etherscan';
import { callAI } from '../services/ai';
import { logger } from '../logger';
import { TokenFlows } from '../types';

const router = Router();

const flowsSchema = Joi.object({
  contract: Joi.string().pattern(/^0x[a-fA-F0-9]{40}$/).required(),
  chain: Joi.string().valid('ethereum', 'base', 'arbitrum', 'polygon').default('ethereum'),
  timeframe: Joi.string().valid('1h', '4h', '24h', '7d').default('24h'),
  decimals: Joi.number().min(0).max(18).default(18),
});

// GET /v1/token/flows
router.get('/flows', validate(flowsSchema), async (req: Request, res: Response): Promise<void> => {
  const { contract, chain, timeframe, decimals } = req.query as {
    contract: string;
    chain: string;
    timeframe: string;
    decimals: string;
  };

  const decimalsNum = parseInt(decimals as string);

  // Timeframe to seconds
  const timeframeMap: Record<string, number> = {
    '1h': 3600,
    '4h': 14400,
    '24h': 86400,
    '7d': 604800,
  };
  const cutoff = Math.floor(Date.now() / 1000) - timeframeMap[timeframe];

  try {
    const [transfers, ethPrice] = await Promise.all([
      getTokenTransfersByContract(contract, chain, 500),
      getEthPrice(),
    ]);

    const relevant = transfers.filter((tx: any) => parseInt(tx.timeStamp) >= cutoff);

    if (relevant.length === 0) {
      res.json({
        success: true,
        data: {
          contract,
          chain,
          timeframe,
          message: 'No transfers found in this timeframe',
          exchangeInflow: 0,
          exchangeOutflow: 0,
          netFlow: 0,
          sentiment: 'NEUTRAL',
          sentimentScore: 0,
          topMovers: [],
          summary: 'No activity detected in the specified timeframe.',
        } as TokenFlows,
      });
      return;
    }

    const tokenSymbol = relevant[0]?.tokenSymbol || 'TOKEN';
    const dec = relevant[0]?.tokenDecimal ? parseInt(relevant[0].tokenDecimal) : decimalsNum;

    let exchangeInflow = 0;
    let exchangeOutflow = 0;
    const moverMap: Record<string, { label: string | null; amount: number; direction: 'IN' | 'OUT' }> = {};

    for (const tx of relevant) {
      const amount = parseInt(tx.value) / Math.pow(10, dec);
      const fromLabel = labelAddress(tx.from);
      const toLabel = labelAddress(tx.to);

      // Inflow to exchange = distribution/selling
      if (toLabel) {
        exchangeInflow += amount;
        const key = tx.from.toLowerCase();
        moverMap[key] = {
          label: fromLabel,
          amount: (moverMap[key]?.amount || 0) + amount,
          direction: 'OUT',
        };
      }
      // Outflow from exchange = accumulation/buying
      if (fromLabel) {
        exchangeOutflow += amount;
        const key = tx.to.toLowerCase();
        moverMap[key] = {
          label: toLabel,
          amount: (moverMap[key]?.amount || 0) + amount,
          direction: 'IN',
        };
      }
    }

    const netFlow = exchangeOutflow - exchangeInflow;
    const total = exchangeInflow + exchangeOutflow;
    const sentimentScore = total > 0 ? Math.round((netFlow / total) * 100) : 0;

    let sentiment: TokenFlows['sentiment'] = 'NEUTRAL';
    if (sentimentScore >= 20) sentiment = 'ACCUMULATION';
    else if (sentimentScore <= -20) sentiment = 'SELL_PRESSURE';

    const topMovers = Object.entries(moverMap)
      .sort((a, b) => b[1].amount - a[1].amount)
      .slice(0, 5)
      .map(([address, data]) => ({
        address,
        label: data.label,
        amount: Math.round(data.amount),
        direction: data.direction,
      }));

    // AI summary
    const aiContext = `Token: ${tokenSymbol} on ${chain} over ${timeframe}
Exchange inflow (selling pressure): ${Math.round(exchangeInflow).toLocaleString()} tokens
Exchange outflow (buying/withdrawal): ${Math.round(exchangeOutflow).toLocaleString()} tokens
Net flow: ${Math.round(netFlow).toLocaleString()} (positive = more leaving exchanges = bullish)
Sentiment score: ${sentimentScore} (range -100 bearish to +100 bullish)
Total transfers analyzed: ${relevant.length}`;

    const summary = await callAI(
      `Analyze these onchain token flow metrics and write 2 sentences summarizing the market sentiment for traders. Be direct and specific.\n\n${aiContext}`
    );

    const result: TokenFlows = {
      token: tokenSymbol,
      contractAddress: contract,
      chain,
      timeframe,
      exchangeInflow: Math.round(exchangeInflow),
      exchangeOutflow: Math.round(exchangeOutflow),
      netFlow: Math.round(netFlow),
      sentiment,
      sentimentScore,
      topMovers,
      summary,
    };

    logger.info({ contract, chain, timeframe, sentiment, sentimentScore }, 'token/flows');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message, contract, chain }, 'token/flows error');
    res.status(500).json({ error: 'Failed to analyze token flows', details: err.message });
  }
});

export default router;
