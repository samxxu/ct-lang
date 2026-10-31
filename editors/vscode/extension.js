'use strict';

// Ctrl+Click navigation for .ct files. No third-party dependencies: the index is
// built by scanning workspace *.ct files with the same line-oriented rules the
// compiler documents (top-level constructs start at the beginning of a line).

const fs = require('fs');
const vscode = require('vscode');

const CT_GLOB = '**/*.ct';
const CT_EXCLUDE = '**/{node_modules,.git}/**';
const MAX_FILES = 2000;
const MAX_RESULTS = 50;

const NOT_A_NAME = new Set([
  'if', 'for', 'while', 'switch', 'return', 'sizeof', 'do', 'else',
  'case', 'goto', 'typedef', 'struct', 'union', 'enum'
]);

let cachedIndex;

function joinNs(base, name) {
  return base ? `${base}::${name}` : name;
}

function countChar(text, ch) {
  let n = 0;
  for (const c of text) {
    if (c === ch) n += 1;
  }
  return n;
}

// Blank out comments and string/char literals so brace counting is not fooled
// by `printf("{")` or by a `}` inside a comment.
function stripNoise(line, state) {
  let out = '';
  let i = 0;
  while (i < line.length) {
    if (state.inBlock) {
      const end = line.indexOf('*/', i);
      if (end === -1) return out;
      state.inBlock = false;
      i = end + 2;
      continue;
    }
    if (line.startsWith('//', i)) break;
    if (line.startsWith('/*', i)) {
      state.inBlock = true;
      i += 2;
      continue;
    }
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      i += 1;
      while (i < line.length) {
        if (line[i] === '\\') {
          i += 2;
          continue;
        }
        if (line[i] === ch) {
          i += 1;
          break;
        }
        i += 1;
      }
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

function nameOf(match) {
  const name = match[3];
  if (NOT_A_NAME.has(name)) return null;
  return { name, index: match.index + match[0].lastIndexOf(name) };
}

const DEFINITION_RE = /^(\s*(?:(?:pub|static|inline|extern)\s+)*)([A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{/;
const DEFINITION_EOL_RE = /^(\s*(?:(?:pub|static|inline|extern)\s+)*)([A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\([^;{}]*\)\s*$/;
const BARE_DEFINITION_RE = /^(\s*)([A-Za-z_]\w*)\s*\([^;{}]*\)\s*(\{|$)/;
const DECLARATION_RE = /^(\s*(?:(?:pub|static|inline)\s+)*)([A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\([^;{}]*\)\s*;/;

// Function/method definition. The `{` may be on the same line (K&R) or the
// next line (Allman); a prototype ends with `;` and is rejected.
function matchDefinition(line) {
  const braced = DEFINITION_RE.exec(line);
  if (braced) return nameOf(braced);
  const allman = DEFINITION_EOL_RE.exec(line);
  if (allman) return nameOf(allman);
  const bare = BARE_DEFINITION_RE.exec(line);
  if (bare && !NOT_A_NAME.has(bare[2])) {
    return { name: bare[2], index: bare.index + bare[1].length };
  }
  return null;
}

function matchDeclaration(line) {
  const m = DECLARATION_RE.exec(line);
  return m ? nameOf(m, line) : null;
}

// Canonical spelling of a C type so `char *`, `char*` and `char a[]` (array
// decay, per the `.m.ct` type-host rule) compare equal.
function normalizeCType(text) {
  return text
    .replace(/\[[^\]]*\]/g, ' * ')
    .replace(/\b(?:const|volatile|static|extern|register|struct|union|enum)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/[ \t]*\*[ \t]*/g, '*');
}

const MAP_HOST_RE = /^\s*map\s+trait\s+([A-Za-z_]\w*)\s+for\s+(instance|namespace|type)\s+([^;{}]*?)\s*\{/;
const USE_CLAUSE_RE = /^\s*\}\s*use\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*;/;

function parseSource(text, uri) {
  const defs = [];
  const impls = [];
  const traits = [];
  const typeHosts = [];
  const adoptions = [];
  const lines = text.split(/\r?\n/);
  const stack = [];
  const nsStack = [''];
  const state = { inBlock: false };
  let depth = 0;

  const add = (name, kind, lineNo, index, extra) => {
    defs.push(Object.assign({
      name,
      kind,
      uri,
      line: lineNo,
      character: Math.max(index, 0),
      namespace: nsStack[nsStack.length - 1],
      owner: null,
      trait: null
    }, extra || {}));
  };

  for (let lineNo = 0; lineNo < lines.length; lineNo += 1) {
    const line = lines[lineNo];
    const startedInBlock = state.inBlock;
    const clean = stripNoise(line, state);
    const trimmed = line.trim();
    const isComment = startedInBlock || trimmed === '' ||
      trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*');
    const scope = stack[stack.length - 1];

    if (!isComment) {
      let m;
      if (!scope || scope.kind === 'namespace') {
        if ((m = /^\s*namespace\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*([;{])/.exec(line))) {
          if (m[2] === ';') {
            nsStack[nsStack.length - 1] = joinNs(nsStack[nsStack.length - 1], m[1]);
          } else {
            stack.push({ kind: 'namespace', endDepth: depth });
            nsStack.push(joinNs(nsStack[nsStack.length - 1], m[1]));
          }
        } else if ((m = MAP_HOST_RE.exec(line))) {
          stack.push({ kind: 'map', trait: m[1], host: m[2], target: m[3].trim(), endDepth: depth });
          if (m[2] === 'type') {
            typeHosts.push({
              trait: m[1],
              namespace: nsStack[nsStack.length - 1],
              type: normalizeCType(m[3])
            });
          }
        } else if ((m = /^\s*impl\s+([A-Za-z_]\w*)\s+for\s+([A-Za-z_]\w*)[^;{}]*\{/.exec(line))) {
          const impl = {
            uri,
            trait: m[1],
            struct: m[2],
            startLine: lineNo,
            endLine: lines.length - 1
          };
          impls.push(impl);
          stack.push({ kind: 'impl', trait: m[1], struct: m[2], endDepth: depth, impl });
        } else if ((m = /^\s*(?:pub\s+)?trait\s+([A-Za-z_]\w*)[^;{}]*\{/.exec(line))) {
          const trait = {
            uri,
            name: m[1],
            startLine: lineNo,
            endLine: lines.length - 1
          };
          traits.push(trait);
          add(m[1], 'trait', lineNo, line.indexOf(m[1]));
          stack.push({ kind: 'trait', name: m[1], endDepth: depth, trait });
        } else if ((m = /^\s*(?:pub\s+)?struct\s+([A-Za-z_]\w*)[^;{}]*\{/.exec(line))) {
          add(m[1], 'struct', lineNo, line.indexOf(m[1]));
          stack.push({ kind: 'struct', name: m[1], endDepth: depth });
        } else {
          const fn = matchDefinition(line);
          if (fn) add(fn.name, 'function', lineNo, fn.index);
        }
      } else if (scope.kind === 'impl') {
        const fn = matchDefinition(line);
        if (fn) add(fn.name, 'method', lineNo, fn.index, { owner: scope.struct, trait: scope.trait });
      } else if (scope.kind === 'trait') {
        const decl = matchDeclaration(line);
        if (decl) {
          add(decl.name, 'traitMethod', lineNo, decl.index, { owner: scope.name });
        } else {
          const fn = matchDefinition(line);
          if (fn) add(fn.name, 'traitMethod', lineNo, fn.index, { owner: scope.name });
        }
      } else if (scope.kind === 'struct') {
        if ((m = USE_CLAUSE_RE.exec(line))) {
          for (const name of m[1].split(',')) {
            adoptions.push({ uri, struct: scope.name, trait: name.trim() });
          }
        }
      } else if (scope.kind === 'map') {
        if ((m = /^\s*([A-Za-z_]\w*)\s*\([^)]*\)\s*->/.exec(line))) {
          add(m[1], 'binding', lineNo, line.indexOf(m[1]), { owner: scope.target, trait: scope.trait });
        }
      }
    }

    depth += countChar(clean, '{') - countChar(clean, '}');
    while (stack.length && depth <= stack[stack.length - 1].endDepth) {
      const done = stack.pop();
      if (done.kind === 'namespace') nsStack.pop();
      if (done.kind === 'impl') done.impl.endLine = lineNo;
      if (done.kind === 'trait') done.trait.endLine = lineNo;
    }
  }

  return { defs, impls, traits, typeHosts, adoptions };
}

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
