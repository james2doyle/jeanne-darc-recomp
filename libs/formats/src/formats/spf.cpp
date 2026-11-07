#include "jdarc/formats/spf.hpp"

#include <cstring>

namespace jdarc::format::spf {

bool check_magic(std::span<const std::byte> data) {
    static constexpr char kMagic[] = {'S', 'F', 'P', '\0'};
    return data.size() >= 4 && std::memcmp(data.data(), kMagic, 4) == 0;
}

}  // namespace jdarc::format::spf
