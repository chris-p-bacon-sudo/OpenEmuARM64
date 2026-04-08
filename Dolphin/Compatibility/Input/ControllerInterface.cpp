// Copyright 2010 Dolphin Emulator Project
// Licensed under GPLv2+
// Refer to the license.txt file included.

#include "InputCommon/ControllerInterface/ControllerInterface.h"

//OpenEmu undefine the OSX settings
#ifdef CIFACE_USE_OSX
#undef CIFACE_USE_OSX
#endif

//OpenEmu include OE input header
#include "OpenEmuInput.h"

#include <algorithm>

#include "Common/Logging/Log.h"
#include "Core/HW/WiimoteReal/WiimoteReal.h"

#ifdef CIFACE_USE_WIN32
#include "InputCommon/ControllerInterface/Win32/Win32.h"
#endif
#ifdef CIFACE_USE_XLIB
#include "InputCommon/ControllerInterface/Xlib/XInput2.h"
#endif
#ifdef CIFACE_USE_OSX
#include "InputCommon/ControllerInterface/OSX/OSX.h"
#include "InputCommon/ControllerInterface/Quartz/Quartz.h"
#endif
#ifdef CIFACE_USE_SDL
#include "InputCommon/ControllerInterface/SDL/SDL.h"
#endif
#ifdef CIFACE_USE_ANDROID
#include "InputCommon/ControllerInterface/Android/Android.h"
#endif
#ifdef CIFACE_USE_EVDEV
#include "InputCommon/ControllerInterface/evdev/evdev.h"
#endif
#ifdef CIFACE_USE_PIPES
#include "InputCommon/ControllerInterface/Pipes/Pipes.h"
#endif
#ifdef CIFACE_USE_DUALSHOCKUDPCLIENT
#include "InputCommon/ControllerInterface/DualShockUDPClient/DualShockUDPClient.h"
#endif

ControllerInterface g_controller_interface;
static bool m_is_populating_devices = false;

