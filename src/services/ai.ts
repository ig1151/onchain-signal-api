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
