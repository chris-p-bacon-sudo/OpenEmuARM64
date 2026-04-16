cask "openemu-silicon" do
  version "1.0.5"
  sha256 "e41345cdcbaf90985fc17c858d699be0e5b759fb6b5e35f98b393fea22871f01"

  url "https://github.com/nickybmon/OpenEmu-Silicon/releases/download/v#{version}/OpenEmu-Silicon.dmg"
  name "OpenEmu Silicon"
  desc "Native Apple Silicon port of the OpenEmu multi-system emulator"
  homepage "https://github.com/nickybmon/OpenEmu-Silicon"

  depends_on macos: ">= :big_sur"

  app "OpenEmu.app"

  zap trash: [
    "~/Library/Application Support/OpenEmu",
    "~/Library/Preferences/org.openemu.OpenEmu.plist",
    "~/Library/Caches/org.openemu.OpenEmu",
  ]
end
