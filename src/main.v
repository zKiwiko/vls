// Copyright (c) 2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.
import os
import v.pref
import io

// App represents the context of the server during its lifetime.
pub struct App {
	cur_mod string = 'main'
	exit    bool   = os.args.contains('exit')
mut:
	text string
	snapshot_cache map[string]SnapshotCacheEntry
	tmp_counter    int
}

const v_prefs = pref.Preferences{
	is_vls: true
}

// CLI command handling: define a small Command type and a registry function.
struct Command {
	name string
	desc string
}

fn default_commands() []Command {
	return [
		Command{ name: '-ping', desc: 'liveness check (prints pong)' },
		Command{ name: '-help', desc: 'show this help' },
		Command{ name: '-version', desc: 'print version and exit' },
		Command{ name: '-start', desc: 'start the language server (default)' },
	]
}

fn run_cli_command() bool {
	if os.args.len <= 1 {
		return false
	}
	cmd := os.args[1]
	match cmd {
		'-ping' {
			println('pong')
			return true
		}
		'-help' {
			println('VLS++ commands:')
			for c in default_commands() {
				println('  ${c.name}\t- ${c.desc}')
			}
			return true
		}
		'-version' {
			println('VLS++ Version: 0.1.0')
			return true
		}
		'-start' {
			start()
			return true
		}
		else {
			println('Unknown command: ${cmd}. Use -help to list commands.')
			return true
		}
	}
}

fn start() {
	mut app := &App{
		text: ''
	}
	mut reader := io.new_buffered_reader(reader: os.stdin(), cap: 1)
	app.handle_stdio_requests(mut reader)
}

fn main() {
	// If a CLI command was handled, exit early.
	if run_cli_command() {
		return
	}

	start()
}
