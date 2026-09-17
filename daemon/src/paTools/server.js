#!/usr/bin/env node
'use strict';
/*
 * server.js — the MCP server the PA's `claude -p` calls get via --mcp-config (see
 * ../paBridge.js and mcp-config.json). Gives the agent real tools instead of us parsing
 * its text for "intent" — it decides when to call these, we just execute them.
 *
 * Panel tools (start_pomodoro) reach the running panel through the SAME
 * `omarchy-shell quake-panel <method>` IPC surface ops/bin/omarchy-quake-panel-toggle
 * already uses — no separate code path invented just for the agent.
 *
 * Home Assistant tools (Phase D) are different in one important way: every one of them
 * is either read-only (list_ha_entities) or requires a SEPARATE, later confirm_pending_
 * action call before anything actually happens — propose_ha_action only ever records
 * what's being asked for, never performs it. This is enforced here in code, not left to
 * the model's own judgment to "ask first": a smart-home action is enough more
 * consequential than starting a Pomodoro timer that a misheard command shouldn't be
 * able to execute it in one shot. See HISTORY.md for the design.
 *
 * This process is spawned fresh per `claude -p` call (stdio transport, whatever process
 * the CLI wants), so it holds no in-memory state of its own between turns — the pending-
 * action gate's state has to live on disk (PENDING_ACTION_FILE) instead, and everything
 * else routes to state that already lives elsewhere (the panel's own QML state, Home
 * Assistant's own state).
 *
 * MIT-licensed: pure process orchestration, no device protocol.
 */
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { execFile } = require('child_process');
const { z } = require('zod');
const fs = require('fs');
const os = require('os');
const path = require('path');

function callPanel(method) {
  return new Promise(resolve => {
    execFile('omarchy-shell', ['quake-panel', method], { timeout: 5000 }, (err, stdout, stderr) => {
      if (err) resolve({ ok: false, message: (stderr || err.message).trim() });
      else resolve({ ok: true, message: stdout.trim() });
    });
  });
}

function toolResult(text, isError) {
  return { content: [{ type: 'text', text }], isError: !!isError };
}

// ---- Home Assistant -------------------------------------------------------------

// ~/.config/omarchy-quake-panel/config.json, not the repo's config/config.example.json
// — the same live-vs-example split Pages/HomeAssistantPage.qml already established for
// this same url/token pair, kept outside git on purpose (see NOTICE/README): a
// long-lived access token is a real credential, not project source.
const CONFIG_FILE = path.join(os.homedir(), '.config', 'omarchy-quake-panel', 'config.json');
const PENDING_ACTION_FILE = path.join(os.tmpdir(), 'omarchy-quake-panel-pa-pending-ha-action.json');
const PENDING_ACTION_TTL_MS = 2 * 60 * 1000; // a stale "yes" from an unrelated later turn should never fire an old action

// ---- persistent memory -----------------------------------------------------------

// Same persisted-state directory Service.qml/PersonalCareState.qml/KnobLighting.qml
// already use for their own state files — plain JSON, no shared library between QML
// and these Node-side tools, just an agreed-upon path/shape (this project's existing
// style; paBridge.js reads this exact same file to inject memories into every turn's
// system prompt, see its own comment there for why that's passive/automatic rather
// than requiring a tool call to recall anything already known).
const MEMORY_FILE = path.join(os.homedir(), '.local', 'state', 'omarchy-quake-panel', 'foxy-memory.json');
const MEMORY_MAX_ENTRIES = 40; // oldest dropped silently past this — a small, bounded prompt addition, not an ever-growing one

