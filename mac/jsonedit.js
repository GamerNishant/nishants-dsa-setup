// JSON helper for Nishant's DSA Setup on macOS. Runs with the built-in
// JavaScript for Automation engine:  osascript -l JavaScript jsonedit.js <command> ...
//
//   vscode   <settings.json> <shared-settings.json> <g++ path> <gcc path> <manifest.json>
//   restore  <manifest.json>
//   addblock <file> <block-file> <manifest.json>
//   rmblocks <manifest.json>
//
// Every value written is recorded in the manifest with what was there before,
// so restore can put back the student's own value. Values the student changed
// after setup are left alone.

ObjC.import('Foundation');

const BLOCK_START = "# >>> Nishant's DSA Setup >>>";
const BLOCK_END = "# <<< Nishant's DSA Setup <<<";
const fm = $.NSFileManager.defaultManager;

function exists(p) { return fm.fileExistsAtPath(p); }

function readText(p) {
    if (!exists(p)) return null;
    const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
    return s.isNil() ? null : ObjC.unwrap(s);
}

function writeText(p, text) {
    const dir = ObjC.unwrap($(p).stringByDeletingLastPathComponent);
    fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
    const ok = $(text).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null);
    if (!ok) throw new Error('could not write ' + p);
}

function removeFile(p) { fm.removeItemAtPathError(p, null); }

// ------------------------------------------------------------- JSONC

function stripComments(text) {
    let out = '', inStr = false, esc = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (inStr) {
            out += c;
            if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false;
            continue;
        }
        if (c === '"') { inStr = true; out += c; continue; }
        if (c === '/' && text[i + 1] === '/') { while (i < text.length && text[i] !== '\n') i++; out += '\n'; continue; }
        if (c === '/' && text[i + 1] === '*') { i += 2; while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++; i++; continue; }
        out += c;
    }
    return out;
}

function stripTrailingCommas(text) {
    let out = '', inStr = false, esc = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (inStr) {
            if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false;
        } else if (c === '"') {
            inStr = true;
        } else if (c === ',') {
            let j = i + 1;
            while (j < text.length && /\s/.test(text[j])) j++;
            if (text[j] === '}' || text[j] === ']') continue;
        }
        out += c;
    }
    return out;
}

// Returns { ok, exists, obj }. ok=false: the file exists but is not valid JSONC.
function readJsonc(p) {
    const text = readText(p);
    if (text === null) return { ok: true, exists: false, obj: {} };
    const clean = stripTrailingCommas(stripComments((text.charCodeAt(0) === 0xfeff ? text.slice(1) : text))).trim();
    if (clean === '') return { ok: true, exists: true, obj: {} };
    try {
        const obj = JSON.parse(clean);
        if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) return { ok: false, exists: true };
        return { ok: true, exists: true, obj };
    } catch (e) {
        return { ok: false, exists: true };
    }
}

function writeJson(p, obj) { writeText(p, JSON.stringify(obj, null, 4) + '\n'); }

function canonical(v) {
    if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
    if (v && typeof v === 'object') return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
    return JSON.stringify(v === undefined ? null : v);
}
const same = (a, b) => canonical(a) === canonical(b);
const clone = (v) => JSON.parse(JSON.stringify(v));

// ------------------------------------------------------------- manifest

function loadManifest(p) {
    const m = readJsonc(p);
    const base = { version: 1, jsonEdits: [], blocks: [] };
    if (!m.ok || !m.exists) return base;
    return Object.assign(base, m.obj);
}

function saveManifest(p, m) { writeJson(p, m); }

function setTracked(manifest, file, changes) {
    const read = readJsonc(file);
    if (!read.ok) return 'unreadable';
    const obj = read.obj;
    let changed = 0;
    for (const { key, value } of changes) {
        const rec = manifest.jsonEdits.find((e) => e.file === file && e.key === key);
        const has = Object.prototype.hasOwnProperty.call(obj, key);
        if (has && same(obj[key], value) && !rec) continue; // student already had it
        if (rec) {
            rec.applied = value;
        } else {
            manifest.jsonEdits.push({ file, key, createdFile: !read.exists, hadValue: has, previous: has ? obj[key] : null, applied: value });
        }
        obj[key] = value;
        changed++;
    }
    if (changed > 0) writeJson(file, obj);
    return 'ok';
}

// ------------------------------------------------------------- commands

