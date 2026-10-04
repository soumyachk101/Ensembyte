import http from 'http';
import { WebSocketServer } from 'ws';

const PORT = 8765;
const PAIRING_CODE = '123456';

const sampleThreadId = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d';
const sampleProjectId = '00000000-0000-0000-0000-000000000000';

const sampleThreads = [
  {
    id: sampleThreadId,
    projectID: sampleProjectId,
    projectName: 'Swarm Code',
    title: 'Mobile Companion Setup',
    provider: 'anthropic',
    model: 'claude-3-7-sonnet',
    lastStatus: 'completed',
    hasUnread: false,
    updatedAt: new Date().toISOString(),
    messageCount: 2,
    lastMessagePreview: 'Swarm Code Mobile is now live and paired with your Mac.'
  }
];

const sampleThreadDetail = {
  id: sampleThreadId,
  projectID: sampleProjectId,
  projectPath: '/Users/soumyachakraborty/Documents/Ensembyte-swift',
  title: 'Mobile Companion Setup',
  provider: 'anthropic',
  model: 'claude-3-7-sonnet',
  runtimeMode: 'local',
  createdAt: new Date(Date.now() - 3600000).toISOString(),
  updatedAt: new Date().toISOString(),
  diffRevision: 1,
  approvals: [],
  entries: [
    {
      id: 'entry-1',
      kind: 'user',
      date: new Date(Date.now() - 3600000).toISOString(),
      text: 'Connect Swarm Code Mobile companion app to my Mac',
      name: null,
      input: null,
      output: null,
      error: null,
      summary: null
    },
    {
      id: 'entry-2',
      kind: 'assistant',
      date: new Date().toISOString(),
      text: 'Swarm Code Mobile is connected and communicating with your Mac over WebSocket. You can send messages, inspect threads, and manage coding agents from your phone!',
      name: null,
      input: null,
      output: null,
      error: null,
      summary: null
    }
  ]
};

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const url = req.url || '';

  if (url === '/api/v1/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      version: '1.1.10',
      threadCount: sampleThreads.length,
      paired: true,
      connectedClients: wss.clients.size
    }));
    return;
  }

  if (url === '/api/v1/threads') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(sampleThreads));
    return;
  }

  if (url.startsWith('/api/v1/threads/')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(sampleThreadDetail));
    return;
  }

  if (url === '/api/v1/models') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      providers: {
        anthropic: {
          id: 'anthropic',
          name: 'Anthropic Claude',
          models: ['claude-3-7-sonnet', 'claude-3-5-sonnet', 'claude-3-5-haiku']
        },
        openai: {
          id: 'openai',
          name: 'OpenAI',
          models: ['gpt-4o', 'o3-mini', 'gpt-4.5-preview']
        }
      }
    }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

const wss = new WebSocketServer({ server, path: '/ws/v1/stream' });

wss.on('connection', (ws) => {
  console.log('✓ Swarm Code Mobile connected over WebSocket!');

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log('Received event from mobile:', msg);

      if (msg.type === 'pair') {
        // Accept pairing code
        console.log(`Pairing code received: ${msg.code}. Pairing successful!`);
        ws.send(JSON.stringify({
          type: 'paired',
          sessionToken: 'swarm_session_' + Date.now()
        }));
      } else if (msg.type === 'sendMessage') {
        // Echo reply streaming
        const threadID = msg.threadID || sampleThreadId;
        setTimeout(() => {
          ws.send(JSON.stringify({
            type: 'messageDelta',
            threadID: threadID,
            content: `Echo from Swarm Code: "${msg.content}"`,
            isTool: false
          }));
        }, 300);

        setTimeout(() => {
          ws.send(JSON.stringify({
            type: 'messageComplete',
            threadID: threadID,
            messageID: 'msg_' + Date.now()
          }));
        }, 800);
      }
    } catch (err) {
      console.error('Error handling WS message:', err);
    }
  });

  ws.on('close', () => {
    console.log('Mobile client disconnected');
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=========================================`);
  console.log(`  Swarm Code Bridge Server LIVE on port ${PORT}`);
  console.log(`  Pairing Code: ${PAIRING_CODE} (any 6 digits will work)`);
  console.log(`=========================================`);
});
