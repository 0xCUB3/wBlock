#!/usr/bin/env node
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.dirname(__dirname);

const DEFAULT_VERSION = '2.5.1';
const version = process.argv[2] || DEFAULT_VERSION;

const outputDir = path.join(projectRoot, 'wBlock Scripts (iOS)', 'Resources', 'redirects');
const swiftOutputFile = path.join(projectRoot, 'wBlockCoreService', 'RedirectResourceCatalog.swift');

// Content type to file extension mapping
const contentTypeExtensions = {
  'text/plain': '.txt',
  'application/javascript': '.js',
  'application/json': '.json',
  'text/html': '.html',
  'text/css': '.css',
  'text/xml': '.xml',
  'image/gif': '.gif',
  'image/png': '.png',
  'audio/mp3': '.mp3',
  'video/mp4': '.mp4',
};

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
  return response.json();
}

async function fetchText(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to fetch ${url}: ${response.status}`);
  return response.text();
}

async function downloadFile(url, outputPath) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to download ${url}: ${response.status}`);
  const buffer = await response.arrayBuffer();
  fs.writeFileSync(outputPath, Buffer.from(buffer));
}

async function extractTar(tarPath, outputDir) {
  // Use tar command to extract
  execSync(`tar -xzf "${tarPath}" -C "${outputDir}"`, { stdio: 'inherit' });
}

