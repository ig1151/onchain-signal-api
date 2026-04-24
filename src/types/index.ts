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
