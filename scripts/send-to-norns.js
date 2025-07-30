// send-to-norns.js
const WebSocket = require('ws');

const host = process.env.NORNS_HOST || 'norns.local';
const port = process.env.NORNS_PORT || 5555;
const command = process.argv[2] || 'print("Hello from Makefile!")';

const ws = new WebSocket(`ws://${host}:${port}`, ['bus.sp.nanomsg.org']);

let responseReceived = false;
let outputLines = [];

ws.on('open', () => {
    console.log(`Sending command: ${command}`);
    ws.send(command + '\n');
});

ws.on('message', (data) => {
    const text = data.toString();
    // Capture each line returned by the Norns REPL
    outputLines.push(text.trim());
    console.log('Received:', text);

    // The Norns REPL sends "<ok>" when the command has finished processing
    if (text.includes('<ok>')) {
        responseReceived = true;
        ws.close();
    }
});

ws.on('error', (error) => {
    console.error('WebSocket error:', error.message);
    process.exit(1);
});

ws.on('close', () => {
    if (!responseReceived) {
        console.log('Connection closed without receiving response');
    } else {
        // Print full output without <ok> line
        const filtered = outputLines.filter(l => l && l !== '<ok>');
        if (filtered.length > 1) {
            console.log('\n--- Full Output ---');
            filtered.forEach(line => console.log(line));
            console.log('-------------------');
        }
    }
});

// Timeout after 5 seconds
setTimeout(() => {
    if (!responseReceived) {
        console.log('Timeout: No response received');
        ws.close();
        process.exit(1);
    }
}, 5000);