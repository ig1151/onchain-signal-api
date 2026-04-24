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
