import 'dotenv/config';
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import {
  getEthBalance,
  getTxList,
  getTokenTransfers,
  getEthPrice,
  labelAddress,
} from '../services/etherscan';
import { callAI } from '../services/ai';
import { logger } from '../logger';
import { WalletAnalysis, WalletSignal } from '../types';

const router = Router();

const SUPPORTED_CHAINS = ['ethereum', 'base', 'arbitrum', 'polygon', 'optimism', 'bsc'];

const analyzeSchema = Joi.object({
  address: Joi.string().pattern(/^0x[a-fA-F0-9]{40}$/).required(),
  chain: Joi.string().valid(...SUPPORTED_CHAINS).default('ethereum'),
});

const signalsSchema = Joi.object({
  address: Joi.string().pattern(/^0x[a-fA-F0-9]{40}$/).required(),
  chain: Joi.string().valid(...SUPPORTED_CHAINS).default('ethereum'),
});

// GET /v1/wallet/analyze
router.get('/analyze', validate(analyzeSchema), async (req: Request, res: Response): Promise<void> => {
  const { address, chain } = req.query as { address: string; chain: string };

  try {
    const ethBalance = await getEthBalance(address, chain);
    const ethPrice = await getEthPrice();
    const txList = await getTxList(address, chain, 50);
    const tokenTransfers = await getTokenTransfers(address, chain, 50);

    const balanceNum = parseFloat(ethBalance);
    const ethBalanceUsd = ethPrice ? Math.round(balanceNum * ethPrice) : null;

    const thirtyDaysAgo = Math.floor(Date.now() / 1000) - 30 * 24 * 3600;
    const recentTxs = txList.filter((tx: any) => parseInt(tx.timeStamp) > thirtyDaysAgo);

    const sends = txList.filter((tx: any) => tx.from.toLowerCase() === address.toLowerCase()).length;
    const receives = txList.filter((tx: any) => tx.to?.toLowerCase() === address.toLowerCase()).length;

    let exchangeInflows = 0;
    let exchangeOutflows = 0;
    for (const tx of txList.slice(0, 30)) {
      const fromLabel = labelAddress(tx.from);
      const toLabel = labelAddress(tx.to || '');
      if (fromLabel) exchangeInflows++;
      if (toLabel) exchangeOutflows++;
    }

    let signalScore = 0;
    if (receives > sends) signalScore += 20;
    if (sends > receives) signalScore -= 20;
    if (exchangeInflows > exchangeOutflows) signalScore += 30;
    if (exchangeOutflows > exchangeInflows) signalScore -= 30;
    if (balanceNum > 10) signalScore += 10;
    if (recentTxs.length > 10) signalScore += 10;
    signalScore = Math.max(-100, Math.min(100, signalScore));

    let signal: WalletAnalysis['signal'] = 'NEUTRAL';
    if (signalScore >= 30) signal = 'ACCUMULATING';
    else if (signalScore <= -30) signal = 'DISTRIBUTING';
    else if (txList.length === 0) signal = 'INACTIVE';

    const exchangeLabel = labelAddress(address);
    const lastTx = txList[0];
    const lastActivityAt = lastTx
      ? new Date(parseInt(lastTx.timeStamp) * 1000).toISOString()
      : null;

    const summary = `Wallet holds ${ethBalance} ETH (${ethBalanceUsd ? `~$${ethBalanceUsd.toLocaleString()}` : 'price unavailable'}). ${recentTxs.length} transactions in the last 30 days. Signal: ${signal} (score: ${signalScore}).`;

    const result: WalletAnalysis = {
      address,
      chain,
      ethBalance,
      ethBalanceUsd,
      txCount: txList.length,
      recentTxCount: recentTxs.length,
      signal,
      signalScore,
      exchangeLabel,
      lastActivityAt,
      summary,
    };

    logger.info({ address, chain, signal, signalScore }, 'wallet/analyze');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message, address, chain }, 'wallet/analyze error');
    res.status(500).json({ error: 'Failed to analyze wallet', details: err.message });
  }
});

