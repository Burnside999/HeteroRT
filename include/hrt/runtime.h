#include <string>
#include <functional>

#include "cuda_runtime.h"

namespace hrt {

// ---------- Device / Runtime ----------
struct Device {
    enum class Kind { CPU, CUDA /* future: ROCM, Vulkan, ... */ };
    Kind kind;
    int id; // CUDA device id, CPU use 0
};

class Runtime {
  public:
    static Runtime Create();

    Device cpu() const;
    Device cuda(int device_id = 0) const;

    // Resources live across graphs, reusable
    template <class T>
    class Buffer buffer(std::string name, size_t count);

    template <class T>
    class Scalar scalar(std::string name); // host-visible scalar

    class Token token(std::string name); // for side effects

    class Graph graph(std::string name = ""); // build a structured program graph
    void run(class Graph& g);                 // blocking run (or return Exec handle)
};

// ---------- Resources ----------
struct ResourceId {
    uint64_t v;
};

class IResource {
  public:
    virtual ResourceId id() const = 0;
};

template <class T>
class Buffer : public IResource {
  public:
    size_t size() const;

    // 1D contiguous view for dependency precision
    class View view(size_t offset, size_t count) const;

    // full buffer view
    View all() const;
};

template <class T>
class Scalar : public IResource {
  public:
    // Host-side access (after produced)
    T get_blocking() const;
    void set_host(T v); // used to feed constants
};

class Token : public IResource {};

// ---------- Task ----------
enum class Access { Read, Write, ReadWrite };

struct LaunchCfg {
    dim3 grid, block;
    size_t shmem = 0; /* + stream policy later */
};

class TaskHandle {
    uint64_t v;
};

class Task {
  public:
    TaskHandle handle() const;

    // device binding (v1: explicit)
    Task& on(Device d);

    // resource usage
    Task& reads(const IResource& r);
    Task& writes(const IResource& r);
    Task& rw(const IResource& r);

    // explicit control edge (for cases data dep can't express)
    Task& after(TaskHandle h);

    // CPU implementation
    Task& cpu(std::function<void()> fn);

    // CUDA implementation
    template <class Kernel, class... Args>
    Task& cuda(Kernel k, LaunchCfg cfg, Args... args);

    // Mark task has external side effects (shortcut)
    // Equivalent to writes(token("side_effects"))
    Task& side_effect(const Token& t);
};

// ---------- Structured blocks ----------
struct LoopOptions {
    bool cross_iter_parallel = false; // default: false (your requirement)
    int max_inflight = 1;             // when cross_iter_parallel=true, limit concurrency
};

class Seq;
class Par;
class Iter;

class Seq {
  public:
    Task task(std::string name);

    void seq(std::function<void(Seq&)> f); // nested seq
    void par(std::function<void(Par&)> f); // fork-join par

    void loop(int64_t n, LoopOptions opt, std::function<void(Iter& it, int64_t i)> body);

    // predicate: host bool OR Scalar<bool>
    void if_(bool pred, std::function<void(Seq&)> then_blk, std::function<void(Seq&)> else_blk);

    void
    if_(const Scalar<bool>& pred,
        std::function<void(Seq&)> then_blk,
        std::function<void(Seq&)> else_blk);
};

class Par {
  public:
    Task task(std::string name);

    // allow nested structures inside par region too
    void seq(std::function<void(Seq&)> f);
    void par(std::function<void(Par&)> f);
    void loop(int64_t n, LoopOptions opt, std::function<void(Iter& it, int64_t i)> body);
    void if_(bool pred, std::function<void(Seq&)>, std::function<void(Seq&)>);
    void if_(const Scalar<bool>& pred, std::function<void(Seq&)>, std::function<void(Seq&)>);
};

// Iter is basically a Seq with index
class Iter : public Seq {
  public:
    int64_t index() const; // current i
};

class Graph {
  public:
    Seq& root(); // root is sequential by default (easy mental model)
};

} // namespace hrt