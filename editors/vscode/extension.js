'use strict';

// Ctrl+Click navigation for .ct files. No third-party dependencies: the index is
// built by scanning workspace *.ct files with the same line-oriented rules the
// compiler documents (top-level constructs start at the beginning of a line).
// The scanner itself lives in ./indexer.js so it can be asserted without the
// editor (test/check-index.js).

const fs = require('fs');
const vscode = require('vscode');
const { parseSource, normalizeCType } = require('./indexer');

const CT_GLOB = '**/*.ct';
const CT_EXCLUDE = '**/{node_modules,.git}/**';
const MAX_FILES = 2000;
const MAX_RESULTS = 50;

let cachedIndex;

async function buildIndex() {
  const defs = [];
  const impls = [];
  const traits = [];
  const typeHosts = [];
  const adoptions = [];
  const seen = new Set();

  const merge = (parsed) => {
    defs.push(...parsed.defs);
    impls.push(...parsed.impls);
    traits.push(...parsed.traits);
    typeHosts.push(...parsed.typeHosts);
    adoptions.push(...parsed.adoptions);
  };

  // Open documents first: this picks up unsaved buffers.
  for (const doc of vscode.workspace.textDocuments) {
    if (doc.languageId !== 'ct') continue;
    const key = doc.uri.toString();
    if (seen.has(key)) continue;
    seen.add(key);
    merge(parseSource(doc.getText(), doc.uri));
  }

  const uris = await vscode.workspace.findFiles(CT_GLOB, CT_EXCLUDE, MAX_FILES);
  for (const uri of uris) {
    if (uri.scheme !== 'file') continue;
    const key = uri.toString();
    if (seen.has(key)) continue;
    seen.add(key);
    let text;
    try {
      text = fs.readFileSync(uri.fsPath, 'utf8');
    } catch (err) {
      continue;
    }
    merge(parseSource(text, uri));
  }

  const types = new Map();
  for (const def of defs) {
    if ((def.kind === 'trait' || def.kind === 'struct') && !types.has(def.name)) {
      types.set(def.name, def.namespace);
    }
  }
  return { defs, impls, traits, typeHosts, adoptions, types };
}

