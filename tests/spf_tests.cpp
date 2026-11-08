// SPF container magic check (docs/formats.md). Table layout tests once the entry table is documented.
#include "jdarc/formats/spf.hpp"

#include <span>

#include "test_main.hpp"

using namespace jdarc;

TEST_CASE("spf magic") {
    const std::byte good[] = {std::byte{'S'}, std::byte{'F'}, std::byte{'P'}, std::byte{0}};
    const std::byte bad[] = {std::byte{'A'}, std::byte{'t'}, std::byte{'e'}, std::byte{'l'}};
    CHECK(format::spf::check_magic(good));
    CHECK(!format::spf::check_magic(bad));
    CHECK(!format::spf::check_magic({}));
}
