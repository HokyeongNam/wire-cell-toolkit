#include "WireCellUtil/Persist.h"
#include "WireCellUtil/String.h"
#include "WireCellUtil/Logging.h"
#include "WireCellUtil/Exceptions.h"

#include <cstdlib>  // for getenv, see get_path()

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#include <boost/iostreams/copy.hpp>
#include <boost/iostreams/filter/bzip2.hpp>
#include <boost/iostreams/device/file.hpp>
#include <boost/iostreams/filtering_stream.hpp>
#include <boost/filesystem.hpp>
#pragma GCC diagnostic pop

#include <string>
#include <sstream>
#include <fstream>

// see #239 for why this is here.
extern "C" {
    struct JsonnetVm;
    struct JsonnetVm* jsonnet_make();
    char *jsonnet_realloc(struct JsonnetVm *vm, char *buf, size_t sz);
    void jsonnet_destroy(struct JsonnetVm* vmRef);
    void jsonnet_jpath_add(struct JsonnetVm* vmRef, char* path);
    void jsonnet_ext_var(struct JsonnetVm* vmRef, char* key, char* value);
    void jsonnet_ext_code(struct JsonnetVm* vmRef, char* key, char* value);
    void jsonnet_tla_var(struct JsonnetVm* vmRef, char* key, char* value);
    void jsonnet_tla_code(struct JsonnetVm* vmRef, char* key, char* value);
    char* jsonnet_evaluate_file(struct JsonnetVm* vmRef, char* filename, int* e);
    char* jsonnet_evaluate_snippet(struct JsonnetVm* vmRef, char* filename, char* code, int* e);
}


using spdlog::debug;
using spdlog::error;
using spdlog::info;
using namespace std;
using namespace WireCell;

#define WIRECELL_PATH_VARNAME "WIRECELL_PATH"

static std::string file_extension(const std::string& filename)
{
    auto ind = filename.rfind(".");
    if (ind == string::npos) {
        return "";
    }
    return filename.substr(ind);
}

WireCell::Persist::TempDir::TempDir(const boost::filesystem::path& model, bool systmp, bool keep)
    : path(systmp ? boost::filesystem::temp_directory_path() / boost::filesystem::unique_path(model) : boost::filesystem::unique_path(model))
    , keep(keep)
{
    boost::filesystem::create_directories(path);
}
#include <iostream> // debug
WireCell::Persist::TempDir::~TempDir()
{
    if (keep) return;

    boost::filesystem::remove_all(path);
    // const std::string spath = path.native();
    // boost::system::error_code ec;
    // std::size_t removed_count =  boost::filesystem::remove_all(path, ec);
    // if (ec) {
    //     //debug("Error removing directory: {}", ec.message());
    //     std::cerr << "Error removing directory: " << ec.message() << endl;
    // }
    // else {
    //     std::cerr << "Removed: " << removed_count << " from " << spath << "\n";
    // }
}


void WireCell::Persist::dump(const std::string& filename, const Json::Value& jroot, bool pretty)
{
    string ext = file_extension(filename);

    /// default to .json.bz2 regardless of extension.
    std::fstream fp(filename.c_str(), std::ios::binary | std::ios::out);
    boost::iostreams::filtering_stream<boost::iostreams::output> outfilt;
    if (ext == ".bz2") {
        outfilt.push(boost::iostreams::bzip2_compressor());
    }
    outfilt.push(fp);
    if (pretty) {
// All of JsonCPP is deprecated in my but I don't want to deal with the details
// until we make the full jump to nlohmann::json.
#pragma GCC diagnostic push
#pragma GCC diagnostic warning "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        Json::StyledWriter jwriter;
#pragma GCC diagnostic pop
        outfilt << jwriter.write(jroot);
    }
    else {
#pragma GCC diagnostic push
#pragma GCC diagnostic warning "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        Json::FastWriter jwriter;
#pragma GCC diagnostic pop
        outfilt << jwriter.write(jroot);
    }
}

std::string WireCell::Persist::dumps(const Json::Value& obj, int indent, int nsig)
{
    Json::StreamWriterBuilder swb;

    if (indent < 0) {
        swb["indentation"] = std::string(std::abs(indent), '\t');
    }
    else {
        swb["indentation"] = std::string(indent, ' ');
    }

    const bool default_sig = nsig == 0 || nsig == 17;
    if (! default_sig) {
        swb["precision"] = nsig;
        // Note: there is also a "precisionType" option.  It defaults to
        // "significant" using "%.*g" or it can be "decimal" which uses "%.*f"
        // sprintf codes.
    }

    std::unique_ptr<Json::StreamWriter> w(swb.newStreamWriter());
    stringstream ss;
    w->write(obj, &ss);
    return ss.str();
}

