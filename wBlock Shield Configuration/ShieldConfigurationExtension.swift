import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func configuration(context: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundColor: .systemBackground,
            title: .init(
                text: NSLocalizedString("wBlock", comment: "Shield title"),
                color: .label
            ),
            subtitle: .init(
                text: String(
                    format: NSLocalizedString(
                        "Screen Time is blocking %@.",
                        comment: "Shield context"
                    ),
                    context
                ),
                color: .secondaryLabel
            ),
            primaryButtonLabel: .init(
                text: NSLocalizedString("Close", comment: "Shield primary action"),
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: .init(
                text: NSLocalizedString(
                    "Allow for 15 Minutes",
                    comment: "Shield secondary action"
                ),
                color: .systemBlue
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(
            context: webDomain.domain
                ?? NSLocalizedString("this website", comment: "Unknown website")
        )
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            context: webDomain.domain
                ?? category.localizedDisplayName
                ?? NSLocalizedString("this category", comment: "Unknown category")
        )
    }
}
