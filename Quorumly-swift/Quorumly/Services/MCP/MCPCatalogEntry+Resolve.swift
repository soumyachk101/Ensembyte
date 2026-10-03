import Foundation

/// The launchable form, with `{key}` placeholders replaced by the user's values (or the
/// field's default). OAuth servers resolve to their route on the app's proxy.
/// Kept out of Core because it needs the proxy.
extension MCPCatalogEntry {
    func resolve(values: [String: String]) -> MCPResolvedServer {
        func fill(_ text: String) -> String { self.fill(text, values: values) }
        var server = MCPResolvedServer(id: id, name: name)
        switch transport {
        case .stdio(let command, let args):
            server.command = command
            server.args = args.map(fill)
            // An optional field left empty drops its variable rather than passing "".
            server.env = env.mapValues(fill).filter { !$0.value.isEmpty }
        case .http(let url, let headers):
            server.url = fill(url)
            server.headers = headers.compactMapValues { rawHeader in
                for field in fields {
                    let placeholder = "{\(field.key)}"
                    if rawHeader.contains(placeholder) {
                        let val = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let def = field.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let effective = (val?.isEmpty == false) ? val : ((def?.isEmpty == false) ? def : nil)
                        if effective == nil {
                            return nil
                        }
                    }
                }
                let filled = fill(rawHeader).trimmingCharacters(in: .whitespacesAndNewlines)
                if filled.contains("{") && filled.contains("}") {
                    return nil
                }
                let lower = filled.lowercased()
                if lower == "bearer" || lower == "bearer " || filled.isEmpty {
                    return nil
                }
                return filled
            }
        case .oauth(let url):
            server.url = MCPProxy.url(for: id)
            server.oauthUpstream = fill(url)
        }
        return server
    }
}
