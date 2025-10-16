// Copyright (c) 2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.
import json
import os
import time

// Convert a document URI to a local filesystem path.
// e.g. file:///home/user/foo.v -> /home/user/foo.v
fn uri_to_path(uri string) string {
	if uri.starts_with('file://') {
		// strip the scheme
		return uri.replace_once('file://', '')
	}
	return uri
}

struct SnapshotCacheEntry {
	text     string
	tmp_path string
	ts       i64
}

// Remove old snapshot files (older than ttl_seconds) and evict entries if cache
// grows beyond max_entries. This keeps the temp dir clean and bounds memory.
fn (mut app App) cleanup_snapshots(ttl_seconds int, max_entries int) {
	now := time.now().unix()
	// remove entries older than TTL
	mut to_remove := []string{}
	for k, e in app.snapshot_cache {
		if now - e.ts > i64(ttl_seconds) {
			to_remove << k
		}
	}
	for key in to_remove {
		entry := app.snapshot_cache[key]
		app.snapshot_cache.delete(key)
		os.rm(entry.tmp_path) or { }
	}

	// Evict oldest entries until under max_entries
	for app.snapshot_cache.len > max_entries {
		mut oldest_key := ''
		mut oldest_ts := i64(1 << 62)
		for k, e in app.snapshot_cache {
			if e.ts < oldest_ts {
				oldest_ts = e.ts
				oldest_key = k
			}
		}
		if oldest_key == '' {
			break
		}
		entry := app.snapshot_cache[oldest_key]
		app.snapshot_cache.delete(oldest_key)
		os.rm(entry.tmp_path) or { }
	}
}

// Ensure we have a filesystem path the compiler can read which matches `text`.
// If the on-disk file at `localpath` already matches `text`, return `localpath` and is_temp=false.
// Otherwise create (or reuse) a temporary copy in the system temp dir and return it with is_temp=true.
fn (mut app App) ensure_snapshot(localpath string, text string) (string, bool) {
	// If the file exists on disk and matches the provided text, prefer it.
	if os.exists(localpath) {
		disk := os.read_file(localpath) or { '' }
		if disk == text {
			return localpath, false
		}
	}
	// Check cache for identical snapshot
	if entry := app.snapshot_cache[localpath] { // read
		if entry.text == text {
			return entry.tmp_path, true
		}
	}
	// create a new unique temp file
	tmpdir := os.temp_dir()
	mut ctr := app.tmp_counter
	ctr++
	app.tmp_counter = ctr
	name := localpath.all_after_last('/')
	tmppath := os.join_path(tmpdir, 'vls_${os.getpid()}_${ctr}_' + name)
	os.write_file(tmppath, text) or { panic(err) }
	ts_now := time.now().unix()
	app.snapshot_cache[localpath] = SnapshotCacheEntry{text: text, tmp_path: tmppath, ts: ts_now}
	// cleanup old snapshots and cap the cache size
	app.cleanup_snapshots(180, 10)
	return tmppath, true
}

fn (mut app App) run_v_check(path string, text string) []JsonError {
	localpath := uri_to_path(path)
	// For diagnostics, always give the compiler the current editor snapshot so
	// diagnostics match what the user sees. Create a snapshot file if needed.
	snapshot_path, _ := app.ensure_snapshot(localpath, text)
	cmd := 'v -w -vls-mode -check -json-errors "${snapshot_path}"'
	x := os.execute(cmd)
	json_errors := json.decode([]JsonError, x.output) or { return [] }
	return json_errors
}

fn (mut app App) run_v_line_info(path string, line_nr int, col int) JsonVarAC {
	localpath := uri_to_path(path)
	// Prefer on-disk file when it matches app.text; otherwise run against a snapshot.
	snapshot_path, is_temp := app.ensure_snapshot(localpath, app.text)
	runpath := if is_temp { snapshot_path } else { localpath }
	cmd := 'v -check -json-errors -nocolor -vls-mode -line-info "${runpath}:${line_nr}:${col}" ${runpath}'
	x := os.execute(cmd)
	json_errors := json.decode(JsonVarAC, x.output) or { return JsonVarAC{} }
	return json_errors
}

// In this mode V returns `/path/to/file.v:line:col`, not json
// So simply return `Location`
fn (mut app App) run_v_go_to_definition(path string, line_nr int, expr string) Location {
	localpath := uri_to_path(path)
	snapshot_path, is_temp := app.ensure_snapshot(localpath, app.text)
	runpath := if is_temp { snapshot_path } else { localpath }
	// This uses the expression instead of line/col
	cmd := 'v -check -json-errors -nocolor -vls-mode -line-info "${runpath}:${line_nr}:gd^${expr}" ${runpath}'
	x := os.execute(cmd)
	vals := x.output.trim_space().split(':')
	if vals.len != 3 {
		return Location{}
	}
	// V prints locations as 1-based lines/cols. Convert to 0-based for LSP.
	line := vals[1].int() - 1
	col := vals[2].int() - 1
	return Location{
		uri: 'file://' + vals[0]
		range: LSPRange{
			start: Position{
				line: line
				char: col
			}
			end: Position{
				line: line
				char: col
			}
		}
	}
}

struct FnSignature {
	name   string
	params []string
}

fn (mut app App) run_v_fn_sig(path string, line_nr int, expr string) FnSignature {
	localpath := uri_to_path(path)
	snapshot_path, is_temp := app.ensure_snapshot(localpath, app.text)
	runpath := if is_temp { snapshot_path } else { localpath }
	cmd := 'v -check -json-errors -nocolor -vls-mode -line-info "${runpath}:${line_nr}:${expr}" ${runpath}'
	x := os.execute(cmd)
	s := x.output.trim_space()
	if s == '' {
		return FnSignature{}
	}
	fn_name := s.before('(')
	params_raw := s.after('(').before(')')
	params := if params_raw == '' { []string{} } else { params_raw.split(',') }
	return FnSignature{
		name:   fn_name
		params: params
	}
}
