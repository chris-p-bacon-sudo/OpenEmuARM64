// Copyright (c) 2022, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#ifdef __x86_64__
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit64_Tables.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_Branch.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_FloatingPoint.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_Integer.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_LoadStore.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_LoadStoreFloating.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_LoadStorePaired.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_Paired.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/Jit_SystemRegisters.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64/JitAsm.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/BlockCache.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/ConstantPool.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/EmuCodeBlock.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/FarCodeCache.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/Jit64AsmCommon.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/Jit64Common/TrampolineCache.cpp"
#elif defined(__arm64__)
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/Jit_Util.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/Jit.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_Branch.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_FloatingPoint.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_Integer.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_LoadStore.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_LoadStoreFloating.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_LoadStorePaired.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_Paired.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_RegCache.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_SystemRegisters.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_Tables.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64Cache.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitAsm.cpp"
#include "../../dolphin/Source/Core/Core/PowerPC/JitArm64/JitArm64_BackPatch.cpp"
#endif
