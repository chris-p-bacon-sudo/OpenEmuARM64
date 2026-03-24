/*
	Copyright 2022 flyinghead

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
// Stub network implementations for Apple/OpenEmu builds where
// http_client.cpp is excluded and no Obj-C networking is available.
#if defined(__APPLE__)
#include "http_client.h"

namespace http {

void init() {}
void term() {}

int get(const std::string& /*url*/, std::vector<u8>& /*content*/, std::string& /*contentType*/)
{
	return 500;
}

int post(const std::string& /*url*/, const char* /*payload*/, const char* /*contentType*/, std::vector<u8>& /*reply*/)
{
	return 500;
}

int post(const std::string& /*url*/, const std::vector<PostField>& /*fields*/)
{
	return 500;
}

} // namespace http
#endif // __APPLE__