function cmdVscode(settingsFile, sharedFile, gpp, gcc, manifestFile) {
    const manifest = loadManifest(manifestFile);
    const shared = readJsonc(sharedFile).obj;
    const current = readJsonc(settingsFile);
    if (!current.ok) return 'unreadable';
    const changes = Object.keys(shared).map((key) => ({ key, value: shared[key] }));
    if (gpp) {
        changes.push({ key: 'C_Cpp.default.compilerPath', value: gpp });
        changes.push({ key: 'cph.language.cpp.Command', value: gpp });
        if (gcc) changes.push({ key: 'cph.language.c.Command', value: gcc });
        const q = (s) => "'" + s.replace(/'/g, "'\\''") + "'";
        const map = current.obj['code-runner.executorMap'];
        const executorMap = map && typeof map === 'object' && !Array.isArray(map) ? clone(map) : {};
        executorMap.cpp = 'cd $dir && ' + q(gpp) + ' $fileName -o $fileNameWithoutExt && $dir$fileNameWithoutExt';
        if (gcc) executorMap.c = 'cd $dir && ' + q(gcc) + ' $fileName -o $fileNameWithoutExt && $dir$fileNameWithoutExt';
        changes.push({ key: 'code-runner.executorMap', value: executorMap });
    }
    const result = setTracked(manifest, settingsFile, changes);
    saveManifest(manifestFile, manifest);
    return result;
}

function cmdRestore(manifestFile) {
    const manifest = loadManifest(manifestFile);
    const files = [...new Set(manifest.jsonEdits.map((e) => e.file))];
    const lines = [];
    for (const file of files) {
        const edits = manifest.jsonEdits.filter((e) => e.file === file);
        const read = readJsonc(file);
        if (!read.exists) { lines.push('skip ' + file + ' no longer exists'); continue; }
        if (!read.ok) { lines.push('warn ' + file + ' could not be read; restore it from the backup folder'); continue; }
        const obj = read.obj;
        for (const e of edits) {
            const has = Object.prototype.hasOwnProperty.call(obj, e.key);
            if (has && !same(obj[e.key], e.applied)) { lines.push('kept your newer value for ' + e.key); continue; }
            if (e.hadValue) obj[e.key] = e.previous; else delete obj[e.key];
        }
        if (edits.some((e) => e.createdFile) && Object.keys(obj).length === 0) removeFile(file);
        else writeJson(file, obj);
        lines.push('ok ' + file + ' restored');
    }
    manifest.jsonEdits = [];
    saveManifest(manifestFile, manifest);
    return lines.join('\n');
}

function cmdAddBlock(file, blockFile, manifestFile) {
    const manifest = loadManifest(manifestFile);
    const existed = exists(file);
    const text = existed ? readText(file) || '' : '';
    if (text.indexOf(BLOCK_START) !== -1) return 'present';
    const block = readText(blockFile).trim();
    const prefix = text.length > 0 && !text.endsWith('\n') ? '\n' : '';
    writeText(file, text + prefix + '\n' + block + '\n');
    if (!manifest.blocks.some((b) => b.file === file)) manifest.blocks.push({ file, createdFile: !existed });
    saveManifest(manifestFile, manifest);
    return 'added';
}

function cmdRemoveBlocks(manifestFile) {
    const manifest = loadManifest(manifestFile);
    const lines = [];
    const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp('\\n?' + esc(BLOCK_START) + '[\\s\\S]*?' + esc(BLOCK_END) + '\\n?', 'g');
    for (const b of manifest.blocks) {
        const text = readText(b.file);
        if (text === null) continue;
        const next = text.replace(re, '');
        if (next === text) continue;
        if (b.createdFile && next.trim() === '') { removeFile(b.file); lines.push('ok removed ' + b.file + ' (created by the setup)'); }
        else { writeText(b.file, next); lines.push('ok prompt removed from ' + b.file); }
    }
    manifest.blocks = [];
    saveManifest(manifestFile, manifest);
    return lines.join('\n');
}

function run(argv) {
    const [cmd, ...a] = argv;
    switch (cmd) {
        case 'vscode': return cmdVscode(a[0], a[1], a[2], a[3], a[4]);
        case 'restore': return cmdRestore(a[0]);
        case 'addblock': return cmdAddBlock(a[0], a[1], a[2]);
        case 'rmblocks': return cmdRemoveBlocks(a[0]);
        default: throw new Error('unknown command ' + cmd);
    }
}
