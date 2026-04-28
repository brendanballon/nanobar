import AppKit
import SwiftUI
import Monitors
import NanoBarPluginAPI

// MARK: - ColorPanelTracker

/// Singleton that owns the NSColorPanel connection.
///
/// SwiftUI's ColorPicker wraps NSColorWell, which has two problems:
/// (1) requires two clicks — first to focus/activate, second to open the panel;
/// (2) stops propagating changes when the well loses activation (user clicks elsewhere).
///
/// ColorPanelTracker bypasses both: a plain Button opens the panel directly,
/// and NSColorPanel.colorDidChangeNotification drives updates regardless of focus.
/// Only the last-opened swatch receives updates — clicking a new swatch replaces
/// the callback, matching the expected "edit one color at a time" UX.
@MainActor
final class ColorPanelTracker: NSObject {
    static let shared = ColorPanelTracker()
    private var onChange: ((NSColor) -> Void)?
    private var token: Any?

    private override init() {}

    func open(color: NSColor, showsAlpha: Bool, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.color = color.usingColorSpace(.sRGB) ?? color
        panel.showsAlpha = showsAlpha
        panel.isContinuous = true
        panel.orderFront(nil)
        // Replace previous observer — only this swatch gets updates now.
        token.map { NotificationCenter.default.removeObserver($0) }
        token = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            self?.onChange?(NSColorPanel.shared.color)
        }
    }
}

// MARK: - ColorSwatch

/// Colored swatch button that opens NSColorPanel on the first click
/// and keeps tracking changes while the panel is open — even when the
/// settings window loses focus or another control is clicked.
struct ColorSwatch: View {
    @Binding var color: Color
    var supportsOpacity: Bool = true

