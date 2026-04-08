// Copyright 2010 Dolphin Emulator Project
// Licensed under GPLv2+
// Refer to the license.txt file included.

#include <vector>

#include "Common/FileUtil.h"
#include "Common/IniFile.h"
#include "Common/MsgHandler.h"
#include "Common/StringUtil.h"
#include "Core/ConfigManager.h"
#include "Core/Core.h"
#include "Core/HW/Wiimote.h"
#include "InputCommon/ControllerEmu/ControlGroup/ControlGroup.h"
#include "InputCommon/ControllerEmu/ControllerEmu.h"
#include "InputCommon/ControllerEmu/Setting/NumericSetting.h"
#include "InputCommon/ControllerInterface/ControllerInterface.h"
#include "InputCommon/InputConfig.h"
#include "InputCommon/InputProfile.h"

InputConfig::InputConfig(const std::string& ini_name, const std::string& gui_name,
                         const std::string& profile_directory_name,
                         const std::string& profile_key)
    : m_ini_name(ini_name), m_gui_name(gui_name),
      m_profile_directory_name(profile_directory_name), m_profile_key(profile_key)
{
}

InputConfig::~InputConfig() = default;

bool InputConfig::LoadConfig()
{
  // OpenEmu Stub
  return false;
}

void InputConfig::SaveConfig()
{
  std::string ini_filename = File::GetUserPath(D_CONFIG_IDX) + m_ini_name + ".ini";

  Common::IniFile inifile;
  inifile.Load(ini_filename);

  for (auto& controller : m_controllers)
    controller->SaveConfig(inifile.GetOrCreateSection(controller->GetName()));

  inifile.Save(ini_filename);
}

ControllerEmu::EmulatedController* InputConfig::GetController(int index) const
{
  return m_controllers.at(index).get();
}

void InputConfig::ClearControllers()
{
  m_controllers.clear();
}

bool InputConfig::ControllersNeedToBeCreated() const
{
  return m_controllers.empty();
}

int InputConfig::GetControllerCount() const
{
  return static_cast<int>(m_controllers.size());
}

void InputConfig::RegisterHotplugCallback()
{
  // Update control references on all controllers
  // as configured devices may have been added or removed.
  m_hotplug_event_hook = g_controller_interface.RegisterDevicesChangedCallback([this] {
    for (auto& controller : m_controllers)
      controller->UpdateReferences(g_controller_interface);
  });
}

void InputConfig::UnregisterHotplugCallback()
{
  // Deregistration happens automatically when m_hotplug_event_hook is destroyed.
  m_hotplug_event_hook.reset();
}

bool InputConfig::IsControllerControlledByGamepadDevice(int index) const
{
  if (static_cast<size_t>(index) >= m_controllers.size())
    return false;

  const auto& controller = m_controllers.at(index).get()->GetDefaultDevice();

  // Filter out anything which obviously not a gamepad
  return !((controller.source == "Quartz")      // OSX Quartz Keyboard/Mouse
           || (controller.source == "XInput2")  // Linux and BSD Keyboard/Mouse
           || (controller.source == "Android" &&
               controller.name == "Touchscreen")  // Android Touchscreen
           || (controller.source == "DInput" &&
               controller.name == "Keyboard Mouse"));  // Windows Keyboard/Mouse
}

std::string InputConfig::GetUserProfileDirectoryPath() const
{
  return File::GetUserPath(D_CONFIG_IDX) + m_profile_directory_name + "/";
}

std::string InputConfig::GetSysProfileDirectoryPath() const
{
  // OpenEmu Stub — SYSDATA_DIR is an internal define in FileUtil.cpp
  return File::GetSysDirectory() + "Sys/" + m_profile_directory_name + "/";
}

void InputConfig::GenerateControllerTextures(const Common::IniFile& file)
{
  // OpenEmu Stub
}

void InputConfig::GenerateControllerTextures()
{
  // OpenEmu Stub
}
