cask "openemu-silicon" do
  version "1.0.3"
  sha256 "70c4000259c5e8f0433fd6d81c85118871fce18ed1695099260472f2d48c1bdf"

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
