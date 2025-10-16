import json

// Logging removed: avoid IO overhead in normal operation.

struct JsonError {
    path    string
    message string
    line_nr int
    col     int
    len     int
}

struct JsonVarAC {
    name       string
    type       string
    methods    []string // "name:type" strings
    functions  []string // "name:type" strings
    fields     []string // "name:type" strings
    type_alias []string // "name" strings
    interfaces []string // "name" strings
    enums      []string // "name" strings
    constants  []string // "name:type" strings
    structs    []string // "name" strings
}

fn strip_type_tags(content string) string {
    // Remove a few common union `_type` encodings the V json encoder inserts.
    // Keep this list small and explicit to avoid accidental removals.
    mut out := content
    out = out.replace(',"_type":"Detail"', '')
    out = out.replace('"_type":"Detail",', '')
    out = out.replace(',"_type":"LSPDiagnostic"', '')
    out = out.replace('"_type":"LSPDiagnostic",', '')
    out = out.replace(',"_type":"SignatureInformation"', '')
    out = out.replace('"_type":"SignatureInformation",', '')
    out = out.replace(',"_type":"ParameterInformation"', '')
    out = out.replace('"_type":"ParameterInformation",', '')
    out = out.replace(',"_type":"Location"', '')
    out = out.replace('"_type":"Location",', '')
    return out
}

fn write_response(response Response) {
    mut content := json.encode(response)
    content = strip_type_tags(content)
    headers := 'Content-Length: ${content.len}\r\n\r\n'
    full_message := '${headers}${content}'
    print(full_message)
    // flush_stdout() is available in V to ensure stdio delivery
    flush_stdout()
}

fn write_notification(notification Notification) {
    mut content := json.encode(notification)
    content = strip_type_tags(content)
    headers := 'Content-Length: ${content.len}\r\n\r\n'
    full_message := '${headers}${content}'
    print(full_message)
    flush_stdout()
}

fn v_error_to_lsp_diagnostic(e JsonError) LSPDiagnostic {
    // Convert 1-based parser positions to 0-based LSP positions
    start_line := e.line_nr - 1
    start_char := e.col - 1
    end_char := start_char + e.len
    return LSPDiagnostic{
        message: e.message
        severity: 1
        range: LSPRange{
            start: Position{
                line: start_line
                char: start_char
            }
            end: Position{
                line: start_line
                char: end_char
            }
        }
    }
}
