#pragma once

// The disc's file layout for sce_lbn raw-sector reads (tools/analysis/lbn.py): install_disc_map() reads
// <game>/lbn.tsv (LBN hex, size hex, disc-relative path) and hands it to the runtime (rt::map_disc_files).
// Call from the mount hook, after rt::set_storage().

#include "jdarc/core.hpp"

namespace jdarc::game {

void install_disc_map();

}  // namespace jdarc::game
