#pragma once

#include <cstdint>
#include <span>

#include "jdarc/core.hpp"

namespace jdarc::format::spf {

// The .SPF container (sound, maps, models...): "SFP\0" magic, then a table of entries.
// Layout below the header is still being documented (see PORT_PLAN.md Phase 2);
// parse_* throw Error on files that do not match yet.
struct Entry {
    std::uint32_t offset = 0;
    std::uint32_t size = 0;
};

bool check_magic(std::span<const std::byte> data);

}  // namespace jdarc::format::spf
