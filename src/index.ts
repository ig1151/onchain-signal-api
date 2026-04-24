import 'dotenv/config';
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