// GET /v1/wallet/signals  (AI-powered)
router.get('/signals', validate(signalsSchema), async (req: Request, res: Response): Promise<void> => {
  const { address, chain } = req.query as { address: string; chain: string };

  try {
    const ethBalance = await getEthBalance(address, chain);
    const ethPrice = await getEthPrice();
    const txList = await getTxList(address, chain, 100);
    const tokenTransfers = await getTokenTransfers(address, chain, 100);

    const balanceNum = parseFloat(ethBalance);
    const ethBalanceUsd = ethPrice ? Math.round(balanceNum * ethPrice) : null;

    const thirtyDaysAgo = Math.floor(Date.now() / 1000) - 30 * 24 * 3600;
    const recentTxs = txList.filter((tx: any) => parseInt(tx.timeStamp) > thirtyDaysAgo);

    const sends = txList.filter((tx: any) => tx.from.toLowerCase() === address.toLowerCase()).length;
    const receives = txList.filter((tx: any) => tx.to?.toLowerCase() === address.toLowerCase()).length;

    const labeledInteractions: string[] = [];
    for (const tx of txList.slice(0, 20)) {
      const fromLabel = labelAddress(tx.from);
      const toLabel = labelAddress(tx.to || '');
      const valueEth = (parseInt(tx.value) / 1e18).toFixed(4);
      if (fromLabel || toLabel) {
        labeledInteractions.push(
          `${fromLabel || tx.from.slice(0, 8)} → ${toLabel || tx.to?.slice(0, 8)} (${valueEth} ETH)`
        );
      }
    }

    const tokenCounts: Record<string, number> = {};
    for (const t of tokenTransfers.slice(0, 50)) {
      tokenCounts[t.tokenSymbol] = (tokenCounts[t.tokenSymbol] || 0) + 1;
    }
    const topTokens = Object.entries(tokenCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([sym, count]) => `${sym}(${count})`);

    const context = `
Wallet: ${address} on ${chain}
ETH Balance: ${ethBalance} ETH (~$${ethBalanceUsd?.toLocaleString() || 'unknown'})
Total transactions: ${txList.length}
Recent (30d) transactions: ${recentTxs.length}
Sends: ${sends}, Receives: ${receives}
Exchange interactions (recent 20 txs): ${labeledInteractions.slice(0, 5).join('; ') || 'none detected'}
Top token activity: ${topTokens.join(', ') || 'none'}
Known exchange wallet: ${labelAddress(address) || 'no'}
`;

    const aiPrompt = `You are an onchain intelligence analyst. Analyze this Ethereum wallet's activity and provide a signal assessment.

${context}

Respond in this exact JSON format (no markdown, just JSON):
{
  "signalScore": <number from -100 to 100>,
  "signal": "<STRONG_BUY|BUY|NEUTRAL|SELL|STRONG_SELL>",
  "confidence": "<HIGH|MEDIUM|LOW>",
  "narrative": "<2-3 sentence interpretation of wallet behavior>",
  "keyFactors": ["<factor1>", "<factor2>", "<factor3>"],
  "recommendation": "<one actionable sentence>"
}`;

    const aiResponse = await callAI(aiPrompt);

    let parsed: any;
    try {
      const cleaned = aiResponse.replace(/```json|```/g, '').trim();
      parsed = JSON.parse(cleaned);
    } catch {
      parsed = {
        signalScore: 0,
        signal: 'NEUTRAL',
        confidence: 'LOW',
        narrative: aiResponse,
        keyFactors: ['AI parsing error - raw analysis provided'],
        recommendation: 'Review raw narrative for manual interpretation.',
      };
    }

    const result: WalletSignal = {
      address,
      chain,
      signalScore: parsed.signalScore,
      signal: parsed.signal,
      confidence: parsed.confidence,
      narrative: parsed.narrative,
      keyFactors: parsed.keyFactors || [],
      recommendation: parsed.recommendation,
      analyzedAt: new Date().toISOString(),
    };

    logger.info({ address, chain, signal: result.signal }, 'wallet/signals');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message, address, chain }, 'wallet/signals error');
    res.status(500).json({ error: 'Failed to generate wallet signals', details: err.message });
  }
});

export default router;