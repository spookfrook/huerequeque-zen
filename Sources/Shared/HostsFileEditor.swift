import Foundation

enum HostsFileEditor {
    static let beginMarker = "# BEGIN HUEREQUEQUE-ZEN BLOCK"
    static let endMarker = "# END HUEREQUEQUE-ZEN BLOCK"

    /// Returns updated /etc/hosts content with the Huerequeque Zen managed section replaced or removed.
    /// Preserves all existing lines outside the markers.
    static func apply(domains: [String], to existingContent: String) -> String {
        let stripped = stripManagedBlock(from: existingContent)
        let expanded = DomainNormalizer.expandedHosts(for: domains)
        guard !expanded.isEmpty else {
            return stripped.hasSuffix("\n") || stripped.isEmpty ? stripped : stripped + "\n"
        }

        var sectionLines: [String] = [beginMarker]
        for host in expanded {
            sectionLines.append("0.0.0.0 \(host)")
            sectionLines.append(":: \(host)")
        }
        sectionLines.append(endMarker)
        let section = sectionLines.joined(separator: "\n") + "\n"

        if stripped.isEmpty {
            return section
        }
        let base = stripped.hasSuffix("\n") ? stripped : stripped + "\n"
        return base + "\n" + section
    }

    static func stripManagedBlock(from content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var inside = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == beginMarker {
                inside = true
                continue
            }
            if trimmed == endMarker {
                inside = false
                continue
            }
            if !inside {
                output.append(line)
            }
        }

        // Trim extra trailing blank lines added before our section
        while let last = output.last, last.isEmpty {
            output.removeLast()
        }
        return output.isEmpty ? "" : output.joined(separator: "\n") + "\n"
    }

    static func containsExactBlock(domains: [String], in content: String) -> Bool {
        let expected = apply(domains: domains, to: content)
        return expected == content
    }
}