void ControllerInterface::Initialize(const WindowSystemInfo& wsi)
{
  if (m_is_init)
    return;

  m_wsi = wsi;

  // Allow backends to add devices as soon as they are initialized.
  m_is_init = true;

  m_is_populating_devices = true;

#ifdef CIFACE_USE_WIN32
  m_input_backends.emplace_back(ciface::Win32::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_XLIB
  m_input_backends.emplace_back(ciface::XInput2::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_OSX
  if (m_wsi.type == WindowSystemType::MacOS)
  {
    m_input_backends.emplace_back(ciface::OSX::CreateInputBackend(this));
    m_input_backends.emplace_back(ciface::Quartz::CreateInputBackend(this));
  }
#endif
#ifdef CIFACE_USE_SDL
  m_input_backends.emplace_back(ciface::SDL::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_ANDROID
  m_input_backends.emplace_back(ciface::Android::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_EVDEV
  m_input_backends.emplace_back(ciface::evdev::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_PIPES
  m_input_backends.emplace_back(ciface::Pipes::CreateInputBackend(this));
#endif
#ifdef CIFACE_USE_DUALSHOCKUDPCLIENT
  m_input_backends.emplace_back(ciface::DualShockUDPClient::CreateInputBackend(this));
#endif

  // OpenEmu: initialize OpenEmu Input
  Input::Openemu_Input_Init();

  RefreshDevices();

  // OpenEmu: set populating devices to false
  m_is_populating_devices = false;
}

static thread_local ciface::InputChannel tls_input_channel = ciface::InputChannel::Host;

void ControllerInterface::SetCurrentInputChannel(ciface::InputChannel input_channel)
{
  tls_input_channel = input_channel;
}

ciface::InputChannel ControllerInterface::GetCurrentInputChannel()
{
  return tls_input_channel;
}

void ControllerInterface::PlatformPopulateDevices(std::function<void()> callback)
{
  if (!m_is_init)
    return;

  std::lock_guard lk_population(m_devices_population_mutex);

  m_populating_devices_counter.fetch_add(1);

  callback();

  if (m_populating_devices_counter.fetch_sub(1) == 1)
    InvokeDevicesChangedCallbacks();
}

void ControllerInterface::ChangeWindow(void* hwnd, WindowChangeReason reason)
{
  if (!m_is_init)
    return;

  // This shouldn't use render_surface so no need to update it.
  m_wsi.render_window = hwnd;
  RefreshDevices();
}

void ControllerInterface::RefreshDevices(RefreshReason reason)
{
  if (!m_is_init)
    return;

  // OpenEmu: keep controllers; do not clear device list on refresh
//  {
//    std::lock_guard lk(m_devices_mutex);
//    m_devices.clear();
//  }

  m_is_populating_devices = true;

  // Make sure shared_ptr<Device> objects are released before repopulating.
  InvokeDevicesChangedCallbacks();

  for (auto& backend : m_input_backends)
    backend->PopulateDevices();

  WiimoteReal::ProcessWiimotePool();

  m_is_populating_devices = false;
  InvokeDevicesChangedCallbacks();
}

// Remove all devices and call library cleanup functions
void ControllerInterface::Shutdown()
{
  if (!m_is_init)
    return;

  // Prevent additional devices from being added during shutdown.
  m_is_init = false;

  {
    std::lock_guard lk(m_devices_mutex);

    for (const auto& d : m_devices)
    {
      // Set outputs to ZERO before destroying device
      for (ciface::Core::Device::Output* o : d->Outputs())
        o->SetState(0);
    }

    m_devices.clear();
  }

  // This will update control references so shared_ptr<Device>s are freed up
  // BEFORE we shutdown the backends.
  InvokeDevicesChangedCallbacks();

  m_input_backends.clear();
}

bool ControllerInterface::AddDevice(std::shared_ptr<ciface::Core::Device> device)
{
  // If we are shutdown (or in process of shutting down) ignore this request:
  if (!m_is_init)
    return false;

  {
    std::lock_guard lk(m_devices_mutex);

    const auto is_id_in_use = [&device, this](int id) {
      return std::any_of(m_devices.begin(), m_devices.end(), [&device, &id](const auto& d) {
        return d->GetSource() == device->GetSource() && d->GetName() == device->GetName() &&
               d->GetId() == id;
      });
    };

    const auto preferred_id = device->GetPreferredId();
    if (preferred_id.has_value() && !is_id_in_use(*preferred_id))
    {
      // Use the device's preferred ID if available.
      device->SetId(*preferred_id);
    }
    else
    {
      // Find the first available ID to use.
      int id = 0;
      while (is_id_in_use(id))
        ++id;

      device->SetId(id);
    }

    NOTICE_LOG_FMT(CONTROLLERINTERFACE, "Added device: {}", device->GetQualifiedName());
    m_devices.emplace_back(std::move(device));
  }

  if (!m_is_populating_devices)
    InvokeDevicesChangedCallbacks();
  return true;
}

void ControllerInterface::RemoveDevice(std::function<bool(const ciface::Core::Device*)> callback, bool force_devices_release)
{
  {
    std::lock_guard lk(m_devices_mutex);
    auto it = std::remove_if(m_devices.begin(), m_devices.end(), [&callback](const auto& dev) {
      if (callback(dev.get()))
      {
        NOTICE_LOG_FMT(CONTROLLERINTERFACE, "Removed device: {}", dev->GetQualifiedName());
        return true;
      }
      return false;
    });
    m_devices.erase(it, m_devices.end());
  }

  if (!m_is_populating_devices)
    InvokeDevicesChangedCallbacks();
}

// Update input for all devices if lock can be acquired without waiting.
void ControllerInterface::UpdateInput()
{
  // Don't block the UI or CPU thread (to avoid a short but noticeable frame drop)
  if (m_devices_mutex.try_lock())
  {
    std::lock_guard lk(m_devices_mutex, std::adopt_lock);
    for (const auto& d : m_devices)
      d->UpdateInput();
  }
}

void ControllerInterface::SetAspectRatioAdjustment(float value)
{
  m_aspect_ratio_adjustment = value;
}

Common::Vec2 ControllerInterface::GetWindowInputScale() const
{
  const auto ar = m_aspect_ratio_adjustment.load();

  if (ar > 1)
    return {1.f, ar};
  else
    return {1 / ar, 1.f};
}

void ControllerInterface::SetMouseCenteringRequested(bool center)
{
  m_requested_mouse_centering = center;
}

bool ControllerInterface::IsMouseCenteringRequested() const
{
  return m_requested_mouse_centering;
}

// Register a callback to be called when a device is added or removed.
// Returns an EventHook (RAII) that auto-deregisters when destroyed.
[[nodiscard]] Common::EventHook
ControllerInterface::RegisterDevicesChangedCallback(Common::HookableEvent<>::CallbackType callback)
{
  return m_devices_changed_event.Register(std::move(callback));
}

// Invoke all callbacks that were registered
void ControllerInterface::InvokeDevicesChangedCallbacks()
{
  m_devices_changed_event.Trigger();
}

WindowSystemInfo ControllerInterface::GetWindowSystemInfo() const
{
  return m_wsi;
}

void ControllerInterface::ClearDevices()
{
  std::lock_guard lk(m_devices_mutex);
  m_devices.clear();
}
