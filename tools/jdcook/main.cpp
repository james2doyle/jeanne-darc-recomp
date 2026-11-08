// jdcook — finds PSMF movies on the extracted disc and converts both streams into cooked media.
// FFmpeg is only needed here, never at runtime. Existing outputs are kept so interrupted runs can resume.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>

#include "psprecore/cli.hpp"
#include "psprecore/error.hpp"
#include "psprecore/formats/atrac.hpp"
#include "psprecore/formats/cooked.hpp"
#include "psprecore/formats/psmf.hpp"
#include "psprecore/io/file.hpp"
#include "psprecore/io/path.hpp"
#include "core/foundation/containers/map.h"
#include "core/foundation/core/callable.h"
#include "core/foundation/core/foundation.h"
#include "core/foundation/platform/filesystem.h"
#include "core/foundation/strings/format.h"
#include "core/foundation/strings/utf8_string.h"
#include "core/foundation/threading/sync.h"
#include "core/foundation/threading/thread.h"

using namespace psprecore;

namespace {

struct Options {
    nx::string ffmpeg = "ffmpeg";
    unsigned jobs = std::max(1u, nx::cpu::logical_core_count() / 2);
    std::size_t limit = static_cast<std::size_t>(-1);
    bool force = false, keep_temp = false;
    int audio_quality = 6, video_crf = 26;
};

nx::string quote(nx::fs::path_view path) { return nx::string("\"") + path.native() + "\""; }

// Runs a command line through the shell; returns the exit status.
int run(const nx::string& command) {
#ifdef _WIN32
    // cmd.exe strips the outer quotes of a command that starts with one; wrap the whole line once more.
    return std::system(("\"" + command + "\"").c_str());
#else
    return std::system(command.c_str());
#endif
}

struct Task {
    nx::string label;
    nx::unique_function<bool()> work;
};

class Cooker {
public:
    Cooker(const Options& options, nx::fs::path_view out)
        : opt_(options), out_(out.native()), tmp_(path_join(out_, "tmp")) {
        for (const nx::string& dir : {path_join(out_, "movies"), tmp_})
            if (!nx::fs::create_directories(dir)) throw Error("cannot create directory '" + dir + "'");
    }

    nx::string ffmpeg() const { return quote(opt_.ffmpeg) + " -hide_banner -loglevel error -nostdin -y"; }