    var body: some View {
        Button(action: open) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 28, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func open() {
        let binding = $color
        ColorPanelTracker.shared.open(
            color: NSColor(color),
            showsAlpha: supportsOpacity,
            onChange: { binding.wrappedValue = Color($0) }
        )
    }
}

// MARK: - ValueField

/// A labeled numeric field combining a fixed-width TextField with a Stepper.
/// Changes commit on focus-loss (TextField) or stepper tap.
struct ValueField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var textInput: String = ""

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", text: $textInput)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitText() }
                    .onChange(of: value) { _, newVal in
                        textInput = formatValue(newVal)
                    }
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
        .onAppear {
            textInput = formatValue(value)
        }
    }

    private func commitText() {
        guard let parsed = Double(textInput) else {
            textInput = formatValue(value)
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        textInput = formatValue(clamped)
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}

// MARK: - SideInsetsEditor

/// Edits a `SideInsets` value with an "Equal on all sides" toggle.
/// When equal: single ValueField; when not equal: four ValueFields (top/right/bottom/left).
///
/// Pass `defaultInsets` to enable write-skip-default: if the written value equals the default
/// the key is removed from config rather than written.
struct SideInsetsEditor: View {
    let label: String
    let section: String
    let key: String
    let current: SideInsets
    var defaultInsets: SideInsets? = nil

    @State private var allEqual: Bool = true
    @State private var top:    Double = 0
    @State private var right:  Double = 0
    @State private var bottom: Double = 0
    @State private var left:   Double = 0

    var body: some View {
        Section(label) {
            Toggle("Equal on all sides", isOn: $allEqual)
                .onChange(of: allEqual) { _, equal in
                    if equal {
                        // Normalize to top value
                        top = top; right = top; bottom = top; left = top
                        writeScalar(top)
                    } else {
                        writeTable(top: top, right: right, bottom: bottom, left: left)
                    }
                }

            if allEqual {
                ValueField(label: "All sides", value: $top, range: 0...60, step: 1)
                    .onChange(of: top) { _, v in writeScalar(v) }
            } else {
                ValueField(label: "Top",    value: $top,    range: 0...60, step: 1)
                    .onChange(of: top)    { _, _ in writeTableCurrent() }
                ValueField(label: "Right",  value: $right,  range: 0...60, step: 1)
                    .onChange(of: right)  { _, _ in writeTableCurrent() }
                ValueField(label: "Bottom", value: $bottom, range: 0...60, step: 1)
                    .onChange(of: bottom) { _, _ in writeTableCurrent() }
                ValueField(label: "Left",   value: $left,   range: 0...60, step: 1)
                    .onChange(of: left)   { _, _ in writeTableCurrent() }
            }
        }
        .onAppear { syncFromCurrent() }
        .onChange(of: current) { _, c in syncFromCurrent(c) }
    }

    private func syncFromCurrent(_ c: SideInsets? = nil) {
        let s = c ?? current
        top    = s.top;  right  = s.right
        bottom = s.bottom;  left = s.left
        allEqual = (top == right && right == bottom && bottom == left)
    }

    private func writeScalar(_ v: Double) {
        if let def = defaultInsets, SideInsets(all: v) == def {
            ConfigLoader.shared.removeKey(section: section, key: key)
        } else {
            ConfigLoader.shared.write(section: section, key: key, value: .integer(Int(v)))
        }
    }

    private func writeTableCurrent() {
        writeTable(top: top, right: right, bottom: bottom, left: left)
    }

    private func writeTable(top: Double, right: Double, bottom: Double, left: Double) {
        if let def = defaultInsets,
           top == def.top && right == def.right && bottom == def.bottom && left == def.left {
            ConfigLoader.shared.removeKey(section: section, key: key)
            return
        }
        let t = Int(top), r = Int(right), b = Int(bottom), l = Int(left)
        let raw = "{ top = \(t), right = \(r), bottom = \(b), left = \(l) }"
        ConfigLoader.shared.write(section: section, key: key, value: .rawLiteral(raw))
    }
}

// MARK: - BorderEditor

/// Edits a `BorderConfig` with enable toggle, adaptive toggle, width ValueField, and ColorPicker.
///
/// Pass `defaultBorder` to enable write-skip-default: if the written value equals the default
/// the key is removed from config rather than written.
struct BorderEditor: View {
    let section: String
    let key: String
    let current: BorderConfig
    var defaultBorder: BorderConfig? = nil

    @State private var enabled:  Bool   = false
    @State private var adaptive: Bool   = true
    @State private var width:    Double = 0.75
    @State private var colorHex: String = BorderConfig.defaultColor

    var body: some View {
        Section("Border") {
            Toggle("Enabled", isOn: $enabled)
                .onChange(of: enabled) { _, isOn in
                    if isOn {
                        if adaptive {
                            writeBool(true)
                        } else {
                            writeCustom()
                        }
                    } else {
                        writeBool(false)
                    }
                }

            if enabled {
                Toggle("Adaptive (auto color)", isOn: $adaptive)
                    .onChange(of: adaptive) { _, isAdaptive in
                        if isAdaptive { writeBool(true) } else { writeCustom() }
                    }

                if !adaptive {
                    ValueField(label: "Width", value: $width, range: 0.25...4, step: 0.25)
                        .onChange(of: width) { _, _ in writeCustom() }

                    LabeledContent("Color") {
                        ColorPicker("", selection: colorBinding, supportsOpacity: true)
                            .labelsHidden()
                    }
                }
            }
        }
        .onAppear { syncFromCurrent() }
        .onChange(of: current) { _, c in syncFromCurrent(c) }
    }

    private func syncFromCurrent(_ override: BorderConfig? = nil) {
        switch override ?? current {
        case .disabled:
            enabled = false; adaptive = true
        case .auto:
            enabled = true; adaptive = true
        case .custom(let w, let c):
            enabled = true; adaptive = false; width = w; colorHex = c
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Theme.color(hex: colorHex) ?? .white },
            set: { color in
                colorHex = color.toHex8() ?? BorderConfig.defaultColor
                writeCustom()
            }
        )
    }

    private func writeBool(_ b: Bool) {
        let value: BorderConfig = b ? .auto : .disabled
        if let def = defaultBorder, value == def {
            ConfigLoader.shared.removeKey(section: section, key: key)
        } else {
            ConfigLoader.shared.write(section: section, key: key, value: .bool(b))
        }
    }

    private func writeCustom() {
        let value = BorderConfig.custom(width: width, color: colorHex)
        if let def = defaultBorder, value == def {
            ConfigLoader.shared.removeKey(section: section, key: key)
        } else {
            let raw = "{ width = \(width), color = \"\(colorHex)\" }"
            ConfigLoader.shared.write(section: section, key: key, value: .rawLiteral(raw))
        }
    }
}

// MARK: - ColorDarkRow

/// Single-row color field with light and dark pickers side by side.
///
/// `[☀ label]  [■ light][✏/✨]   ·   [🌙 label]  [■ dark][✏/✨]`
///
/// Uses direct @State Color bindings for each picker so SwiftUI's ColorPicker
/// always holds a stable reference — computed Binding(get:set:) recreated on
/// every render is a known source of silent no-ops on macOS NSColorPanel.
struct ColorDarkRow: View {
    let field: SettingsField   // must have darkKey != nil and type == .color
    let pluginID: String
    @ObservedObject private var loader = ConfigLoader.shared

    // String state: "#..." or "auto" — mirrors TOML, drives auto-mode logic
    @State private var baseHex:  String = ""
    @State private var darkHex:  String = ""

