import SwiftUI
import CodeEditorView
import LanguageSupport

struct MultilineCodeEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var text: String
    private let language: LanguageConfiguration
    private let minHeight: CGFloat
    private let releasesResourcesOnDisappear: Bool
    @State private var position = CodeEditor.Position()
    @State private var messages = Set<TextLocated<Message>>()
    @State private var isEditorActive = true
    @State private var editorID = UUID()

    init(
        text: Binding<String>,
        language: LanguageConfiguration = .none,
        minHeight: CGFloat,
        releasesResourcesOnDisappear: Bool = false
    ) {
        _text = text
        self.language = language
        self.minHeight = minHeight
        self.releasesResourcesOnDisappear = releasesResourcesOnDisappear
    }

    var body: some View {
        Group {
            if isEditorActive {
                CodeEditor(
                    text: $text,
                    position: $position,
                    messages: $messages,
                    language: language
                )
                .id(editorID)
                .environment(
                    \.codeEditorTheme,
                    colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
                )
                .environment(
                    \.codeEditorLayoutConfiguration,
                    CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)
                )
            }
        }
        .frame(minHeight: minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .onAppear {
            isEditorActive = true
        }
        .onDisappear {
            guard releasesResourcesOnDisappear else { return }
            isEditorActive = false
            editorID = UUID()
            position = CodeEditor.Position()
            messages.removeAll(keepingCapacity: false)
        }
    }
}

extension LanguageConfiguration {
    static let yaml = LanguageConfiguration(
        name: "YAML",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: true,
        indentationSensitiveScoping: true,
        stringRegex: /"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'/,
        characterRegex: nil,
        numberRegex: /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/,
        singleLineComment: "#",
        nestedComment: nil,
        identifierRegex: /[A-Za-z_][A-Za-z0-9_-]*/,
        operatorRegex: nil,
        reservedIdentifiers: ["true", "false", "null", "yes", "no", "on", "off"],
        reservedOperators: []
    )
}