function loadMemory() {
  try {
    const parsed = JSON.parse(fs.readFileSync(MEMORY_FILE, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    return [];
  }
}

function saveMemory(entries) {
  fs.mkdirSync(path.dirname(MEMORY_FILE), { recursive: true });
  fs.writeFileSync(MEMORY_FILE, JSON.stringify(entries, null, 2));
}

// Every domain/service pair the agent may even PROPOSE — anything else is rejected
// before a pending action is ever written, regardless of what the model asks for.
// Deliberately not a generic "call any Home Assistant service" tool: this is a voice
// interface fed by speech-to-text, and the whole point of the confirm gate is undercut
// if the thing being confirmed could be arbitrary. Scoped to what the user actually
// asked FOXY to be able to control.
const HA_ALLOWED_SERVICES = {
  light: ['turn_on', 'turn_off', 'toggle'],
  switch: ['turn_on', 'turn_off', 'toggle'],
  climate: ['turn_on', 'turn_off', 'set_temperature', 'set_hvac_mode'],
  lock: ['lock', 'unlock'],
};

function loadHaConfig() {
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    const ha = cfg.homeAssistant || {};
    if (!ha.url || !ha.token) return null;
    return { url: String(ha.url).replace(/\/+$/, ''), token: String(ha.token) };
  } catch (e) {
    return null;
  }
}

async function haRequest(ha, method, apiPath, body) {
  const res = await fetch(ha.url + apiPath, {
    method,
    headers: {
      Authorization: `Bearer ${ha.token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Home Assistant returned ${res.status}${detail ? ': ' + detail.slice(0, 200) : ''}`);
  }
  return res.json().catch(() => null);
}

function readPendingAction() {
  try {
    const pending = JSON.parse(fs.readFileSync(PENDING_ACTION_FILE, 'utf8'));
    if (Date.now() - pending.proposedAt > PENDING_ACTION_TTL_MS) return { expired: true };
    return { pending };
  } catch (e) {
    return {};
  }
}

function clearPendingAction() {
  try { fs.unlinkSync(PENDING_ACTION_FILE); } catch (e) { /* already gone */ }
}

const server = new McpServer({ name: 'quake-panel', version: '0.1.0' });

server.registerTool(
  'start_pomodoro',
  {
    title: 'Start Pomodoro',
    description: 'Starts the pomodoro focus timer on the panel. Does nothing if a session is already running.',
  },
  async () => {
    const result = await callPanel('startPomodoro');
    return result.ok
      ? toolResult('Pomodoro started.')
      : toolResult(`Failed to start the pomodoro: ${result.message}`, true);
  }
);

server.registerTool(
  'remember_fact',
  {
    title: 'Remember a fact',
    description: 'Saves a short fact about the user for future conversations — a preference, a routine, ' +
      'something worth knowing later. Not shown to the user; it just becomes part of what you already know ' +
      'in later conversations. Use your own judgment about what is worth saving; no need to ask permission ' +
      'first for ordinary personal facts.',
    inputSchema: {
      fact: z.string().describe('A short, self-contained fact, e.g. "Prefers the office at 21 degrees."'),
    },
  },
  async ({ fact }) => {
    const entries = loadMemory();
    entries.push({ text: fact, savedAt: Date.now() });
    while (entries.length > MEMORY_MAX_ENTRIES) entries.shift();
    saveMemory(entries);
    return toolResult('Remembered.');
  }
);

server.registerTool(
  'forget_fact',
  {
    title: 'Forget a remembered fact',
    description: 'Removes a previously remembered fact — use when the user asks you to forget something or ' +
      'corrects a fact you got wrong. Matches by substring against what was saved, not by exact wording.',
    inputSchema: {
      query: z.string().describe('Text to match against remembered facts, e.g. "office temperature".'),
    },
  },
  async ({ query }) => {
    const entries = loadMemory();
    const q = query.toLowerCase();
    const removed = entries.filter(e => e.text.toLowerCase().includes(q));
    if (removed.length === 0) return toolResult('Nothing matched that.');
    saveMemory(entries.filter(e => !e.text.toLowerCase().includes(q)));
    return toolResult(`Forgot: ${removed.map(e => e.text).join('; ')}`);
  }
);

server.registerTool(
  'list_remembered_facts',
  {
    title: 'List remembered facts',
    description: 'Returns everything currently remembered about the user — use when they ask what you remember or know about them.',
  },
  async () => {
    const entries = loadMemory();
    if (entries.length === 0) return toolResult('Nothing remembered yet.');
    return toolResult(JSON.stringify(entries.map(e => e.text)));
  }
);

server.registerTool(
  'list_ha_entities',
  {
    title: 'List Home Assistant devices',
    description: 'Look up real Home Assistant entities (lights, switches, climate, locks) by domain, ' +
      'so a request like "turn off the living room light" can be matched to the actual entity_id and ' +
      'current state before proposing an action. Always call this before propose_ha_action unless you ' +
      'already know the exact entity_id from earlier in this conversation.',
    inputSchema: {
      domain: z.enum(['light', 'switch', 'climate', 'lock']).optional()
        .describe('Restrict to one domain. Omit to list all four controllable domains at once.'),
    },
  },
  async ({ domain }) => {
    const ha = loadHaConfig();
    if (!ha) return toolResult('Home Assistant is not configured on this panel yet.', true);
    let states;
    try {
      states = await haRequest(ha, 'GET', '/api/states');
    } catch (e) {
      return toolResult(`Could not reach Home Assistant: ${e.message}`, true);
    }
    const domains = domain ? [domain] : Object.keys(HA_ALLOWED_SERVICES);
    const entities = states
      .filter(s => domains.includes(s.entity_id.split('.')[0]))
      .map(s => {
        const row = { entity_id: s.entity_id, name: s.attributes.friendly_name || s.entity_id, state: s.state };
        if (s.entity_id.startsWith('climate.')) {
          if (s.attributes.current_temperature !== undefined) row.current_temperature = s.attributes.current_temperature;
          if (s.attributes.temperature !== undefined) row.target_temperature = s.attributes.temperature;
        }
        return row;
      });
    if (entities.length === 0) return toolResult('No matching entities found.');
    return toolResult(JSON.stringify(entities));
  }
);

server.registerTool(
  'propose_ha_action',
  {
    title: 'Propose a Home Assistant action',
    description: 'Records a smart-home action for the user to confirm — this does NOT perform it yet. ' +
      'Tell the user what you are about to do and ask them to confirm; only call confirm_pending_action ' +
      'after they clearly say yes in a following message. Look up the real entity_id with ' +
      'list_ha_entities first if you do not already have it.',
    inputSchema: {
      entity_id: z.string().describe('Exact Home Assistant entity_id, e.g. "light.living_room".'),
      service: z.string().describe('Service to call, e.g. "turn_on", "turn_off", "toggle", "set_temperature", "lock", "unlock".'),
      data: z.record(z.string(), z.any()).optional().describe('Extra service data, e.g. {"temperature": 21} for climate.set_temperature.'),
      description: z.string().describe('Short human-readable summary of the action, to relay to the user, e.g. "Turn off the living room light".'),
    },
  },
  async ({ entity_id, service, data, description }) => {
    const domain = entity_id.split('.')[0];
    const allowed = HA_ALLOWED_SERVICES[domain];
    if (!allowed) {
      return toolResult(`FOXY isn't set up to control "${domain}" devices.`, true);
    }
    if (!allowed.includes(service)) {
      return toolResult(`"${service}" isn't an allowed action for ${domain} devices (allowed: ${allowed.join(', ')}).`, true);
    }
    fs.writeFileSync(PENDING_ACTION_FILE, JSON.stringify({
      entity_id, domain, service, data: data || {}, description, proposedAt: Date.now(),
      turnId: process.env.OQP_PA_TURN_ID || '',
    }));
    return toolResult(`Proposed: ${description}. Waiting for the user to confirm before doing this.`);
  }
);

server.registerTool(
  'confirm_pending_action',
  {
    title: 'Confirm the pending Home Assistant action',
    description: 'Actually performs the action recorded by the most recent propose_ha_action call. ' +
      'Only call this after the user has clearly confirmed (said yes / go ahead / etc.) in their own words.',
  },
  async () => {
    const { pending, expired } = readPendingAction();
    if (expired) {
      clearPendingAction();
      return toolResult('That request has expired — ask again if you still want it done.', true);
    }
    if (!pending) return toolResult('There is nothing pending to confirm.', true);
    // Enforced here, not just requested in the system prompt: paBridge.js gives every
    // separate `claude -p` invocation (one per user utterance) a distinct
    // OQP_PA_TURN_ID. If this confirm call is running in the SAME invocation that
    // proposed the action, the user never actually had a turn to say yes in between —
    // refuse regardless of how confident the model is. See paBridge.js's own comment
    // on turnCounter for the full reasoning.
    if (pending.turnId && pending.turnId === process.env.OQP_PA_TURN_ID) {
      return toolResult('Not yet — wait for the user to actually respond before confirming this.', true);
    }
    const ha = loadHaConfig();
    if (!ha) { clearPendingAction(); return toolResult('Home Assistant is not configured on this panel.', true); }
    try {
      await haRequest(ha, 'POST', `/api/services/${pending.domain}/${pending.service}`,
        { entity_id: pending.entity_id, ...pending.data });
    } catch (e) {
      clearPendingAction();
      return toolResult(`Failed: ${e.message}`, true);
    }
    clearPendingAction();
    return toolResult(`Done: ${pending.description}.`);
  }
);

server.registerTool(
  'cancel_pending_action',
  {
    title: 'Cancel the pending Home Assistant action',
    description: 'Discards the action recorded by propose_ha_action without performing it — use when the user says no/never mind.',
  },
  async () => {
    const { pending } = readPendingAction();
    clearPendingAction();
    return toolResult(pending ? `Cancelled: ${pending.description}.` : 'Nothing was pending.');
  }
);

const transport = new StdioServerTransport();
server.connect(transport).catch(err => {
  process.stderr.write(`paTools/server.js failed to start: ${err && err.message ? err.message : err}\n`);
  process.exit(1);
});
