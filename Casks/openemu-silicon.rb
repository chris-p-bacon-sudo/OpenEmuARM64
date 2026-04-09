cask "openemu-silicon" do
  version "1.0.4"
  sha256 "3bfee455fe5839467e055c152537009857245e80732d1347a1ab233cd92d8e86"

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
