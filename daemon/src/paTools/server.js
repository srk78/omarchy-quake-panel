#!/usr/bin/env node
'use strict';
/*
 * server.js — the MCP server the PA's `claude -p` calls get via --mcp-config (see
 * ../paBridge.js and mcp-config.json). Gives the agent real tools instead of us parsing
 * its text for "intent" — it decides when to call these, we just execute them.
 *
 * Every tool here reaches the running panel through the SAME `omarchy-shell quake-panel
 * <method>` IPC surface ops/bin/omarchy-quake-panel-toggle already uses — no separate
 * code path invented just for the agent. This process is spawned fresh per `claude -p`
 * call (stdio transport, whatever process the CLI wants), so it holds no state of its
 * own between turns; all real state lives on the panel side (PersonalCareState.qml etc).
 *
 * MIT-licensed: pure process orchestration, no device protocol.
 */
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { execFile } = require('child_process');

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

const transport = new StdioServerTransport();
server.connect(transport).catch(err => {
  process.stderr.write(`paTools/server.js failed to start: ${err && err.message ? err.message : err}\n`);
  process.exit(1);
});
