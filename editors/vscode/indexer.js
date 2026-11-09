'use strict';

// The pure half of the go-to-definition indexer: a line-oriented scanner for
// `.ct` sources. It has no `vscode` dependency on purpose, so the rules can be
// asserted by a plain Node script (editors/vscode/test/check-index.js) as well
// as used by the extension (editors/vscode/extension.js).

const NOT_A_NAME = new Set([
  'if', 'for', 'while', 'switch', 'return', 'sizeof', 'do', 'else',
  'case', 'goto', 'typedef', 'struct', 'union', 'enum'
]);

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

// v0.26.4 / DOC-68: a type parameter list may sit between the name and `(`.
// The angle-bracket body is restricted to identifiers, `,`, whitespace and `*`
// so a comparison (`a < b > c`) cannot be mistaken for a generic declarator.
const TPARAMS = '(?:\\s*<[A-Za-z_][\\w\\s,*]*>)?';
const DEFINITION_RE = new RegExp(
  '^(\\s*(?:(?:pub|static|inline|extern)\\s+)*)([A-Za-z_][\\w\\s\\*]*?)\\b([A-Za-z_]\\w*)' +
  TPARAMS + '\\s*\\([^;{}]*\\)\\s*\\{');
const DEFINITION_EOL_RE = new RegExp(
  '^(\\s*(?:(?:pub|static|inline|extern)\\s+)*)([A-Za-z_][\\w\\s\\*]*?)\\b([A-Za-z_]\\w*)' +
  TPARAMS + '\\s*\\([^;{}]*\\)\\s*$');
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
  return m ? nameOf(m) : null;
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

module.exports = {
  NOT_A_NAME,
  normalizeCType,
  matchDefinition,
  matchDeclaration,
  parseSource
};