async function main() {
  console.log(`Using @adguard/scriptlets version: ${version}`);

  // Create temp directory
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'adguard-redirects-'));
  console.log(`Temp directory: ${tempDir}`);

  try {
    // Download npm package
    const npmUrl = `https://registry.npmjs.org/@adguard/scriptlets/-/scriptlets-${version}.tgz`;
    const tarPath = path.join(tempDir, 'scriptlets.tgz');
    console.log(`Downloading ${npmUrl}...`);
    await downloadFile(npmUrl, tarPath);

    // Extract tar
    const extractDir = path.join(tempDir, 'extracted');
    fs.mkdirSync(extractDir, { recursive: true });
    console.log(`Extracting tar...`);
    await extractTar(tarPath, extractDir);

    // The tar extracts to a "package" directory
    const packageDir = path.join(extractDir, 'package');
    const redirectFilesDir = path.join(packageDir, 'dist', 'redirect-files');

    if (!fs.existsSync(redirectFilesDir)) {
      throw new Error(`redirect-files directory not found at ${redirectFilesDir}`);
    }

    // Clean output directory
    if (fs.existsSync(outputDir)) {
      execSync(`rm -rf "${outputDir}"`);
    }
    fs.mkdirSync(outputDir, { recursive: true });

    // Download static-redirects.yml from GitHub
    console.log(`Downloading static-redirects.yml from GitHub...`);
    const staticYaml = await fetchText(
      `https://raw.githubusercontent.com/AdguardTeam/Scriptlets/v${version}/src/redirects/static-redirects.yml`
    );

    // Parse YAML manually (simple parsing)
    const staticResources = parseStaticYaml(staticYaml);

    // Get list of JS redirect files from GitHub API
    console.log(`Fetching JS redirect files from GitHub API...`);
    const apiResponse = await fetchJson(
      `https://api.github.com/repos/AdguardTeam/Scriptlets/contents/src/redirects?ref=v${version}`
    );

    const jsFiles = apiResponse
      .filter(item => /\.(js|ts)$/.test(item.name) && item.type === 'file')
      .map(item => item.name);

    console.log(`Found ${jsFiles.length} JS redirect files`);

    // Download JS files and extract names
    const jsRedirectNames = {};
    for (const fileName of jsFiles) {
      const baseFileName = fileName.replace(/\.(js|ts)$/, '');
      const jsUrl = `https://raw.githubusercontent.com/AdguardTeam/Scriptlets/v${version}/src/redirects/${fileName}`;
      const jsContent = await fetchText(jsUrl);
      const names = extractNames(jsContent, baseFileName);
      if (names.length > 0) {
        jsRedirectNames[baseFileName] = names;
      }
    }

    // Copy redirect files and build catalog
    const catalog = {};
    const distFiles = fs.readdirSync(redirectFilesDir);

    // Skip click2load.html
    const filesToCopy = distFiles.filter(f => f !== 'click2load.html');

    for (const fileName of filesToCopy) {
      const sourcePath = path.join(redirectFilesDir, fileName);
      const stat = fs.statSync(sourcePath);

      if (stat.isFile()) {
        // Determine target extension based on content type or use original
        let targetName = fileName;

        // Check if this is a static resource
        const resource = staticResources.find(r => r.file === fileName);
        if (resource) {
          const ext = getExtension(resource.contentType);
          if (ext) {
            const base = fileName.replace(/\.[^.]*$/, '');
            targetName = base + ext;
          }
        } else if (fileName === 'nooptext.js') {
          // Special case: nooptext should be .txt, not .js
          targetName = 'nooptext.txt';
        }

        const targetPath = path.join(outputDir, targetName);
        fs.copyFileSync(sourcePath, targetPath);

        // Add to catalog with the resource title and aliases
        if (resource) {
          const key = resource.title.toLowerCase();
          const relPath = `/redirects/${targetName}`;
          catalog[key] = relPath;

          // Add aliases
          if (resource.aliases && Array.isArray(resource.aliases)) {
            for (const alias of resource.aliases) {
              const aliasKey = alias.toLowerCase();
              if (catalog[aliasKey] && catalog[aliasKey] !== relPath) {
                throw new Error(`Duplicate alias: ${aliasKey} maps to both ${catalog[aliasKey]} and ${relPath}`);
              }
              catalog[aliasKey] = relPath;
            }
          }
        }

        // Add JS redirect names
        const baseName = fileName.replace(/\.[^.]*$/, '');
        if (jsRedirectNames[baseName]) {
          for (const name of jsRedirectNames[baseName]) {
            const nameKey = name.toLowerCase();
            if (catalog[nameKey] && catalog[nameKey] !== catalog[baseName.toLowerCase()]) {
              throw new Error(`Duplicate alias: ${nameKey} maps to both ${catalog[nameKey]} and ${catalog[baseName.toLowerCase()]}`);
            }
            const relPath = `/redirects/${targetName}`;
            catalog[nameKey] = relPath;
          }
        }
      }
    }

    // Handle static resources that have no dist file
    for (const resource of staticResources) {
      if (!filesToCopy.includes(resource.file)) {
        const ext = getExtension(resource.contentType);
        const fileName = resource.file.replace(/\.[^.]*$/, '') + ext;
        const targetPath = path.join(outputDir, fileName);

        // Decode content if base64
        let content = resource.content;
        if (resource.contentType.includes(';base64')) {
          content = Buffer.from(content.replace(/\s/g, ''), 'base64').toString('utf8');
        }

        fs.writeFileSync(targetPath, content);

        // Add to catalog
        const key = resource.title.toLowerCase();
        const relPath = `/redirects/${fileName}`;
        catalog[key] = relPath;

        if (resource.aliases && Array.isArray(resource.aliases)) {
          for (const alias of resource.aliases) {
            const aliasKey = alias.toLowerCase();
            if (catalog[aliasKey] && catalog[aliasKey] !== relPath) {
              throw new Error(`Duplicate alias: ${aliasKey} maps to both ${catalog[aliasKey]} and ${relPath}`);
            }
            catalog[aliasKey] = relPath;
          }
        }
      }
    }

    // Remove 'none' token if it exists
    delete catalog['none'];

    // Remove anything mapping to click2load
    const toDelete = Object.keys(catalog).filter(k => catalog[k].includes('click2load'));
    for (const key of toDelete) {
      delete catalog[key];
    }

    // Verify all catalog values point to existing files
    console.log(`Verifying catalog paths...`);
    for (const [key, relPath] of Object.entries(catalog)) {
      // relPath is like "/redirects/1x1-transparent.gif", extract filename
      const fileName = relPath.split('/').pop();
      const fullPath = path.join(outputDir, fileName);
      if (!fs.existsSync(fullPath)) {
        throw new Error(`Catalog points to non-existent file: ${key} -> ${relPath} (${fullPath})`);
      }
    }

    // Sort catalog keys
    const sortedCatalog = Object.fromEntries(
      Object.entries(catalog).sort(([a], [b]) => a.localeCompare(b))
    );

    // Generate Swift catalog
    generateSwiftCatalog(swiftOutputFile, sortedCatalog, version);

    // Copy LICENSE
    const licensePath = path.join(packageDir, 'LICENSE');
    if (fs.existsSync(licensePath)) {
      fs.copyFileSync(licensePath, path.join(outputDir, 'LICENSE.txt'));
    }

    // Write NOTICE.txt
    const notice = `These files are bundled from @adguard/scriptlets version ${version} (GPL-3.0)
Source: https://github.com/AdguardTeam/Scriptlets/releases/tag/v${version}`;
    fs.writeFileSync(path.join(outputDir, 'NOTICE.txt'), notice);

    console.log(`\nSuccess! Generated:`);
    console.log(`  Resources: ${outputDir}`);
    console.log(`  Catalog: ${swiftOutputFile}`);
    console.log(`  Keys in catalog: ${Object.keys(sortedCatalog).length}`);

  } finally {
    // Clean up temp directory
    execSync(`rm -rf "${tempDir}"`);
  }
}

