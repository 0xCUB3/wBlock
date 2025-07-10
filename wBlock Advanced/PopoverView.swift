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
            
            // Element Zapper button
            Button(action: {
                viewModel.activateElementZapper()
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
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            viewModel.loadState()
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
