// Popup script for wBlock Scripts (iOS)

async function updateBlockedCount() {
    try {
        const blockedCountElement = document.getElementById('blocked-count');

        // Try to get the current tab URL
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });

        if (tabs && tabs.length > 0) {
            blockedCountElement.textContent = 'Content blocking is active for this page';
        } else {
            blockedCountElement.textContent = 'Content blocking is active';
        }
    } catch (error) {
        console.error('Error updating blocked count:', error);
        document.getElementById('blocked-count').textContent = 'Content blocking is active';
    }
}

// Update the display when the popup is opened
document.addEventListener('DOMContentLoaded', () => {
    updateBlockedCount();
});
