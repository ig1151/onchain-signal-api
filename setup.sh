#!/bin/bash
set -e

echo "🔧 Setting up onchain-signal-api..."

# ── package.json ──────────────────────────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "onchain-signal-api",
  "version": "1.0.0",
  "description": "Onchain wallet intelligence — whale signals, token flows, accumulation/distribution for AI agents",
  "main": "dist/index.js",
  "scripts": {
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.7.2",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.3.1",
    "helmet": "^7.1.0",
    "joi": "^17.13.1"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.4.5"
  }
}
EOF

# ── tsconfig.json ─────────────────────────────────────────────────────────────
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

# ── render.yaml ───────────────────────────────────────────────────────────────
cat > render.yaml << 'EOF'
services:
  - type: web
    name: onchain-signal-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 3000
      - key: ETHERSCAN_API_KEY
        sync: false
      - key: OPENROUTER_API_KEY
        sync: false
      - key: COINGECKO_API_KEY
        sync: false
EOF

# ── .gitignore ────────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
node_modules/
dist/
.env
*.log
EOF

# ── .env.example ─────────────────────────────────────────────────────────────
cat > .env.example << 'EOF'
PORT=3000
NODE_ENV=development
ETHERSCAN_API_KEY=your_etherscan_api_key
OPENROUTER_API_KEY=your_openrouter_api_key
COINGECKO_API_KEY=your_coingecko_api_key_optional
EOF

# ── src/ structure ────────────────────────────────────────────────────────────
mkdir -p src/routes src/services src/middleware src/types

# ── src/logger.ts ─────────────────────────────────────────────────────────────
cat > src/logger.ts << 'EOF'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
EOF

# ── src/types/index.ts ────────────────────────────────────────────────────────
cat > src/types/index.ts << 'EOF'
export interface WalletAnalysis {
  address: string;
  chain: string;
  ethBalance: string;
  ethBalanceUsd: number | null;
  txCount: number;
  recentTxCount: number;
  signal: 'ACCUMULATING' | 'DISTRIBUTING' | 'NEUTRAL' | 'INACTIVE';
  signalScore: number; // -100 (bearish) to +100 (bullish)
  exchangeLabel: string | null;
  lastActivityAt: string | null;
  summary: string;
}

export interface WhaleTransfer {
  txHash: string;
  from: string;
  to: string;
  fromLabel: string | null;
  toLabel: string | null;
  valueEth: string;
  valueUsd: number | null;
  direction: 'EXCHANGE_INFLOW' | 'EXCHANGE_OUTFLOW' | 'WALLET_TO_WALLET';
  sentiment: 'BEARISH' | 'BULLISH' | 'NEUTRAL';
  timestamp: string;
  chain: string;
}

export interface TokenFlows {
  token: string;
  contractAddress: string;
  chain: string;
  timeframe: string;
  exchangeInflow: number;
  exchangeOutflow: number;
  netFlow: number;
  sentiment: 'SELL_PRESSURE' | 'ACCUMULATION' | 'NEUTRAL';
  sentimentScore: number;
  topMovers: Array<{
    address: string;
    label: string | null;
    amount: number;
    direction: 'IN' | 'OUT';
  }>;
  summary: string;
}

export interface WalletSignal {
  address: string;
  chain: string;
  signalScore: number;
  signal: string;
  confidence: 'HIGH' | 'MEDIUM' | 'LOW';
  narrative: string;
  keyFactors: string[];
  recommendation: string;
  analyzedAt: string;
}
EOF

# ── src/services/etherscan.ts ─────────────────────────────────────────────────
cat > src/services/etherscan.ts << 'EOF'
import axios from 'axios';
import { logger } from '../logger';

const BASE_URL = 'https://api.etherscan.io/v2/api';

