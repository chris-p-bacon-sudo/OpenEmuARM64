/*
	Copyright 2024 flyinghead

	This file is part of Flycast.

    Flycast is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    Flycast is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Flycast.  If not, see <https://www.gnu.org/licenses/>.
*/
// Stub for Xcode builds: cmrc embedded resources are not available,
// so all resource lookups return empty/null.
#include "resources.h"

namespace resource
{

std::unique_ptr<u8[]> load(const std::string& /*path*/, size_t& size)
{
	size = 0;
	return nullptr;
}

std::vector<std::string> listDirectory(const std::string& /*path*/)
{
	return {};
}

}
