#pragma once

// The game's code lives in namespace jdarc and uses the runtime's (psprecore) names as its own: io::, rt::,
// platform::, path_join, Error...
namespace psprecore {}

namespace jdarc {
using namespace psprecore;
}  // namespace jdarc
