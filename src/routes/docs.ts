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
