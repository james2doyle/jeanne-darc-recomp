// jdarc: Jeanne d'Arc (UCUS98700) on the recompiled-game runtime. Options: see the runtime's
// frontend (psprecore/platform/frontend.hpp).

#ifdef __ANDROID__
#include <SDL3/SDL_main.h>  // main() becomes SDL_main, called by SDLActivity
#endif

#include "psprecore/platform/frontend.hpp"
#include "disc.hpp"
#include "mods.hpp"

namespace jdarc::game {

namespace {

void mount(std::span<const nx::string> mods) {
    install_disc_map();  // sce_lbn raw-sector reads (FILEINFO.DAT -> LBN map)
    set_mods(mods);      // whole-file replacements (mods/<name>/PSP_GAME/...)
}

constexpr platform::GameInfo kGame{
    .title = "Jeanne d'Arc",
    .name = "jdarc",
    .folder = "Jeanne d'Arc",
    .load_base = 0x08804000,
    .mount = mount,
};

}  // namespace

}  // namespace jdarc::game

int main(int argc, char** argv) { return psprecore::platform::run_game(jdarc::game::kGame, argc, argv); }