function getExtension(contentType) {
  if (!contentType) return '';
  const baseType = contentType.split(';')[0];
  return contentTypeExtensions[baseType] || '';
}

function parseStaticYaml(yamlContent) {
  const resources = [];
  const entries = yamlContent.split('\n- title:');
  
  for (const entry of entries) {
    if (!entry.trim()) continue;
    
    const titleMatch = entry.match(/^\s*(.*?)\n/);
    const aliasesMatch = entry.match(/aliases:\s*\n(([\s\S]*?)(?=\n  \w+:|\n- |\Z))/);
    const fileMatch = entry.match(/file:\s*(.*?)\n/);
    const contentTypeMatch = entry.match(/contentType:\s*(.*?)\n/);
    const contentMatch = entry.match(/content:\s*([\s\S]*?)(?=\n  \w+:|\n- |\Z)/);

    const title = titleMatch ? titleMatch[1].trim() : '';
    const file = fileMatch ? fileMatch[1].trim() : '';
    const contentType = contentTypeMatch ? contentTypeMatch[1].trim() : '';
    
    let content = '';
    if (contentMatch) {
      content = contentMatch[1]
        .split('\n')
        .map(line => line.replace(/^\s*- |^\s*\|\s*|^\s*>\s*/, '').trim())
        .filter(line => line && !line.startsWith('#'))
        .join('\n')
        .trim();
    }

    const aliases = [];
    if (aliasesMatch) {
      const aliasText = aliasesMatch[1];
      const aliasLines = aliasText.split('\n');
      for (const line of aliasLines) {
        const match = line.match(/^\s*- (.*)/);
        if (match) {
          aliases.push(match[1].trim());
        }
      }
    }

    if (title && file) {
      resources.push({ title, file, contentType, content, aliases });
    }
  }

  return resources;
}

function extractNames(jsContent, baseName) {
  const names = [baseName]; // Always include the base name
  
  // Look for .names = [...]
  // Upstream declares `export const FooNames = ['primary', ...];`.
  const match = jsContent.match(/Names\s*=\s*\[(.*?)\]/s);
  if (match) {
    const namesStr = match[1];
    const nameMatches = namesStr.match(/'([^']*)'/g);
    if (nameMatches) {
      for (const nm of nameMatches) {
        const name = nm.replace(/['"]/g, '');
        if (name && !names.includes(name)) {
          names.push(name);
        }
      }
    }
  }

  // Verify first name matches base name if there are multiple names
  if (names.length > 1 && names[0] !== baseName) {
    // Try to find the base name in the list and put it first
    const idx = names.indexOf(baseName);
    if (idx > 0) {
      [names[0], names[idx]] = [names[idx], names[0]];
    }
  }

  return names;
}

function generateSwiftCatalog(filePath, catalog, version) {
  const lines = [
    '// Generated by scripts/update-redirect-resources.mjs from @adguard/scriptlets ' + version + '. Do not edit.',
    'public enum RedirectResourceCatalog {',
    '    public static let version = "' + version + '"',
    '    /// Filter-list redirect token or alias -> bundled extension path.',
    '    public static let paths: [String: String] = [',
  ];

  for (const [key, value] of Object.entries(catalog)) {
    lines.push(`        "${key}": "${value}",`);
  }

  lines.push('    ]');
  lines.push('}');

  fs.writeFileSync(filePath, lines.join('\n') + '\n');
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
