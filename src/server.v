import json
import io

// Read a single LSP Content-Length framed request from the buffered reader.
fn read_request(mut reader io.BufferedReader) !string {
    mut len := 0
    for {
        line := reader.read_line() or {
            if err is io.Eof {
                return err
            }
            return err
        }
        trimmed_line := line.trim_space()
        if trimmed_line == '' {
            break
        }
        
        if trimmed_line.starts_with('Content-Length: ') {
            len_str := trimmed_line.after(':').trim_space()
            len = len_str.int()
        }
    }
    if len == 0 {
        return ''
    }
    mut buf := []u8{len: len}
    mut total_bytes_read := 0
    for total_bytes_read < len {
        bytes_read_now := reader.read(mut buf[total_bytes_read..]) or { return err }
        if bytes_read_now == 0 && total_bytes_read < len {
            return io.Eof{}
        }
        total_bytes_read += bytes_read_now
    }
    return buf.bytestr()
}

// Main request handler loop — kept as a method on `App` but implemented here to keep `main.v` small.
fn (mut app App) handle_stdio_requests(mut reader io.BufferedReader) {
    for {
        content := read_request(mut reader) or {
            if err is io.Eof {
            }
            break
        }
        if content.len == 0 {
            continue
        }
        request := json.decode(Request, content) or { continue }
        method := Method.from_string(request.method)
        match method {
            .completion {
                
                resp := app.completion(request)
                write_response(resp)
            }
            .signature_help {
                
                resp := app.signature_help(request)
                write_response(resp)
            }
            .definition {
                
                resp := app.go_to_definition(request)
                write_response(resp)
            }
            .did_change {
                
                notification := app.on_did_change(request) or { continue }
                write_notification(notification)
            }
            .initialize {
                response := Response{
                    id:     request.id
                    result: Capabilities{
                        capabilities: Capability{
                            text_document_sync:      TextDocumentSyncOptions{
                                open_close: true
                                change:     1 // 1 = Full sync
                            }
                            completion_provider:     CompletionProvider{
                                trigger_characters: ['.']
                                completion_item:    CompletionItemCapability{
                                    snippet_support: true
                                }
                            }
                            signature_help_provider: SignatureHelpOptions{
                                trigger_characters: ['(', ',']
                            }
                            definition_provider:     true
                        }
                    }
                }
                write_response(response)
            }
            .initialized, .did_open, .set_trace, .cancel_request {
                
            }
            .shutdown {
                
                shutdown_resp := Response{
                    id:     request.id
                    result: 'null'
                }
                write_response(shutdown_resp)
            }
            .exit {
                
                break
            }
            else {
                
            }
        }
    }
}
