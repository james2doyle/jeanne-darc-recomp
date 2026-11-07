#pragma once

// Mods for a game with loose files on the disc: a mod folder (mods/<name>/) holds replacement files at their
// disc-relative paths (e.g. mods/hd/PSP_GAME/USRDIR/DATA/WMAP.SPF), plus optional textures (mods/<name>/textures,
// psprecore/gpu/texture_replacement.hpp). Later mods win. Call from the mount hook (after rt::set_storage()).

#include <span>

#include "jdarc/core.hpp"
#include "core/foundation/core/foundation.h"
#include "core/foundation/strings/utf8_string.h"

namespace jdarc::game {

void set_mods(std::span<const nx::string> mods);

}  // namespace jdarc::game
