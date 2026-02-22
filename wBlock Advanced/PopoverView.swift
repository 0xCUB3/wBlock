import SwiftUI
import wBlockCoreService

/// SwiftUI popover for wBlock Advanced
struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Divider()

                Toggle("Disable on this site", isOn: $viewModel.isDisabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Element zapper")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(viewModel.zapperRules.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.activateElementZapper() }
                        } label: {
                            Text("Activate")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button {
                            viewModel.deleteAllZapperRules()
                        } label: {
                            Text("Clear")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(viewModel.zapperRules.isEmpty)
                    }

                    Text("Click an element on the page to hide it.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                DisclosureGroup(
                    blockedRequestsTitle,
                    isExpanded: $viewModel.showingBlockedRequests
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.blockedRequests.isEmpty {
                            Text("No blocked requests yet.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.blockedRequests, id: \.self) { url in
                                    Text(url)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Refresh") {
                                Task { await viewModel.refreshBlockedRequests() }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 6)
                }

                DisclosureGroup(
                    zapperRulesTitle,
                    isExpanded: $viewModel.showingZapperRules
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.zapperRules.isEmpty {
                            Text("No zapper rules for this site.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.zapperRules, id: \.self) { rule in
                                HStack(spacing: 8) {
                                    Text(rule.isEmpty ? String(localized: "(empty rule)") : rule)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        viewModel.deleteZapperRule(rule)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                Text(blockedCountText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 320)
        .onAppear {
            Task {
                await viewModel.loadState()
            }
        }
        .onChange(of: viewModel.showingBlockedRequests) { expanded in
            guard expanded else { return }
            Task { await viewModel.refreshBlockedRequests() }
        }
        .onChange(of: viewModel.showingZapperRules) { expanded in
            guard expanded else { return }
            Task { await viewModel.loadZapperRules() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("wBlock")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(LocalizedStringKey(viewModel.isDisabled ? "Disabled" : "Active"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(statusBorder, lineWidth: 1)
                        )
                        .cornerRadius(999)
                }

                Text(viewModel.host.isEmpty ? "—" : viewModel.host)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var statusBackground: Color {
        viewModel.isDisabled ? Color.red.opacity(0.18) : Color.green.opacity(0.18)
    }

    private var statusBorder: Color {
        viewModel.isDisabled ? Color.red.opacity(0.45) : Color.green.opacity(0.45)
    }

    private var blockedCountText: String {
        switch viewModel.blockedCount {
        case 0:
            return String(localized: "Blocked: 0")
        case 1:
            return String(localized: "Blocked: 1")
        default:
            return String.localizedStringWithFormat(
                NSLocalizedString("Blocked: %d", comment: "Blocked request count"),
                viewModel.blockedCount
            )
        }
    }

    private var blockedRequestsTitle: String {
        String.localizedStringWithFormat(
            NSLocalizedString("Blocked requests (%d)", comment: "Blocked requests disclosure title"),
            viewModel.blockedRequests.count
        )
    }

    private var zapperRulesTitle: String {
        String.localizedStringWithFormat(
            NSLocalizedString("Zapper rules (%d)", comment: "Element zapper rules disclosure title"),
            viewModel.zapperRules.count
        )
    }
}

#if DEBUG
struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(viewModel: PopoverViewModel())
    }
}
#endif
