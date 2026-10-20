import SwiftUI

/// Settings → About: version, the app's own licence, credits for the
/// third-party work the body-composition formulas come from, privacy policy,
/// source code, and the medical / trademark disclaimers.
struct AboutView: View {
    static let repoURL = URL(string: "https://github.com/PhilippGrulich/my-scale")!
    static let privacyURL = URL(string: "https://github.com/PhilippGrulich/my-scale/blob/main/docs/PRIVACY.md")!
    static let supportURL = URL(string: "https://github.com/PhilippGrulich/my-scale/issues")!

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Link(destination: Self.repoURL) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: Self.privacyURL) { Label("Privacy policy", systemImage: "hand.raised") }
                Link(destination: Self.supportURL) { Label("Support & feedback", systemImage: "questionmark.bubble") }
            } footer: {
                Text("Mochi is open source. No account, no tracking — your data stays on your devices and in Apple Health.")
            }

            Section("Licenses") {
                NavigationLink("Mochi — MIT License") {
                    LicenseText(title: "Mochi", text: Licenses.myOpenScale)
                }
                NavigationLink("Xiaomi_Scale_Body_Metrics — MIT License") {
                    LicenseText(title: "Xiaomi_Scale_Body_Metrics", text: Licenses.lolouk44)
                }
                NavigationLink("bodymiscale — Apache License 2.0") {
                    LicenseText(title: "bodymiscale", text: Licenses.bodymiscale)
                }
            }

            Section {
                Text("The body-composition estimates (body fat, lean and muscle mass, water, bone mass, visceral fat, basal metabolic rate, metabolic age, protein) are based on the formulas published in lolouk44/Xiaomi_Scale_Body_Metrics and dckiller51/bodymiscale.")
            } header: {
                Text("Acknowledgements")
            }
            .font(.footnote)

            Section {
                Text("Body-composition values are estimates, not medical advice. Talk to a doctor before making health decisions.")
                Text("Works with the Xiaomi Mi Body Composition Scale 2. Mochi is an independent app and is not affiliated with, endorsed by, or sponsored by Xiaomi. Apple Health and Apple Watch are trademarks of Apple Inc.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("About")
    }
}

private struct LicenseText: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Full licence texts shown in About (they must ship with the app).
enum Licenses {
    static let mitBody = """
    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """

    static let myOpenScale = "MIT License\n\nCopyright (c) 2026 Philipp Grulich\n\n" + mitBody

    static let lolouk44 = """
    MIT License

    Xiaomi_Scale_Body_Metrics — https://github.com/lolouk44/xiaomi_mi_scale
    Copyright (c) lolouk44 and contributors

    """ + mitBody

    static let bodymiscale = """
    bodymiscale — https://github.com/dckiller51/bodymiscale
    Copyright (c) dckiller51 and contributors

    Licensed under the Apache License, Version 2.0 (the "License"); you may not \
    use this file except in compliance with the License. You may obtain a copy of \
    the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software \
    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT \
    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the \
    License for the specific language governing permissions and limitations under \
    the License.

    Mochi reimplements the published body-composition equations in Swift; \
    no bodymiscale source code is included.
    """
}
