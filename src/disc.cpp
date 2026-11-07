#include "disc.hpp"

#include <cstdio>

#include "psprecore/io/path.hpp"
#include "psprecore/runtime/io.hpp"
#include "psprecore/text.hpp"

namespace jdarc::game {

void install_disc_map() {
    const nx::string path = path_join(rt::game_dir(), "lbn.tsv");
    const auto text = nx::fs::file_read_text(path);
    if (!text.has_value()) {
        std::fprintf(stderr, "disc: no lbn.tsv at %s (run tools/analysis/lbn.py); sce_lbn reads will fail\n",
                     path.c_str());
        return;
    }
    nx::vector<rt::DiscFile> files;
    nx::string_view rest(text.value());
    while (!rest.empty()) {
        std::size_t nl = rest.find('\n');
        nx::string_view line = rest.substr(0, nl);
        rest = nl == nx::string_view::npos ? nx::string_view{} : rest.substr(nl + 1);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty() || line[0] == '#') continue;
        // "<lbn hex> <size hex> <disc-relative path>"
        const std::size_t sp1 = line.find(' ');
        const std::size_t sp2 = sp1 == nx::string_view::npos ? sp1 : line.find(' ', sp1 + 1);
        if (sp1 == nx::string_view::npos || sp2 == nx::string_view::npos) continue;
        try {
            rt::DiscFile f;
            f.lbn = static_cast<std::uint32_t>(parse_u64(line.substr(0, sp1), 16));
            f.size = static_cast<std::uint32_t>(parse_u64(line.substr(sp1 + 1, sp2 - sp1 - 1), 16));
            nx::string_view rel = line.substr(sp2 + 1);
            while (!rel.empty() && (rel.front() == '/' || rel.front() == '\\')) rel.remove_prefix(1);
            f.path = nx::string(rel);
            if (f.size == 0) continue;
            files.push_back(std::move(f));
        } catch (const std::exception& e) {
            std::fprintf(stderr, "disc: %s: bad line: %s\n", path.c_str(), e.what());
        }
    }
    std::fprintf(stderr, "disc: %zu files in the LBN map (%s)\n", files.size(), path.c_str());
    rt::map_disc_files(std::move(files));
}

}  // namespace jdarc::game