    // Color state: direct bindings for ColorPicker — stable across re-renders
    @State private var lightColor: Color = .white
    @State private var darkColor:  Color = .gray

    private var isLightAuto: Bool { baseHex == Theme.darkVariantAuto }
    private var isDarkAuto:  Bool { darkHex == Theme.darkVariantAuto }

    // Auto previews derived from the other side — update in real-time.
    private var autoLightColor: Color {
        guard let c = Theme.color(hex: darkHex) else { return field.adaptiveColor ?? .white }
        return Theme.generatedComplement(for: c)
    }
    private var autoDarkColor: Color {
        guard let c = Theme.color(hex: baseHex) else { return field.adaptiveColor ?? .white }
        return Theme.generatedComplement(for: c)
    }

    var body: some View {
        LabeledContent(field.label) {
            HStack(spacing: 6) {
                modeColumn(
                    symbol:    "sun.max",
                    isAuto:    isLightAuto,
                    autoColor: autoLightColor,
                    picker:    ColorSwatch(color: $lightColor)
                                   .onChange(of: lightColor) { _, c in onLightPicked(c) },
                    autoHelp:  "Auto-generated from dark. Click ✎ to set manually.",
                    manualHelp: "Generate from dark color.",
                    onToggle:  toggleLightAuto
                )
                Divider().frame(height: 22)
                modeColumn(
                    symbol:    "moon",
                    isAuto:    isDarkAuto,
                    autoColor: autoDarkColor,
                    picker:    ColorSwatch(color: $darkColor)
                                   .onChange(of: darkColor) { _, c in onDarkPicked(c) },
                    autoHelp:  "Auto-generated from light. Click ✎ to set manually.",
                    manualHelp: "Generate from light color.",
                    onToggle:  toggleDarkAuto
                )
            }
        }
        .onAppear { sync() }
        .onChange(of: baseConfigValue) { _, _ in sync() }
        .onChange(of: darkConfigValue)  { _, _ in sync() }
    }

    // MARK: - Column builder

    @ViewBuilder
    private func modeColumn(
        symbol: String,
        isAuto: Bool,
        autoColor: Color,
        picker: some View,
        autoHelp: String,
        manualHelp: String,
        onToggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            if isAuto {
                RoundedRectangle(cornerRadius: 4)
                    .fill(autoColor)
                    .frame(width: 28, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5))
            } else {
                picker
            }
            Button(action: onToggle) {
                Image(systemName: isAuto ? "pencil" : "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isAuto ? autoHelp : manualHelp)
        }
    }

    // MARK: - Picker change handlers

    private func onLightPicked(_ color: Color) {
        guard !isLightAuto else { return }
        guard let hex = color.toHex8() else { return }
        // onChange fires when sync() sets lightColor from config — skip those.
        // toHex8(Theme.color(hex: X)) == X for any valid 8-bit hex (stable round-trip),
        // so this guard reliably distinguishes sync-triggered from user-triggered changes.
        guard hex != baseConfigValue else { return }
        baseHex = hex
        commitBase(hex)
    }

    private func onDarkPicked(_ color: Color) {
        guard !isDarkAuto else { return }
        guard let hex = color.toHex8() else { return }
        guard hex != darkConfigValue else { return }
        darkHex = hex
        writeDark(hex)
    }

    // MARK: - Toggle actions

    private func toggleLightAuto() {
        if isLightAuto {
            let hex = autoLightColor.toHex8() ?? field.defaultValue
            baseHex = hex
            lightColor = Theme.color(hex: hex) ?? lightColor
            commitBase(hex)
        } else {
            if isDarkAuto {
                let hex = autoDarkColor.toHex8() ?? (field.darkDefaultValue ?? "")
                darkHex = hex
                darkColor = Theme.color(hex: hex) ?? darkColor
                writeDark(hex)
            }
            baseHex = Theme.darkVariantAuto
            commitBase(Theme.darkVariantAuto)
        }
    }

    private func toggleDarkAuto() {
        if isDarkAuto {
            let hex = autoDarkColor.toHex8() ?? (field.darkDefaultValue ?? "")
            darkHex = hex
            darkColor = Theme.color(hex: hex) ?? darkColor
            writeDark(hex)
        } else {
            if isLightAuto {
                let hex = autoLightColor.toHex8() ?? field.defaultValue
                baseHex = hex
                lightColor = Theme.color(hex: hex) ?? lightColor
                commitBase(hex)
            }
            darkHex = Theme.darkVariantAuto
            writeDark(Theme.darkVariantAuto)
        }
    }