function getIndex() {
  if (!cachedIndex) cachedIndex = buildIndex();
  return cachedIndex;
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Work out the struct behind a receiver so `p.greet()` can be narrowed to
// `impl Greeter for Person`. Falls back to null (all same-name methods) when
// the declaration cannot be found.
function inferReceiverType(document, position, receiver, index) {
  if (receiver === 'self' || receiver === 'this') {
    const key = document.uri.toString();
    const hit = index.impls.find((i) =>
      i.uri.toString() === key && i.startLine <= position.line && position.line <= i.endLine);
    return hit ? hit.struct : null;
  }

  const before = document.getText(new vscode.Range(new vscode.Position(0, 0), position));
  const re = new RegExp(
    '(?:struct\\s+)?\\b([A-Z][A-Za-z0-9_]*)\\s*\\*{0,2}\\s*&?\\s*' +
    escapeRegExp(receiver) + '\\b(?=\\s*[;=,)\\[.])', 'g');
  let found = null;
  let m;
  while ((m = re.exec(before)) !== null) found = m[1];
  return found;
}

function nsMatches(defNs, wanted) {
  if (defNs === wanted) return true;
  return wanted !== '' && defNs.endsWith('::' + wanted);
}

// The declared C type of a receiver, canonicalised. `.m.ct` type hosts bind
// methods to a C type (`map trait CStr for type char *`), so `a.toInt()` with
// `char a[]` needs `char *` after array decay.
function inferDeclaredCType(document, position, receiver) {
  const before = document.getText(new vscode.Range(new vscode.Position(0, 0), position));
  const re = new RegExp(
    '(?:^|[;{}\\n])\\s*' +
    '(?:(?:static|extern|const|volatile|register)\\s+)*' +
    '((?:(?:struct|union|enum)\\s+)?' +
    '(?:(?:unsigned|signed|long|short|const)\\s+)*' +
    '[A-Za-z_][A-Za-z0-9_]*)\\s*' +
    '((?:\\*[ \\t]*)*)' +
    '&?\\s*' + escapeRegExp(receiver) + '\\s*' +
    '((?:\\[[^\\]\\n]*\\])*)\\s*(?=[;=,.)\\[\\n])',
    'g');
  let found = null;
  let m;
  while ((m = re.exec(before)) !== null) found = m;
  if (!found) return null;
  return normalizeCType(found[1] + ' ' + found[2] + (found[3] ? ' * ' : ''));
}

function traitsForCType(type, index) {
  if (!type) return [];
  return index.typeHosts
    .filter((host) => host.type === type)
    .map((host) => host.trait);
}

function dedupe(defs) {
  const seen = new Set();
  const out = [];
  for (const def of defs) {
    const key = `${def.uri.toString()}:${def.line}:${def.character}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(def);
  }
  return out;
}

function rank(def, document) {
  let r = def.uri.toString() === document.uri.toString() ? 0 : 10;
  if (def.kind === 'method') r -= 2;
  if (def.kind === 'function') r -= 1;
  return r;
}

class CtDefinitionProvider {
  async provideDefinition(document, position) {
    const range = document.getWordRangeAtPosition(position, /[A-Za-z_][A-Za-z0-9_]*/);
    if (!range) return undefined;

    const word = document.getText(range);
    const index = await getIndex();
    const prefix = document.getText(
      new vscode.Range(new vscode.Position(range.start.line, 0), range.start)).replace(/\s+$/, '');

    let candidates = [];
    const qualifier = /([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)::$/.exec(prefix);
    const dotted = /([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*(\.|->)$/.exec(prefix);

    if (qualifier) {
      const raw = qualifier[1];
      const ns = index.types.has(raw) ? index.types.get(raw) : raw;
      candidates = index.defs.filter((d) => d.name === word && nsMatches(d.namespace, ns));
    } else if (dotted) {
      const path = dotted[1];
      const segs = path.split('::');
      const receiver = segs[segs.length - 1];

      // `Host::Trait.method(…)`: a zero-cost static-mapping call, no receiver.
      if (dotted[2] === '.' && segs.length > 1 && index.types.has(receiver)) {
        const ns = index.types.get(receiver) || segs.slice(0, -1).join('::');
        candidates = index.defs.filter((d) => d.name === word && d.kind === 'traitMethod' &&
          d.owner === receiver && nsMatches(d.namespace, ns));
        if (!candidates.length) {
          candidates = index.defs.filter((d) =>
            d.name === word && d.kind === 'traitMethod' && d.owner === receiver);
        }
      } else {
        let struct = null;
        let traitScope = null;
        if (receiver === 'self' || receiver === 'this') {
          const key = document.uri.toString();
          const impl = index.impls.find((i) =>
            i.uri.toString() === key && i.startLine <= position.line && position.line <= i.endLine);
          if (impl) {
            struct = impl.struct;
          } else {
            const trait = index.traits.find((t) =>
              t.uri.toString() === key && t.startLine <= position.line && position.line <= t.endLine);
            if (trait) traitScope = trait.name;
          }
        } else {
          struct = inferReceiverType(document, position, receiver, index);
        }

        const methods = index.defs.filter((d) => d.name === word && d.kind === 'method');
        const traitMethods = index.defs.filter((d) => d.name === word && d.kind === 'traitMethod');
        if (struct) {
          // An impl method wins; default bodies and adopted traits follow.
          const traits = new Set();
          for (const impl of index.impls) if (impl.struct === struct) traits.add(impl.trait);
          for (const adoption of index.adoptions) if (adoption.struct === struct) traits.add(adoption.trait);
          candidates = methods.filter((d) => d.owner === struct);
          candidates = candidates.concat(traitMethods.filter((d) => traits.has(d.owner)));
          candidates = candidates.concat(index.defs.filter((d) =>
            d.name === word && d.kind === 'binding' && d.owner === receiver));
        } else if (traitScope) {
          candidates = traitMethods.filter((d) => d.owner === traitScope);
          if (!candidates.length) candidates = methods;
        } else {
          const typeTraits = traitsForCType(inferDeclaredCType(document, position, receiver), index);
          if (typeTraits.length) {
            candidates = traitMethods.filter((d) => typeTraits.indexOf(d.owner) !== -1);
          }
          if (!candidates.length) {
            candidates = index.defs.filter((d) =>
              d.name === word && d.kind === 'binding' && d.owner === receiver);
          }
          if (!candidates.length) candidates = methods;
        }
        if (!candidates.length) candidates = traitMethods;
        if (!candidates.length) candidates = index.defs.filter((d) => d.name === word);
      }
    } else {
      candidates = index.defs.filter((d) => d.name === word);
    }

    candidates = dedupe(candidates)
      .sort((a, b) => rank(a, document) - rank(b, document) || a.line - b.line)
      .slice(0, MAX_RESULTS);

    if (!candidates.length) return undefined;
    return candidates.map((def) => {
      const start = new vscode.Position(def.line, def.character);
      const end = new vscode.Position(def.line, def.character + def.name.length);
      return new vscode.Location(def.uri, new vscode.Range(start, end));
    });
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.languages.registerDefinitionProvider({ language: 'ct' }, new CtDefinitionProvider())
  );

  const reset = () => {
    cachedIndex = undefined;
  };
  const watcher = vscode.workspace.createFileSystemWatcher(CT_GLOB);
  watcher.onDidChange(reset);
  watcher.onDidCreate(reset);
  watcher.onDidDelete(reset);
  context.subscriptions.push(watcher);

  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument((event) => {
    if (event.document.languageId === 'ct') reset();
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