// Known exchange addresses for labeling
const EXCHANGE_LABELS: Record<string, string> = {
  '0x28c6c06298d514db089934071355e5743bf21d60': 'Binance Hot Wallet',
  '0x21a31ee1afc51d94c2efccaa2092ad1028285549': 'Binance Hot Wallet 2',
  '0xdfd5293d8e347dfe59e90efd55b2956a1343963d': 'Binance Hot Wallet 3',
  '0xa9d1e08c7793af67e9d92fe308d5697fb81d3e43': 'Coinbase',
  '0x71660c4005ba85c37ccec55d0c4493e66fe775d3': 'Coinbase 2',
  '0x503828976d22510aad0201ac7ec88293211d23da': 'Coinbase 3',
  '0xddfabcdc4d8ffc6d5beaf154f18b778f892a0740': 'Coinbase 4',
  '0x3cd751e6b0078be393132286c442345e5dc49699': 'Coinbase 5',
  '0xb739d0895772dbb71a89a3754a160269068f0d45': 'Kraken',
  '0x2910543af39aba0cd09dbb2d50200b3e800a63d2': 'Kraken 2',
  '0x0a869d79a7052c7f1b55a8ebabbea3420f0d1e13': 'Kraken 3',
  '0xe853c56864a2ebe4576a807d26fdc4a0ada51919': 'Kraken 4',
  '0xae2d4617c862309a3d75a0ffb358c7a5009c673f': 'Kraken 5',
  '0x43984d578803891dfa9706bdeee6078d80cfc79e': 'OKX',
  '0x5041ed759dd4afc3a72b8192c143f72f4724081f': 'OKX 2',
  '0x6cc5f688a315f3dc28a7781717a9a798a59fda7b': 'OKX 3',
  '0xf89d7b9c864f589bbf53a82105107622b35eaa40': 'Bybit',
};

function getChainId(chain: string): number {
  const chainMap: Record<string, number> = {
    ethereum: 1,
    base: 8453,
    arbitrum: 42161,
    polygon: 137,
    optimism: 10,
    bsc: 56,
  };
  return chainMap[chain.toLowerCase()] || 1;
}

export function labelAddress(address: string): string | null {
  return EXCHANGE_LABELS[address.toLowerCase()] || null;
}

export async function getEthBalance(address: string, chain = 'ethereum'): Promise<string> {
  const chainId = getChainId(chain);
  const res = await axios.get(BASE_URL, {
    params: {
      chainid: chainId,
      module: 'account',
      action: 'balance',
      address,
      tag: 'latest',
      apikey: process.env.ETHERSCAN_API_KEY,
    },
    timeout: 8000,
  });
  if (res.data.status !== '1') {
    logger.warn({ address, result: res.data.result }, 'Etherscan balance warning');
    return '0';
  }
  // Convert from wei to ETH
  const wei = BigInt(res.data.result);
  const eth = Number(wei) / 1e18;
  return eth.toFixed(6);
}

export async function getTxList(address: string, chain = 'ethereum', limit = 50): Promise<any[]> {
  const chainId = getChainId(chain);
  const res = await axios.get(BASE_URL, {
    params: {
      chainid: chainId,
      module: 'account',
      action: 'txlist',
      address,
      startblock: 0,
      endblock: 99999999,
      page: 1,
      offset: limit,
      sort: 'desc',
      apikey: process.env.ETHERSCAN_API_KEY,
    },
    timeout: 10000,
  });
  if (res.data.status !== '1') return [];
  return res.data.result || [];
}

export async function getTokenTransfers(address: string, chain = 'ethereum', limit = 100): Promise<any[]> {
  const chainId = getChainId(chain);
  const res = await axios.get(BASE_URL, {
    params: {
      chainid: chainId,
      module: 'account',
      action: 'tokentx',
      address,
      startblock: 0,
      endblock: 99999999,
      page: 1,
      offset: limit,
      sort: 'desc',
      apikey: process.env.ETHERSCAN_API_KEY,
    },
    timeout: 10000,
  });
  if (res.data.status !== '1') return [];
  return res.data.result || [];
}

export async function getTokenTransfersByContract(
  contractAddress: string,
  chain = 'ethereum',
  limit = 200
): Promise<any[]> {
  const chainId = getChainId(chain);
  const res = await axios.get(BASE_URL, {
    params: {
      chainid: chainId,
      module: 'account',
      action: 'tokentx',
      contractaddress: contractAddress,
      startblock: 0,
      endblock: 99999999,
      page: 1,
      offset: limit,
      sort: 'desc',
      apikey: process.env.ETHERSCAN_API_KEY,
    },
    timeout: 12000,
  });
  if (res.data.status !== '1') return [];
  return res.data.result || [];
}