std::string WireCell::Persist::slurp(const std::string& filename)
{
    std::string fname = resolve(filename);
    if (fname.empty()) {
        THROW(IOError() << errmsg{"no such file: " + filename + ". Maybe you need to add to WIRECELL_PATH."});
    }

    std::ifstream fstr(filename);
    std::stringstream buf;
    buf << fstr.rdbuf();
    return buf.str();
}

bool WireCell::Persist::exists(const std::string& filename)
{
    return boost::filesystem::exists(filename);
}

bool WireCell::Persist::assuredir(const std::string& pathname)
{
    boost::filesystem::path p(pathname);
    if ( ! p.extension().empty() ) {
        p = p.parent_path();
    }
    if (p.empty()) {
        return false;
    }
    return boost::filesystem::create_directories(p);
}

static std::vector<std::string> get_path()
{
    std::vector<std::string> ret;
    const char* cpath = std::getenv(WIRECELL_PATH_VARNAME);
    if (!cpath) {
        return ret;
    }
    for (auto path : String::split(cpath)) {
        ret.push_back(path);
    }
    return ret;
}

std::string WireCell::Persist::resolve(const std::string& filename)
{
    if (filename.empty()) {
        return "";
    }
    if (filename[0] == '/') {
        return filename;
    }

    std::vector<boost::filesystem::path> tocheck{
        boost::filesystem::current_path(),
    };
    for (auto pathname : get_path()) {
        tocheck.push_back(boost::filesystem::path(pathname));
    }
    for (auto pobj : tocheck) {
        boost::filesystem::path full = pobj / filename;
        if (boost::filesystem::exists(full)) {
            return boost::filesystem::canonical(full).string();
        }
    }
    return "";
}

Json::Value WireCell::Persist::load(const std::string& filename,
                                    const externalvars_t& extvar,
                                    const externalvars_t& extcode)
{
    string ext = file_extension(filename);
    std::string fname = resolve(filename);
    if (fname.empty()) {
        THROW(IOError() <<
              errmsg{"no such file: " + filename
                  + ". Maybe you need to add to WIRECELL_PATH."});
    }

    if (ext == ".jsonnet") {  // use libjsonnet++ file interface
        Parser parser(get_path(), extvar, extcode);
        return parser.load(fname);
    }

    // use jsoncpp file interface
    std::fstream fp(fname.c_str(), std::ios::binary | std::ios::in);
    boost::iostreams::filtering_stream<boost::iostreams::input> infilt;
    if (ext == ".bz2") {
        info("loading compressed json file: {}", fname);
        infilt.push(boost::iostreams::bzip2_decompressor());
    }
    infilt.push(fp);
    std::string text;
    Json::Value jroot;
    infilt >> jroot;
    // return update(jroot, extvar); fixme
    return jroot;
}

Json::Value WireCell::Persist::loads(const std::string& text,
                                     const externalvars_t& extvar,
                                     const externalvars_t& extcode)
{
    Parser parser(get_path(), extvar, extcode);
    return parser.loads(text);
}

// bundles few lines into function to avoid some copy-paste
Json::Value WireCell::Persist::json2object(const std::string& text)
{
    Json::Value res;
    stringstream ss(text);
    ss >> res;
    return res;
}


// std::string
// WireCell::Persist::evaluate_jsonnet_file(const std::string& filename,
//                                          const externalvars_t& extvar,
//                                          const externalvars_t& extcode)
// {
//     std::string fname = resolve(filename);
//     if (fname.empty()) {
//         THROW(IOError() <<
//               errmsg{"no such file: " + filename
//                   + ", maybe you need to add to WIRECELL_PATH."});
//     }

//     Parser parser(get_path(), extvar, extcode);
//     return parser.load(fname);
// }

// std::string
// WireCell::Persist::evaluate_jsonnet_text(const std::string& text,
//                                          const externalvars_t& extvar,
//                                          const externalvars_t& extcode)
// {
//     Parser parser(get_path(), extvar, extcode);
//     return parser.loads(text);
// }

namespace {
  auto to_chars(std::string const& str)
  {
    return const_cast<char*>(str.c_str());
  }

}

WireCell::Persist::Parser::~Parser()
{
    if (m_jvm) {
        jsonnet_destroy(m_jvm);
        m_jvm = nullptr;
    }
}


