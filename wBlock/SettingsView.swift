import SwiftUI
import wBlockCoreService

struct SettingsView: View {
@AppStorage("isBadgeCounterEnabled", store: UserDefaults(suiteName: GroupIdentifier.shared.value))
private var isBadgeCounterEnabled = true
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])
            
            Form {
                Section {
                    Toggle("Show blocked item count in toolbar", isOn: $isBadgeCounterEnabled)
                    .toggleStyle(.switch)
                }
                
                Section {
                    HStack {
                        Text("wBlock Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
                .textCase(.none)
            }
            .formStyle(.grouped)
            
            Spacer()
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 200)
        #endif
    }
}