    // MARK: - Config values

    private var baseConfigValue: String {
        loader.config.plugins[pluginID]?.settings[field.key] ?? field.defaultValue
    }

    private var darkConfigValue: String {
        guard let dk = field.darkKey else { return "" }
        return loader.config.plugins[pluginID]?.settings[dk] ?? field.darkDefaultValue ?? ""
    }

    private func sync() {
        let newBase = baseConfigValue
        let newDark = darkConfigValue
        baseHex = newBase
        darkHex = newDark
        if let c = Theme.color(hex: newBase) { lightColor = c }
        if let c = Theme.color(hex: newDark) { darkColor  = c }
    }

    // MARK: - Writes

    private func commitBase(_ value: String) {
        let section = "plugins.\(pluginID)"
        if value == field.defaultValue {
            ConfigLoader.shared.removeKey(section: section, key: field.key)
        } else {
            ConfigLoader.shared.write(section: section, key: field.key, value: .string(value))
        }
    }

    private func writeDark(_ value: String) {
        guard let dk = field.darkKey else { return }
        let section = "plugins.\(pluginID)"
        if value == (field.darkDefaultValue ?? "") {
            ConfigLoader.shared.removeKey(section: section, key: dk)
        } else {
            ConfigLoader.shared.write(section: section, key: dk, value: .string(value))
        }
    }
}

// MARK: - SettingsFieldRow

/// Schema-driven row for a single plugin field.
/// Uses `localValue` as the immediate source of truth so the UI responds
/// instantly to user input. The debounced write to config happens in the
/// background; `localValue` is re-synced when the config reload completes.
struct SettingsFieldRow: View {
    let field: SettingsField
    let pluginID: String
    @ObservedObject private var loader = ConfigLoader.shared

    /// The currently displayed value (string form). Updated immediately on
    /// user interaction; synced back from config after each reload.
    @State private var localValue: String = ""
    /// True while the user is actively editing a text field.
    /// Prevents config reloads from clobbering mid-typing keystrokes.
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(field.label) {
            fieldControl
        }
        .onAppear { localValue = configValue }
        // Only sync from config when the user is not actively typing.
        .onChange(of: configValue) { _, v in if !isFocused { localValue = v } }
    }

    /// Current persisted value (or schema default if not yet written).
    private var configValue: String {
        loader.config.plugins[pluginID]?.settings[field.key] ?? field.defaultValue
    }

    /// Update local state immediately and schedule the debounced disk write.
    /// If the new value matches the schema default, remove the key instead of writing it,
    /// keeping the config file free of redundant default entries.
    private func commit(_ str: String) {
        localValue = str
        if str == field.defaultValue {
            ConfigLoader.shared.removeKey(section: "plugins.\(pluginID)", key: field.key)
        } else {
            ConfigLoader.shared.write(section: "plugins.\(pluginID)", key: field.key, value: .string(str))
        }
    }

    // MARK: - Control

    @ViewBuilder private var fieldControl: some View {
        switch field.type {
        case .text:
            TextField("", text: Binding(get: { localValue }, set: { commit($0) }))
                .frame(maxWidth: 200)
                .focused($isFocused)

        case .color:
            ColorPicker("", selection: Binding(
                get: {
                    if !localValue.isEmpty, let c = Theme.color(hex: localValue) { return c }
                    return field.adaptiveColor ?? .white
                },
                set: { color in
                    if let hex = color.toHex8() { commit(hex) }
                }
            ), supportsOpacity: true)
            .labelsHidden()

        case .toggle:
            Toggle("", isOn: Binding(
                get: { localValue == "true" },
                set: { commit($0 ? "true" : "false") }
            )).labelsHidden()

        case .picker(let options):
            Picker("", selection: Binding(get: { localValue }, set: { commit($0) })) {
                ForEach(options, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

        case .stepper(let min, let max, let step):
            let dbl = Binding<Double>(
                get: { Double(localValue) ?? Double(field.defaultValue) ?? min },
                set: { v in
                    let c = Swift.min(Swift.max(v, min), max)
                    commit(step >= 1 && c.truncatingRemainder(dividingBy: 1) == 0
                           ? String(Int(c)) : String(c))
                }
            )
            HStack(spacing: 4) {
                TextField("", text: Binding(
                    get: {
                        let v = dbl.wrappedValue
                        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
                    },
                    set: { text in
                        if let p = Double(text) {
                            dbl.wrappedValue = Swift.min(Swift.max(p, min), max)
                        }
                    }
                ))
                .focused($isFocused)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                Stepper("", value: dbl, in: min...max, step: step)
                    .labelsHidden()
            }
        }
    }
}