void WireCell::Persist::Parser::add_load_path(const std::string& path)
{
    jsonnet_jpath_add(m_jvm, to_chars(path));
}
void WireCell::Persist::Parser::bind_ext_var(const std::string& key,
                                             const std::string& val)
{
    jsonnet_ext_var(m_jvm, to_chars(key), to_chars(val));
}
void WireCell::Persist::Parser::bind_ext_code(const std::string& key,
                                              const std::string& val)
{
    jsonnet_ext_code(m_jvm, to_chars(key), to_chars(val));
}
void WireCell::Persist::Parser::bind_tla_var(const std::string& key,
                                             const std::string& val)
{
    jsonnet_tla_var(m_jvm, to_chars(key), to_chars(val));
}
void WireCell::Persist::Parser::bind_tla_code(const std::string& key,
                                              const std::string& val)
{
    jsonnet_tla_code(m_jvm, to_chars(key), to_chars(val));
}

WireCell::Persist::Parser::Parser(const std::vector<std::string>& load_paths, const externalvars_t& extvar,
                                  const externalvars_t& extcode, const externalvars_t& tlavar,
                                  const externalvars_t& tlacode)
    : m_jvm{jsonnet_make()}
{

    // Loading: 1) cwd, 2) passed in paths 3) environment
    m_load_paths.push_back(boost::filesystem::current_path());
    for (auto path : load_paths) {
        debug("search path: {}", path);
        m_load_paths.push_back(boost::filesystem::path(path));
    }
    for (auto path : get_path()) {
        //debug("search path: {}", path);
        m_load_paths.push_back(boost::filesystem::path(path));
    }
    // load paths into jsonnet backwards to counteract its reverse ordering
    for (auto pit = m_load_paths.rbegin(); pit != m_load_paths.rend(); ++pit) {
        auto path = boost::filesystem::canonical(*pit).string();
        add_load_path(path);
    }

    // external variables
    for (auto& vv : extvar) {
        bind_ext_var(vv.first, vv.second);
    }

    // external code
    for (auto& vv : extcode) {
        bind_ext_code(vv.first, vv.second);
    }

    // top level argument string variables
    for (auto& vv : tlavar) {
        debug("tla: {} = \"{}\"", vv.first, vv.second);
        bind_tla_var(vv.first, vv.second);
    }

    // top level argument code variables
    for (auto& vv : tlacode) {
        bind_tla_code(vv.first, vv.second);
    }
}

std::string WireCell::Persist::Parser::resolve(const std::string& filename)
{
    if (filename.empty()) {
        return "";
    }
    if (filename[0] == '/') {
        return filename;
    }

    for (auto pobj : m_load_paths) {
        boost::filesystem::path full = pobj / filename;
        if (boost::filesystem::exists(full)) {
            return boost::filesystem::canonical(full).string();
        }
    }
    return "";
}

Json::Value WireCell::Persist::Parser::load(const std::string& filename)
{
    std::string fname = resolve(filename);
    if (fname.empty()) {
        THROW(IOError() << errmsg{"no such file: " + filename + ". Maybe you need to add to WIRECELL_PATH."});
    }
    string ext = file_extension(filename);

    if (ext == ".jsonnet" or ext.empty()) {  // use libjsonnet++ file interface
        int rc=0;
        char* jtext = jsonnet_evaluate_file(m_jvm, to_chars(fname), &rc);
        if (rc) {
            error(jtext);
            THROW(ValueError() << errmsg{jtext});
        }
        std::string output(jtext);
        jsonnet_realloc(m_jvm, jtext, 0);
        return json2object(output);
    }

    // also support JSON, possibly compressed

    // use jsoncpp file interface
    std::fstream fp(fname.c_str(), std::ios::binary | std::ios::in);
    boost::iostreams::filtering_stream<boost::iostreams::input> infilt;
    if (ext == ".bz2") {
        info("loading compressed json file: {}", fname);
        infilt.push(boost::iostreams::bzip2_decompressor());
    }
    infilt.push(fp);
    std::string text;
    Json::Value jroot;
    infilt >> jroot;
    // return update(jroot, extvar); fixme
    return jroot;
}

Json::Value WireCell::Persist::Parser::loads(const std::string& text)
{
    int rc=0;
    char* jtext = jsonnet_evaluate_snippet(m_jvm, to_chars("<stdin>"), to_chars(text), &rc);
    if (rc) {
        error(jtext);
        THROW(ValueError() << errmsg{jtext});
    }
    std::string output(jtext);
    jsonnet_realloc(m_jvm, jtext, 0);
    return json2object(output);
}
