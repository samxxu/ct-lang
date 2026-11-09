#!/usr/bin/env node
'use strict';

// v0.26.4 / DOC-68: executable assertions for the go-to-definition indexer.
// The scanner must see `T name<T>(...)` declarations (K&R and Allman, free
// functions, `impl` methods and trait default bodies) while leaving comparison
// expressions alone. Calls are resolved by name only: `id<int>(…)` jumps to the
// declaration of `id`, never to an instantiation.

const { parseSource, matchDefinition, normalizeCType } = require('../indexer.js');

let checks = 0;
const failures = [];

function check(label, ok, detail) {
  checks += 1;
  if (!ok) failures.push(`${label}${detail ? ': ' + detail : ''}`);
}

function defs(text) {
  return parseSource(text, 'file:///test.ct').defs;
}

function named(text, name, kind) {
  return defs(text).filter((d) => d.name === name && (!kind || d.kind === kind));
}

// 1-2: a generic free function is indexed in both brace styles.
const knr = 'T id<T>(T x) {\n    return x;\n}\n';
const allman = 'T id<T>(T x)\n{\n    return x;\n}\n';
for (const [label, text] of [['K&R', knr], ['Allman', allman]]) {
  const hits = named(text, 'id', 'function');
  check(`${label} generic declaration is indexed`, hits.length === 1, `${hits.length} hits`);
  check(`${label} declaration points at its line`, hits.length === 1 && hits[0].line === 0,
    hits.length ? `line ${hits[0].line}` : 'no hit');
  check(`${label} declaration points at the name`, hits.length === 1 && hits[0].character === 2,
    hits.length ? `character ${hits[0].character}` : 'no hit');
}

// 3: an `impl` method may be generic too.
const implText = 'impl Wrapper for Holder {\n    T wrap<T>(T x) {\n        return x;\n    }\n}\n';
const methods = named(implText, 'wrap', 'method');
check('generic impl method is indexed', methods.length === 1, `${methods.length} hits`);
check('generic impl method keeps its owner', methods.length === 1 && methods[0].owner === 'Holder',
  methods.length ? String(methods[0].owner) : 'no hit');

// 4: a trait default body may be generic too.
const traitText = 'trait Twice {\n    T twice<T>(T x) {\n        return x + x;\n    }\n}\n';
const traitMethods = named(traitText, 'twice', 'traitMethod');
check('generic trait default method is indexed', traitMethods.length === 1, `${traitMethods.length} hits`);
check('generic trait default method keeps its owner', traitMethods.length === 1 && traitMethods[0].owner === 'Twice',
  traitMethods.length ? String(traitMethods[0].owner) : 'no hit');

// 5-6: calls resolve to the declaration by name, whatever the type argument is.
for (const [label, call] of [['int', 'id<int>(42);'], ['pointer', 'id<char *>(p);']]) {
  const text = 'T id<T>(T x)\n{\n    return x;\n}\n\nint main(void)\n{\n    ' + call + '\n    return 0;\n}\n';
  const hits = named(text, 'id', 'function');
  check(`${label} instantiation does not shadow the declaration`, hits.length === 1, `${hits.length} hits`);
  check(`${label} instantiation is not indexed as a definition`,
    defs(text).filter((d) => d.line === 7).length === 0,
    String(defs(text).filter((d) => d.line === 7).map((d) => d.name)));
}

// 7-9: comparisons must not be mistaken for generic declarators.
const negatives = [
  ['comparison call', 'int main(void)\n{\n    if (a < b) f();\n    return 0;\n}\n'],
  ['chained comparison assignment', 'int main(void)\n{\n    int m = a < b > c;\n    return 0;\n}\n'],
  ['arrow comparison', 'int main(void)\n{\n    while (p->x < q) x += 1;\n    return 0;\n}\n']
];
for (const [label, text] of negatives) {
  const line2 = defs(text).filter((d) => d.line === 2);
  check(`${label} adds no definition`, line2.length === 0,
    line2.map((d) => `${d.name}@${d.line}`).join(','));
  check(`${label} keeps the surrounding function`, named(text, 'main', 'function').length === 1,
    `${named(text, 'main', 'function').length} main hits`);
}

// 10: a prototype is not a definition.
check('prototype is not a definition',
  matchDefinition('int add(int a, int b);') === null,
  JSON.stringify(matchDefinition('int add(int a, int b);')));

// 11-13: the non-generic forms keep working.
const plain = 'int add(int a, int b) {\n    return a + b;\n}\n';
check('plain function keeps working', named(plain, 'add', 'function').length === 1,
  `${named(plain, 'add', 'function').length} hits`);
const inNs = 'namespace math;\n\nint add(int a, int b) {\n    return a + b;\n}\n';
const nsHits = named(inNs, 'add', 'function');
check('namespace-qualified function keeps its namespace', nsHits.length === 1 && nsHits[0].namespace === 'math',
  nsHits.length ? String(nsHits[0].namespace) : 'no hit');
check('struct declaration is indexed',
  named('struct Point {\n    int x;\n};\n', 'Point', 'struct').length === 1, 'no hit');

// 14: array decay keeps `.m.ct` type-host matching intact.
check('array decay canonicalises to a pointer', normalizeCType('char []') === 'char*',
  normalizeCType('char []'));
check('const is dropped from a canonical type', normalizeCType('const char *') === 'char*',
  normalizeCType('const char *'));

console.log(`check-index: ${checks} assertions, ${failures.length} failed`);
for (const failure of failures) console.log(`  FAIL ${failure}`);
process.exit(failures.length ? 1 : 0);