export async function getEthPrice(): Promise<number | null> {
  try {
    const res = await axios.get(BASE_URL, {
      params: {
        chainid: 1,
        module: 'stats',
        action: 'ethprice',
        apikey: process.env.ETHERSCAN_API_KEY,
      },
      timeout: 5000,
    });
    if (res.data.status === '1') {
      return parseFloat(res.data.result.ethusd);
    }
  } catch (e) {
    logger.warn({}, 'Failed to fetch ETH price');
  }
  return null;
}
EOF

# ── src/services/ai.ts ────────────────────────────────────────────────────────
cat > src/services/ai.ts << 'EOF'
import axios from 'axios';
import { logger } from '../logger';

type Messages = string | { role: string; content: string }[];

export async function callAI(input: Messages, systemPrompt?: string): Promise<string> {
  const messages: { role: string; content: string }[] = typeof input === 'string'
    ? [{ role: 'user', content: input }]
    : input;

  const body: Record<string, unknown> = {
    model: 'anthropic/claude-sonnet-4-5',
    max_tokens: 1000,
    messages,
  };
  if (systemPrompt) {
    body.system = systemPrompt;
  }

  const res = await axios.post(
    'https://openrouter.ai/api/v1/chat/completions',
    body,
    {
      headers: {
        Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
      },
      timeout: 20000,
    }
  );

  const data = res.data as { choices: { message: { content: string } }[] };
  return data.choices[0].message.content;
}
EOF

# ── src/middleware/validate.ts ────────────────────────────────────────────────
cat > src/middleware/validate.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';

export function validate(schema: Joi.ObjectSchema) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const { error } = schema.validate(req.query);
    if (error) {
      res.status(400).json({
        error: 'Validation error',
        details: error.details.map((d) => d.message),
      });
      return;
    }
    next();
  };
}
EOF

# ── src/routes/health.ts ──────────────────────────────────────────────────────
cat > src/routes/health.ts << 'EOF'
import { Router, Request, Response } from 'express';

const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'onchain-signal-api',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

export default router;
EOF

# ── src/routes/wallet.ts ──────────────────────────────────────────────────────
cat > src/routes/wallet.ts << 'EOF'
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
    const [ethBalance, txList, tokenTransfers, ethPrice] = await Promise.all([
      getEthBalance(address, chain),
      getTxList(address, chain, 50),
      getTokenTransfers(address, chain, 50),
      getEthPrice(),
    ]);

    const balanceNum = parseFloat(ethBalance);
    const ethBalanceUsd = ethPrice ? Math.round(balanceNum * ethPrice) : null;

    // Analyze recent activity (last 30 days)
    const thirtyDaysAgo = Math.floor(Date.now() / 1000) - 30 * 24 * 3600;
    const recentTxs = txList.filter((tx: any) => parseInt(tx.timeStamp) > thirtyDaysAgo);

    // Count sends vs receives for signal
    const sends = txList.filter((tx: any) => tx.from.toLowerCase() === address.toLowerCase()).length;
    const receives = txList.filter((tx: any) => tx.to?.toLowerCase() === address.toLowerCase()).length;

    // Exchange inflow/outflow detection
    let exchangeInflows = 0;
    let exchangeOutflows = 0;
    for (const tx of txList.slice(0, 30)) {
      const fromLabel = labelAddress(tx.from);
      const toLabel = labelAddress(tx.to || '');
      if (fromLabel) exchangeInflows++;
      if (toLabel) exchangeOutflows++;
    }

    // Compute signal
    let signalScore = 0;
    if (receives > sends) signalScore += 20;
    if (sends > receives) signalScore -= 20;
    if (exchangeInflows > exchangeOutflows) signalScore += 30; // receiving from exchange = accumulating
    if (exchangeOutflows > exchangeInflows) signalScore -= 30; // sending to exchange = distributing
    if (balanceNum > 10) signalScore += 10;
    if (recentTxs.length > 10) signalScore += 10; // active wallet
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

    const summary = `Wallet holds ${ethBalance} ETH (${ethBalanceUsd ? `~$${ethBalanceUsd.toLocaleString()}` : 'price unavailable'}). ${
      recentTxs.length
    } transactions in the last 30 days. Signal: ${signal} (score: ${signalScore}).`;

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
    const [ethBalance, txList, tokenTransfers, ethPrice] = await Promise.all([
      getEthBalance(address, chain),
      getTxList(address, chain, 100),
      getTokenTransfers(address, chain, 100),
      getEthPrice(),
    ]);

    const balanceNum = parseFloat(ethBalance);
    const ethBalanceUsd = ethPrice ? Math.round(balanceNum * ethPrice) : null;

    // Build context for AI
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

    // Top token activity
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
EOF