    // Writes a temporary input, runs FFmpeg, and atomically moves the result into place. Freshly written files can
    // be briefly locked on Windows, so retries cover both writing the input and renaming the finished output.
    bool transcode(nx::string_view name, std::span<const std::byte> data, nx::string_view input_args,
                   nx::string_view output_args, nx::fs::path_view out) {
        const nx::string in = path_join(tmp_, name);
        const nx::string part = nx::string(out.native()) + ".part";
        bool ok = false;
        for (int attempt = 0; attempt < 3 && !ok; ++attempt) {
            if (attempt) nx::this_thread::sleep_for(std::chrono::milliseconds(500 * attempt));
            try {
                io::write_all(in, data);
            } catch (const std::exception&) {
                continue;
            }
            ok = run(ffmpeg() + " " + input_args + " -i " + quote(in) + " " + output_args + " " + quote(part)) == 0;
        }
        if (!opt_.keep_temp) (void)nx::fs::remove(in);
        if (!ok) {
            (void)nx::fs::remove(part);
            return false;
        }
        for (int attempt = 0; attempt < 5; ++attempt) {
            if (nx::fs::rename(part, out)) return true;
            nx::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
        return false;
    }

    nx::string vorbis_args() const {
        // FFmpeg's ATRAC3plus decoder repeats input timestamps, which corrupts Ogg granule positions.
        return nx::format("-af asetpts=N/SR/TB -c:a libvorbis -q:a {} -f ogg", opt_.audio_quality);
    }

    // PSMF -> AV1 video (one frame per access unit, in display order) + Ogg Vorbis audio.
    bool cook_movie(std::size_t entry, std::span<const std::byte> file, std::uint64_t key) {
        psmf::Header header;
        if (!psmf::parse_header(file, header)) return false;
        psmf::Demuxer demux;
        nx::vector<std::byte> video, audio;
        std::uint64_t index = 0;
        const auto drain = [&] {
            for (auto& unit : demux.units(psmf::kVideo)) {
                const auto* bytes = reinterpret_cast<const std::byte*>(unit.data.data());
                video.insert(video.end(), bytes, bytes + unit.data.size());
            }
            demux.units(psmf::kVideo).clear();
            for (auto& unit : demux.units(psmf::kAudio)) {
                // ATRAC access units start with an 8-byte frame header, not part of the RIFF data chunk.
                if (unit.data.size() <= 8) continue;
                const auto* bytes = reinterpret_cast<const std::byte*>(unit.data.data());
                audio.insert(audio.end(), bytes + 8, bytes + unit.data.size());
            }
            demux.units(psmf::kAudio).clear();
        };
        for (std::size_t pos = header.data_offset; pos + psmf::kPackSize <= file.size(); pos += psmf::kPackSize) {
            demux.feed(file.subspan(pos, psmf::kPackSize), index++);
            drain();
        }
        demux.finish();
        drain();

        const nx::string stem = nx::format("m{}", entry);
        bool ok = true;
        const nx::string video_out = cooked::movie_video_path(out_, key);
        if (!video.empty() && (opt_.force || !nx::fs::exists(video_out))) {
            ok = transcode(stem + ".h264", video, "-framerate 30000/1001 -f h264",
                           nx::format("-c:v libsvtav1 -preset 6 -crf {} -g 300 -pix_fmt yuv420p -f ivf",
                                      opt_.video_crf),
                           video_out);
        }
        const nx::string audio_out = cooked::movie_audio_path(out_, key);
        if (ok && !audio.empty() && demux.atrac_params() && (opt_.force || !nx::fs::exists(audio_out)))
            ok = transcode(stem + ".at3", atrac::make_atrac3plus_riff(audio, demux.atrac_params(), 2), "",
                           vorbis_args(), audio_out);
        return ok;
    }

private:
    Options opt_;
    nx::string out_, tmp_;
};

struct Source {
    nx::string path;
    std::uint64_t key = 0;
};

int cook(nx::fs::path_view game, nx::fs::path_view out_dir, const Options& opt) {
#ifdef _WIN32
    _putenv_s("SVT_LOG", "1");  // SVT-AV1: errors only
#else
    setenv("SVT_LOG", "1", 1);
#endif
    const auto entries = nx::fs::recursive_directory_entries(game);
    if (!entries) throw Error("cannot list directory '" + nx::string(game.native()) + "'");
    nx::vector<nx::string> paths;
    for (const auto& entry : entries.value())
        if (entry.type == nx::fs::file_type::regular) paths.push_back(entry.path);
    std::sort(paths.begin(), paths.end());

    Cooker cooker(opt, out_dir);
    const nx::string out(out_dir.native());
    nx::vector<Task> tasks;
    nx::map<std::uint64_t, std::size_t> seen;
    std::size_t movie_count = 0, skipped = 0, duplicates = 0;

    const auto schedule = [&](const Source& source) {
        const std::size_t entry = tasks.size();
        tasks.push_back({"movie " + source.path, nx::unique_function<bool()>([&cooker, entry, source] {
                             const auto file = io::read_all(source.path);
                             const std::span<const std::byte> data(file.data(), file.size());
                             return cooker.cook_movie(entry, data, source.key);
                         })});
    };

    for (const auto& path : paths) {
        const auto file = io::read_all(path);
        const std::span<const std::byte> data(file.data(), file.size());
        psmf::Header header;
        const bool movie = data.size() >= psmf::kPackSize &&
                           psmf::parse_header(data.first(psmf::kPackSize), header);
        if (!movie || movie_count >= opt.limit) continue;
        const std::uint64_t key = cooked::fnv1a64(data.first(psmf::kPackSize));
        if (!seen.emplace(key, 0).second) {
            ++duplicates;
            continue;
        }
        const bool exists = nx::fs::exists(cooked::movie_video_path(out, key)) &&
                            nx::fs::exists(cooked::movie_audio_path(out, key));
        if (exists && !opt.force) {
            ++skipped;
            continue;
        }
        ++movie_count;
        schedule({path, key});
    }

    std::fprintf(stderr, "cooking %zu movies with %u jobs (%zu already cooked, %zu duplicates)\n", movie_count,
                 opt.jobs, skipped, duplicates);

    std::atomic<std::size_t> next{0}, done{0}, failed{0};
    nx::mutex log;
    nx::vector<nx::thread> pool;
    for (unsigned j = 0; j < opt.jobs; ++j)
        pool.emplace_back([&] {
            for (std::size_t t; (t = next++) < tasks.size();) {
                bool ok = false;
                try {
                    ok = tasks[t].work();
                } catch (const std::exception& e) {
                    nx::scoped_lock lock(log);
                    std::fprintf(stderr, "%s: %s\n", tasks[t].label.c_str(), e.what());
                }
                const std::size_t n = ++done;
                if (!ok) ++failed;
                nx::scoped_lock lock(log);
                std::fprintf(stderr, "[%zu/%zu] %s%s\n", n, tasks.size(), tasks[t].label.c_str(), ok ? "" : "  FAILED");
            }
        });
    for (auto& thread : pool) thread.join();
    if (!opt.keep_temp) (void)nx::fs::remove(path_join(out, "tmp"));
    std::fprintf(stderr, "done: %zu cooked, %zu failed\n", tasks.size() - failed.load(), failed.load());
    return failed ? 1 : 0;
}

}  // namespace

int main(int argc, char** argv) {
    Options opt;
    nx::string game, out;
    nx::cli::Parser cli("jdcook", "Finds PSMF movies on an extracted disc and converts them to AV1 (IVF) + Ogg "
                                  "Vorbis. Existing outputs are kept.");
    cli.root()
        .positional("game", game, "the extracted disc folder")
        .positional("out", out, "cooked media folder")
        .option("ffmpeg", opt.ffmpeg, "FFmpeg executable (default: ffmpeg on PATH)", {.value_name = "PATH"})
        .option("jobs", opt.jobs, "parallel FFmpeg processes (default: half the CPU threads)", {.value_name = "N"})
        .option("limit", opt.limit, "cook at most N movies (testing)", {.value_name = "N"})
        .flag("force", opt.force, "overwrite existing outputs")
        .flag("keep-temp", opt.keep_temp, "keep FFmpeg's intermediate files")
        .option("audio-quality", opt.audio_quality, "Vorbis quality 0-10 (default: 6)", {.value_name = "Q"})
        .option("video-crf", opt.video_crf, "SVT-AV1 CRF (default: 26)", {.value_name = "N"});
    if (const int code = parse_command_line(cli, argc, argv); code >= 0) return code;
    try {
        opt.jobs = std::max(1u, opt.jobs);
        return cook(game, out, opt);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "jdcook: %s\n", e.what());
        return 1;
    }
}
