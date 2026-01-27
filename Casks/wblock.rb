cask "wblock" do
  version "latest"
  sha256 :no_check

  url "https://github.com/0xCUB3/wBlock/releases/latest/download/wBlock.dmg",
      verified: "github.com/0xCUB3/wBlock/"
  name "wBlock"
  desc "Safari content blocker for macOS, iOS, and iPadOS"
  homepage "https://github.com/0xCUB3/wBlock"

  app "wBlock.app"
end