# ── src/routes/whale.ts ───────────────────────────────────────────────────────
cat > src/routes/whale.ts << 'EOF'
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
EOF

# ── src/routes/token.ts ───────────────────────────────────────────────────────
cat > src/routes/token.ts << 'EOF'
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
EOF

# ── src/routes/docs.ts ────────────────────────────────────────────────────────
cat > src/routes/docs.ts << 'EOF'
import { Router, Request, Response } from 'express';

const router = Router();

const openApiSpec = {
  openapi: '3.0.0',
  info: {
    title: 'Onchain Signal API',
    version: '1.0.0',
    description:
      'Onchain wallet intelligence — whale signals, token flows, and accumulation/distribution analysis for AI agents and traders. Powered by Etherscan V2 + Claude AI.',
    contact: { url: 'https://orbisapi.com' },
  },
  servers: [{ url: 'https://onchain-signal-api.onrender.com' }],
  paths: {
    '/v1/health': {
      get: {
        summary: 'Health check',
        operationId: 'health',
        responses: {
          200: { description: 'Service is healthy' },
        },
      },
    },
    '/v1/wallet/analyze': {
      get: {
        summary: 'Analyze wallet — balance, tx pattern, accumulation/distribution signal',
        operationId: 'walletAnalyze',
        parameters: [
          { name: 'address', in: 'query', required: true, schema: { type: 'string' }, description: 'EVM wallet address (0x...)' },
          { name: 'chain', in: 'query', schema: { type: 'string', enum: ['ethereum', 'base', 'arbitrum', 'polygon', 'optimism', 'bsc'], default: 'ethereum' } },
        ],
        responses: {
          200: {
            description: 'Wallet analysis with signal score',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    success: { type: 'boolean' },
                    data: {
                      type: 'object',
                      properties: {
                        address: { type: 'string' },
                        chain: { type: 'string' },
                        ethBalance: { type: 'string' },
                        ethBalanceUsd: { type: 'number', nullable: true },
                        txCount: { type: 'number' },
                        recentTxCount: { type: 'number' },
                        signal: { type: 'string', enum: ['ACCUMULATING', 'DISTRIBUTING', 'NEUTRAL', 'INACTIVE'] },
                        signalScore: { type: 'number', description: '-100 (bearish) to +100 (bullish)' },
                        exchangeLabel: { type: 'string', nullable: true },
                        lastActivityAt: { type: 'string', nullable: true },
                        summary: { type: 'string' },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
    '/v1/wallet/signals': {
      get: {
        summary: 'AI-powered wallet signal — full narrative, score, and trading recommendation',
        operationId: 'walletSignals',
        parameters: [
          { name: 'address', in: 'query', required: true, schema: { type: 'string' } },
          { name: 'chain', in: 'query', schema: { type: 'string', enum: ['ethereum', 'base', 'arbitrum', 'polygon', 'optimism', 'bsc'], default: 'ethereum' } },
        ],
        responses: {
          200: {
            description: 'AI-interpreted wallet signal',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    success: { type: 'boolean' },
                    data: {
                      type: 'object',
                      properties: {
                        address: { type: 'string' },
                        chain: { type: 'string' },
                        signalScore: { type: 'number' },
                        signal: { type: 'string', enum: ['STRONG_BUY', 'BUY', 'NEUTRAL', 'SELL', 'STRONG_SELL'] },
                        confidence: { type: 'string', enum: ['HIGH', 'MEDIUM', 'LOW'] },
                        narrative: { type: 'string' },
                        keyFactors: { type: 'array', items: { type: 'string' } },
                        recommendation: { type: 'string' },
                        analyzedAt: { type: 'string' },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
    '/v1/whale/recent': {
      get: {
        summary: 'Recent whale transfers — large token movements with exchange labels and sentiment',
        operationId: 'whaleRecent',
        parameters: [
          { name: 'token', in: 'query', schema: { type: 'string', enum: ['USDC', 'USDT', 'WETH', 'DAI'], default: 'USDC' } },
          { name: 'minUsd', in: 'query', schema: { type: 'number', default: 50000 }, description: 'Minimum USD value filter' },
          { name: 'chain', in: 'query', schema: { type: 'string', enum: ['ethereum', 'base'], default: 'ethereum' } },
          { name: 'limit', in: 'query', schema: { type: 'number', default: 20 } },
        ],
        responses: {
          200: { description: 'List of whale transfers with sentiment' },
        },
      },
    },
    '/v1/token/flows': {
      get: {
        summary: 'Token exchange flow analysis — inflow/outflow sell pressure or accumulation',
        operationId: 'tokenFlows',
        parameters: [
          { name: 'contract', in: 'query', required: true, schema: { type: 'string' }, description: 'Token contract address' },
          { name: 'chain', in: 'query', schema: { type: 'string', enum: ['ethereum', 'base', 'arbitrum', 'polygon'], default: 'ethereum' } },
          { name: 'timeframe', in: 'query', schema: { type: 'string', enum: ['1h', '4h', '24h', '7d'], default: '24h' } },
          { name: 'decimals', in: 'query', schema: { type: 'number', default: 18 } },
        ],
        responses: {
          200: { description: 'Token flow analysis with AI summary' },
        },
      },
    },
  },
};

router.get('/openapi.json', (_req: Request, res: Response) => {
  res.json(openApiSpec);
});

router.get('/docs', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html>
<head>
  <title>Onchain Signal API — Docs</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.11.0/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.11.0/swagger-ui-bundle.js"></script>
<script>
  SwaggerUIBundle({
    url: '/openapi.json',
    dom_id: '#swagger-ui',
    presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
    layout: 'BaseLayout'
  });
</script>
</body>
</html>`);
});

export default router;
EOF

# ── src/index.ts ──────────────────────────────────────────────────────────────
cat > src/index.ts << 'EOF'
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import healthRouter from './routes/health';
import walletRouter from './routes/wallet';
import whaleRouter from './routes/whale';
import tokenRouter from './routes/token';
import docsRouter from './routes/docs';

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use(limiter);

// Routes
app.use('/v1/health', healthRouter);
app.use('/v1/wallet', walletRouter);
app.use('/v1/whale', whaleRouter);
app.use('/v1/token', tokenRouter);
app.use('/', docsRouter);

// 404
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Start
app.listen(PORT, () => {
  logger.info({ port: PORT }, 'onchain-signal-api started');
});

export default app;
EOF

echo ""
echo "✅ onchain-signal-api scaffold complete!"
echo ""
echo "Next steps:"
echo "  1. npm install"
echo "  2. cp .env.example .env && fill in keys"
echo "  3. npm run dev"
echo "  4. npm run build && npm start"
echo ""
echo "Endpoints:"
echo "  GET /v1/health"
echo "  GET /v1/wallet/analyze?address=0x...&chain=ethereum"
echo "  GET /v1/wallet/signals?address=0x...&chain=ethereum   (AI)"
echo "  GET /v1/whale/recent?token=USDC&minUsd=50000"
echo "  GET /v1/token/flows?contract=0x...&timeframe=24h      (AI)"
echo "  GET /docs"
echo "  GET /openapi.json"