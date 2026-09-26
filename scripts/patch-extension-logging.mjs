#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';

// Safari's extension error summary shows only the first console argument.
// Apply the same formatting to both upstream loggers after every refresh.
const timestamp = '  const getTimestamp = () => `[${new Date().toISOString()}]`;\n';
const formatting = `  const formatLogValue = value => {
    if (value instanceof Error) {
      return value.stack || value.message || String(value);
    }
    if (typeof value === 'string') {
      return value;
    }
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return String(value);
    }
  };
  const formatLogLine = (prefix, args) => [getTimestamp(), prefix, ...args.map(formatLogValue)].join(' ');
`;
for (const file of process.argv.slice(2)) {
  const original = readFileSync(file, 'utf8');
  let source = original;
  const replaceOnce = (before, after) => {
    if (source.split(before).length !== 2) throw new Error(`Unexpected logger shape in ${file}: ${before}`);
    source = source.replace(before, after);
  };
  if (!source.includes(formatting)) replaceOnce(timestamp, timestamp + formatting);
  for (const level of ['debug', 'info', 'error']) {
    const before = `console.${level}(getTimestamp(), this.prefix, ...args);`;
    const after = `console.${level}(formatLogLine(this.prefix, args));`;
    if (!source.includes(after)) replaceOnce(before, after);
  }
  if (source !== original) writeFileSync(file, source);
}
