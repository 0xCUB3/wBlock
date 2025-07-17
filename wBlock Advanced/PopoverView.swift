import SwiftUI
import wBlockCoreService

/// SwiftUI popover for wBlock Advanced
struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("wBlock Ad Blocker")
                .font(.headline)
                .frame(maxWidth: .infinity)

            // Blocked count
            Text(blockedCountText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Disable toggle
            Toggle(isOn: $viewModel.isDisabled) {
                Text(viewModel.host.isEmpty ? "Disable for this site" : "Disable for \(viewModel.host)")
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.top, 8)

                // Minimal disclaimer directly under toggle
                VStack(spacing: 2) {
                    Text("Safari may take a few minutes to apply changes.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("Restart Safari if needed.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            
            // Element Zapper button
            Button(action: {
                Task {
                    await viewModel.activateElementZapper()
                }
            }) {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.white)
                    Text("Element Zapper")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
            
            
                // Zapper Rules section
            VStack(spacing: 8) {
                Button(action: {
                    viewModel.toggleZapperRules()
                }) {
                    HStack {
                        Text("Zapper Rules (\(viewModel.zapperRules.count))")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: viewModel.showingZapperRules ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                if viewModel.showingZapperRules {
                    VStack(spacing: 4) {
                        if viewModel.zapperRules.isEmpty {
                            Text("No zapper rules for this site")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            // Rules list
                            VStack(spacing: 3) {
ForEach(viewModel.zapperRules, id: \.self) { rule in
                                    HStack {
                                        Text(rule.isEmpty ? "(empty rule)" : rule)
                                            .font(.system(size: 11))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            viewModel.deleteZapperRule(rule)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(4)
                                }
                            }
                            .frame(maxHeight: 120)
                            
                            // Clear all button
                            Button(action: {
                                viewModel.deleteAllZapperRules()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                    Text("Clear All")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            Task {
                await viewModel.loadState()
            }
        }
    }

    private var blockedCountText: String {
        switch viewModel.blockedCount {
        case 0:
            return "No requests blocked on this page."
        case 1:
            return "1 request blocked on this page."
        default:
            return "\(viewModel.blockedCount) requests blocked on this page."
        }
    }
}

#if DEBUG
struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(viewModel: PopoverViewModel())
    }
}
#endif
