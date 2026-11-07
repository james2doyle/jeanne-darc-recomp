#include "mods.hpp"

#include <cstdio>

#include "psprecore/runtime/io.hpp"
#include "core/foundation/containers/map.h"
#include "core/foundation/core/foundation.h"
#include "core/foundation/platform/filesystem.h"
#include "core/foundation/strings/utf8_string.h"

namespace jdarc::game {

namespace {

// One overlay for all mods: any file under a mod folder at a disc-relative path (PSP_GAME/...) replaces the
// disc file of the same path when the game opens it by name (see rt::DiscOverlay::file in hle_io.cpp).
// Later mods win. Textures under mods/<name>/textures are handled separately by the runtime's
// texture_replacement scan in the front end.
class ModOverlay final : public rt::DiscOverlay {
public:
    nx::map<nx::string, nx::vector<char>> files;
    void read_sectors(std::uint64_t, std::uint64_t, char*) override {
        // Loose files on the disc: the game reads by name, never by raw UMD sector.
    }
    const nx::vector<char>* file(nx::string_view path) override {
        if (const auto it = files.find(nx::string(path)); it != files.end()) return &it->second;
        return nullptr;
    }
};

}  // namespace

void set_mods(std::span<const nx::string> mods) {
    auto overlay = std::make_unique<ModOverlay>();
    std::size_t folders = 0;
    for (const auto& m : mods) {
        auto entries = nx::fs::recursive_directory_entries(m);
        if (!entries.has_value()) continue;
        bool any = false;
        for (const auto& e : entries.value()) {
            if (e.type != nx::fs::file_type::regular) continue;
            nx::string_view rel = nx::string_view(e.path).substr(m.size() + (m.ends_with("/") ? 0 : 1));
            nx::string lower;
            lower.reserve(rel.size());
            for (char c : rel) lower.push_back(c == '\\' ? '/' : static_cast<char>(tolower(c)));
            if (!lower.starts_with("psp_game/")) continue;
            const auto bytes = nx::fs::file_read(e.path);
            if (!bytes.has_value()) {
                std::fprintf(stderr, "mods: cannot read %s\n", e.path.c_str());
                continue;
            }
            const auto* raw = reinterpret_cast<const char*>(bytes.value().data());
            overlay->files[std::move(lower)].assign(raw, raw + bytes.value().size());
            any = true;
        }
        if (any) ++folders;
    }
    if (overlay->files.empty()) return;
    std::fprintf(stderr, "mods: %zu files overlaid from %zu mod folders\n", overlay->files.size(), folders);
    rt::set_disc_overlay(std::move(overlay));
}

}  // namespace jdarc::game
