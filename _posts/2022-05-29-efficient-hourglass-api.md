---
title: "Efficient Hourglass APIs"
date: 2022-05-29
layout: post
published: true
---

Today we will be covering hourglass APIs. In effect: wrapping C++ APIs around C
APIs around C++ APIs. It's turtles all the way down!

Many of the concepts discussed can apply to other programming languages. Most of
the focus will be placed on the ABI stable C layer of an hourglass pattern
library design, which is where most of the critical decisions are made.

# Table of contents

1. [What is an Hourglass API](#what)
2. [Illustrative Hourglass API libfoo](#illustrative)
  * [C API Header](#illustrative-c-header)
  * [C++ Implementation](#illustrative-cpp-impl)
  * [C++ API Wrapper Header](#illustrative-cpp-wrapper)
  * [C++ Client app_bar](#illustrative-cpp-client-appbar)
3. [What are the Benefits of an Hourglass API?](#benefits)
  * [ABI Stability](#benefits-abi-stability)
  * [Downstream Portability](#benefits-downstream-portability)
  * [Implementation Hiding](#benefits-impl-hiding)
4. [Performance Concerns](#perf)
  * [Customizing Memory Allocation](#perf-memory-allocation)
  * [Reducing Memory Allocations & Controlling Memory Layout](#perf-controlling-memory)
  * [Static Libraries and LTO](#perf-static-lto)
5. [Avoiding ABI Breakage](#abi)
  * [Size & Layout Changes](#abi-struct-layout)
  * [API Argument/Return Value Changes](#abi-arg-return)
6. [Closing Thoughts](#closing)


# <a name="what">What is an Hourglass API?</a>

In the world of API implementation there is a design pattern commonly called the
_hourglass API_ pattern [^1].

It is named an _hourglass API_ because it consists of three distinct API layers,
the size of which follows an hourglass pattern:

 * A broad implementation at the bottom-most layer (often a feature-full systems
   language such as modern C, C++, or Rust) -- languages with complex run-times
   and garbage collection can be used, but this is much less common due to
   additional wrapping complexities and dependencies.
 * A thin and feature-limited layer in the middle (commonly C, specifically C89)
   -- the ideal is an implementation with a stable ABI, and simple bindings
   access to client languages.
 * A broad layer at the top (in any target client language) -- providing the
   full feature-set & native ergonomics you wish to expose to your end-user.

Even if you are implementing your library itself in C, it's a naturally arising
pattern. Consider when you clearly delineating between internal functions & types
as opposed to those officially define as being stable in the public API. While
this is a natural result of the development process, it's often beneficial to
carry out this delineation systematically. We will discuss this further later.


# <a name="illustrative">Illustrative Hourglass API libfoo</a>

We will build off of a simple example. In this example we have:
 * A library named `libfoo` written in C++.
 * A client application named `app_bar` written in C++.
 * `libfoo` provides some primitives to do some unspecified work which `app_bar`
   utilizes.

If you are already familiar with the basic concept of hourglass APIs, feel free
to skip to the next section of the article.

A simple hourglass API for `libfoo` may look as follows:

## <a name="illustrative-c-header">C API Header</a>

This is the middle ABI stable layer:
```c
/* libfoo.h */
/* Opaque type, only used via pointer. */
struct libfoo_foo;

/* Allocate memory AND construct.
 * A real implementation would have better error reporting. */
libfoo_foo* libfoo_create_foo();
/* Do baz on given foo. */
void libfoo_do_baz(libfoo_foo*);
/* If non-null, deinitialize and then release. */
void libfoo_free_foo(libfoo_foo*);
```

## <a name="illustrative-cpp-impl">C++ API Implementation</a>

This is the bottom-most implementation layer:
```cpp
// foo_lib_internal.cpp
#include "libfoo.h"

// Imagine we have some template functions etc. under the hood.

class InternalFoo
{
public:
    // Some interface
    void baz() { /* Some behavior */ }

private:
    // Some data (could be C++ containers, etc.)
};

extern "C"
{

// Opaque type
struct libfoo_foo
{
    InternalFoo foo;
};

libfoo_foo* libfoo_create_foo()
{
    auto* f{static_cast<libfoo*>(std::malloc(sizeof(libfoo_foo)))};
    if (nullptr == f)
    {
        return nullptr;
    }
    try
    {
        // Construct the C++ object inside the allocated memory.
        // You can avoid separating allocation and construction in this case,
        // I keep them separated because we will talk about this later.
        ::new (&f->foo) InternalFoo{};
        return f;
    }
    catch (...) // We can't let exceptions cross ABI boundaries
    {
        std::free(f);
        return nullptr;
    };
}

void libfoo_do_baz(libfoo_foo* f)
{
    if (nullptr == f)
    {
        // A real implementation would error report
        return;
    }

    try
    {
        f->foo.baz();
    }
    catch (...)
    {
        // A real implementation would error report
        return;
    }
}

void libfoo_free_foo(libfoo_foo* f)
{
    if (nullptr != f)
    {
        // Destroy the C++ object - similarly to allocation+construction you can
        // also just use `new`. We don't in order to aid later explanation.
        std::destroy_at(&f->foo);
        std::free(f);
    }
}

} // extern "C"
```

## <a name="illustrative-cpp-wrapper">C++ Wrapper API Header</a>

This is the upper-most client-side layer of the library:
```cpp
// foo_lib_wrapper.hpp
class Foo {
public:
    Foo() : _foo{libfoo_create_foo()}
    {
        if (nullptr == _foo)
        {
            throw std::runtime_error{"Unable to create libfoo foo!"};
        }
    }
    ~Foo() noexcept
    {
        if (nullptr != _foo)
        {
            libfoo_free_foo(_foo);
            _foo = nullptr;
        }
    }

    // ... Ignoring copy/move for now ...

    void baz() { libfoo_do_baz(_foo); }

private:
    libfoo_foo* _foo{nullptr};
};
```

## <a name="illustrative-cpp-client-appbar">C++ Client app_bar</a>

Here is a very simple usage example of the library in `app_bar`:
```cpp
// app_bar.cpp
#inlude <foo_lib_wrapper.hpp>

int main(int /* argc */, char* /* argv */[])
{
    while (true)
    {
        Foo foo{};
        foo.baz();
        // Imagine there's some eventual break condition
    }

    return 0;
}
```

That was quite a bit of code. Don't worry too much about it -- it's primarily
just to illustrate the idea of an hourglass API. Generally I think the idea
should already be quite intuitive, especially now that you have a concrete
example.

From this point onward, we will mostly ignore the top-most C++ wrapper layer and
the bottom-most C++ implementation layer. Instead we will focus on the C ABI
middle layer. In other words, focusing on the thinnest point of the hourglass.
This part is, in my opinion, the where the magic happens. The middle layer also
proves to be the most critical for creating efficient APIs with stable ABIs
(Application Binary Interface), with the upper abstractive and lower
implementation layers being significantly less critical. For sake of argument,
we will reintroduce `app_bar` but in a C form directly using the C API.


# <a name="benefits">Benefits of an Hourglass API</a>

What exactly are the benefits of using a hourglass API pattern for your library?
There are a fair few...

## <a name="benefits-abi-stability">ABI Stability</a>

A restricted subset of C89 has a very stable ABI. By exposing an API written in
such a form, you gain the ability to maintain longstanding compatibility for
binary artifacts such as shared/dynamic libraries. This means client
applications can dynamically link to new or old versions with high degree of
success, which is a very useful property for doing things such as providing
transparent performance and security improvements without needing to rebuild
client applications.

Note that this stability is not automatically guaranteed. As mentioned earlier,
it's only stable as long as platform owners decide to maintain that stability
and not make breaking changes to the platform's C ABI, and if you restrict your
"stable" interfaces to a relatively feature minimal interface. Additionally
there are other things which you need to be careful of to avoid accidentally
breaking ABI compatibility. This is discussed further in a later section.

As is often the case in software development, maintaining ABI compatibility is
as much about social factors as it is about technical ones -- it is critical to
utilize effective mechanisms for communicating the state of compatibility to
your users, whether this by some kind of automated checks, or by softer measures
such as client-visible semantic versioning. Robust systems are key to abiding by
contracts.

## <a name="benefits-downstream-portability">Downstream Portability</a>

C -- and more specifically C89 -- is lingua franca of the computing world.
Almost every language has support for interfacing with C code. Additionally,
most programmers can at least understand basic C interfaces, meaning relevant
documentation has a very large potential audience. C has its problems, but this
widespread support is a major factor as to why it is still in such heavy use in
interfaces everywhere.

The key implication of C's ubiquity is that it providing a C API allows almost
every language environment out there to immediately gain access to your library
at an exceedingly low cost. It cannot be overstated how powerful this is. It is
by no mistake that some of the oldest and most widely used software libraries
continue provide C APIs.

## <a name="benefits-impl-hiding">Implementation Hiding</a>

Firewalling your implementation away from the client interface by providing a C
API as the fundamental public interface means that the implementation can use
any platform, language, tools or techniques. Your library could be implemented
in C, Rust, C++, Go, and many, many more. This allows you, as a library
implementer, great flexibility. As long as you maintain behavioral and C API
compatibility (which can both be tested using automated means no less), you are
able to seamlessly make alterations to the underlying technology.

For example: Consider you are using `libfoo`, and for one platform you target
there is no supported C++ toolchain. It is totally feasible to write an
implementation conforming to the same interface for this platform using its own
custom toolchain and/or language-platform. Conversely, if a new
language-platform comes along that offers a better implementation experience
(for instance, migrating from C implementation to a Rust implementation for
security purposes), then this can be done without breaking existing client
applications and their usage models. An hourglass model offers great power of
abstraction.

Implementation hiding through the hourglass model has other potential benefits:
It can be used to hide proprietary information or to allow for differing
distribution models of artifacts at each step in the hourglass. For example,
imagine you have a library for interfacing with a custom piece of hardware (e.g.
a driver of some kind). By wrapping this with a separate public C API, you
retain the ability to hide how to interface with this proprietary technology
from direct public consumption in primarily source-based environments.


# <a name="perf">Performance Concerns</a>

Using the hourglass pattern naively can lead to some additional performance
overheads.

In order to illustrate this, let us look at a simple alternative `app_bar`
implementation directly calling the C API:
```cpp
// app_bar.c
#inlude <foo_lib.h>

int main(int, char*[])
{
    /* Allocate a new set of `foo`s */
    libfoo_foo* fs[N];
    for (int i = 0; i < N; ++i)
    {
        fs[i] = libfoo_create_foo();
    }

    /* Do some work over all our `foo`s every iteration. */
    while (true)
    {
        for (int i = 0; i < N; ++i)
        {
            /*
             * This could be accessing memory all over the place! Cache
             * efficiency drops through the floor.
             */
            libfoo_do_baz(fs[i]);
        }
    }

    /* ... */
}
```

In order to maintain an ABI firewall, we have had to hide implementation
details. As a result of this, things such as allocation decisions are left up to
the implementation layer. This is often fine for simple use-cases, but consider
the case of `libfoo` being a very low-level library intended for performance
use-cases. By leaving allocation decisions up to the implementation, we make it
difficult for client applications to tailor things such as memory layout and
access patterns for their needs.

## <a name="perf-memory-allocation">Customizing Memory Allocation</a>

By leaving allocation decisions entirely up to the implementation, we disallow
deviating from the implementers' decision. If the implementer decided to use
`malloc` and `free`, then we have no choice to but to rely on the system
allocator (or any library-based replacement `malloc` implementation we so
choose).

The obvious solution to this is to add some customization hook point. A common
technique for this often seen in small libraries such as the `stb_` family of
C micro-libraries is via a function pointer table:

```c
struct libfoo_allocator
{
    void* (*malloc)(unsigned long /* size */);
    void (*free)(void* /* ptr */);
};
/*
 * A global allocator table used by the library for allocating memory.
 * Default to malloc/free.
 */
libfoo_allocator libfoo_allocator_table = {&malloc, &free};
```

If the user wants to make the library use a custom allocator, they simply change
the relevant function pointers at run-time. The library will then delegate to
this table for all allocations/deallocations.

Clearly, in this example case we are using a global table which may not always
be suitable. Different data might be best allocated with different mechanisms.
We could fix this by simply passing a table explicitly to all potentially
allocating `libfoo` routines, or offering multiple such vtables.

There are performance implications to this, as now every allocation/deallocation
occurs via an additional indirection. Most of the time this is a low-priority
issue as the overhead of allocation/deallocation will exceed the indirection
cost, but as you optimize the allocation/deallocation routines, this overhead
becomes more and more prominent.

## <a name="perf-controlling-memory">Reducing Memory Allocations & Controlling Memory Layout</a>

Another alternative approach that works around the mentioned issues with the
function pointer table approach described above is to break up the API, and
reduce the responsibilities of individual API calls.

Your C API should be fine-grained enough such that whenever it needs. You can
remedy the additional complexity by offering a higher-level API that combines
these lower-level, advanced API calls and uses sensible defaults for things like
allocation. If the client needs control, they can choose to drop to the advanced
layer where needed. This brings you away from fancy C function pointer tricks,
and back towards general classic API design principles [^2]. Additionally,
because you aren't using function pointers, you avoid additional indirections.
Even better is that the function pointer table trick can also be used in
conjunction with this approach if needed (e.g. for the simple API layered atop
the advanced API).

As an example: Imagine I wanted to design an API allowing full memory control,
where a client could write the earlier described C `app_bar` routine, but reuse
the same memory. You approximate this with the following:
```c
// app_bar.c
#inlude <foo_lib.h>

int main(int, char*[])
{
    /*
     * We provide the resource for the library. Only a single allocation. Note
     * that we still don't need to know what foo _is_ only its size.
     */
    void* f = malloc(libfoo_size_foo()*N);

    /* Ask the library to fill our resource with `foo`s. */
    libfoo_foo* fs[N];
    for (int i = 0; i < N; ++i)
    {
        /* All the `foo`s are now contiguous! */
        fs[i] = libfoo_construct_foo(f + N*libfoo_size_foo());
    }

    while (true)
    {
        for (int i = 0; i < N; ++i)
        {
            /* Cache efficient iteration over spacially localized `foo`s. */
            libfoo_do_baz(fs[i]);
        }
    }

    /* ... */
}
/*
 * The simple higher level API described earlier can /also/ be provided on top
 * of these APIs.
 */
```

Now this example is more complex and loses some type-safety, but one can imagine
how a higher-level C++ wrapper could take advantage of this more fundamental,
advanced API to achieve extremely high performance and good ergonomics at the
same time.

The primary take-away from this is that even with hourglass APIs, it is entirely
possible to provide greater user-control if you are careful with your API
design.


## <a name="perf-static-lto">Static Libraries and LTO</a>

Where without the hourglass approach we may have had one single API layer, now
with the hourglass model we have three distinct layers. This can introduce some
overhead. The compiler has little capability to gain visibility across the
function call between the top and middle layers. This is by design, and is
largely what gives access to the ABI stability guarantees we have discussed thus
far.

This does not have to be the case, however. Suppose you also provide your
library as a static library. The use of LTO (Link-Time Optimization) [^3] with
your compiler & linker could potentially allow the build process the ability to
optimize away large amounts of the overhead between all the hourglass layers. Of
course, this would come at the cost of ABI stability, but this leaves the choice
up to the end-user of your library. If the user:
 * Chooses to link statically - they get no ABI stability guarantees (and
   they don't need it anyway since they're statically linking) at near peak
   performance assuming a sufficiently advanced toolchain thanks to LTO allowing
   optimization to occur across module boundaries etc.
 * Chooses to link dynamically - they get full stability guarantees at a slight
   performance cost at the boundary between their code and the shared library.

Similarly, much of the stable middle and bottom implementation layer can be
optimized down even under normal circumstances without full LTO, as the compiler
will potentially have full visibility across both layers on compilation (though
LTO would help here also).

A naive intuition may lead you to believe that an hourglass model leads to
inherent performance degradation, but thanks to modern advances in build tooling
this does not necessarily need to be the case.

# <a name="abi">Avoiding ABI Breakage</a>

When designing an hourglass API -- and indeed a C API in general -- if you want
to achieve some level of ABI stability, then you need to be extremely careful
about what changes you make, and what language features you take advantage of.
This is a very thorny topic, and probably deserves an article in and of itself,
so instead we will focus on a few core gotchas to be aware of when you want to
achieve ABI stability.

## <a name="abi-struct-layout">Struct Size & Layout Changes</a>

Much of the interfacing between the client layer and the C API firewall layer
involves passing around opaque data. This data needs to have be stable in order
to meaningfully offer ABI guarantees across versions of the library. This means
that the specific language features used in your APIs, and the changes you make
in implementation can have an impact on whether this stability is maintained.

If the size of the data-types are statically visible to the client, even if
opaque, it is entirely within the realm of possibility that adding new fields to
these data-types (or their constituent members recursively) can cause
significant breakage. A common workaround for this is to preemptively add unused
fields of sufficient size to the data-types, such that new data can be added
without breaking client code. For example:
```c
/* Assume packed */
struct A
{
    int x;
    /* These 16 bytes are now free to be replaced with real data */
    char _unused[16];
    int y;
};
```

An alternative workaround is to make the data-types opaque, and instead make the
the size a run-time value retrieved from the API. This is a technique we used
earlier in the performance section in order to achieve full memory layout
control on the client-side without exposing the internal structure of the
data-types.

If the layout of the data-types are visible to the client (i.e. non-opaque), it
is a breaking change to re-order data-members. This is because any code that
attempted to access the data-members based on the internal order will no longer
be touching correct offsets. Sufficiently firewalled, opaque data-types don't
suffer from this limitation, as the only code accessing data members is the
library itself, which is by definition compatible.

Fortunately there usually isn't much reason to reorder data members between
library versions, however it is worth taking into account that details of how
the implementation language (such as C++ arranging vtables etc.) organizes data
could potentially cause issues here at some deeper member of the relevant
data-type provided insufficient implemetation/API firewalling.

It is worth noting, that these ABI guarantees are not provided should the client
library go out of their way to invasively access or retain the contents of any
passed around library data (e.g. serialize a struct for access in a later run
against a new library).


## <a name="abi-arg-return">API Argument/Return Value Changes</a>

The most obvious ABI breaking change is if you add/remove API functions or
data-types, or alternatively change parameter lists or return types. I shouldn't
have to explain why making the client application attempt to call a function
with the wrong argument list will break client applications. This can cause
rather fantastical behavior.

Perhaps less obvious is the concern of run-time values. For instance, imagine we
have a function which returns an error result value. Altering the potential list
of return values can break expectations of the client applications, causing them
to enter an unexpected state if insufficiently defensively written. As an
example, going from:
```c
#define LIBFOO_SUCCESS 0
#define LIBFOO_NO_MEM 1

typedef unsigned int libfoo_result;

/* Can return SUCCESS or NO_MEM */
libfoo_result libfoo_do_xyz();
```
to:
```c
#define LIBFOO_SUCCESS 0
#define LIBFOO_NO_MEM 1
#define LIBFOO_RESOURCE_LOCKED 2

typedef unsigned int libfoo_result;

/* Can return SUCCESS or NO_MEM or RESOURCE_LOCKED */
libfoo_result libfoo_do_xyz();
```

is a breaking change, as the set of return values has changed. As a result any
code which operated assuming only the prior two return values were possible,
could potentially be rendered irreconcilably broken.

By extension, behavioral changes in general can, while remaining ABI stability
conserving, still be client breaking. For example, if an application assumes a
certain behavior from the library, but a new version of the library no longer
behaves in exactly the same way, it is entirely possible that the clients will
no longer be well-behaved. This is much more challenging to avoid than every
other type of breakage in a library due to the wide-reaching impact of Hyrum's
law [^4].


# <a name="closing">Closing Thoughts</a>

All-in-all, the hourglass pattern makes a fantastic addition to your library
design toolbox. It's not always worth the additional overhead of code to use,
but when you need it, but when you need it, it's incredibly powerful.

There are many design decisions that need to be made in order to keep efficiency
while also maintaining ABI stability, and these decisions can have profound
effects on the way the API is designed and structured.

I wish you luck the next time you see the need to use an hourglass API, and hope
the discussion here can help you in your journey.
Until next time!


[^1]: See [CppCon 2014: Hourglass APIs for C++ - Stefanus DuToit](https://www.youtube.com/watch?v=PVYdHDm0q6Y) for a more in-depth coverage of the concept.

[^2]: See [Designing and Evaluating Reusable Components - Casey Muratori (2005)](https://caseymuratori.com/blog_0024).

[^3]: See [LLVM LTO](https://llvm.org/docs/LinkTimeOptimization.html).

[^4]: See [Hyrum's Law](https://www.hyrumslaw.com/).
